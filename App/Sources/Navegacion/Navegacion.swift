import Combine
import CoreLocation
import Foundation
import MapKit
import FerrostarCore
import FerrostarCoreFFI

/// Variantes de ruta que se calculan al elegir el destino (opciones de la moto en
/// Valhalla). Valhalla no mide las curvas: «Por secundarias» se aproxima
/// evitando autovías (use_highways = 0) y prefiriendo carreteras secundarias
/// (use_trails = 0,5). Todas sin peajes.
enum TipoVariante: String, CaseIterable, Identifiable {
    case rapida
    case secundarias
    case corta

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .rapida: return "Más rápida"
        case .secundarias: return "Por secundarias"
        case .corta: return "Más corta"
        }
    }

    var opcionesMoto: [String: Any] {
        switch self {
        case .rapida: return ["use_tolls": 0]
        case .secundarias: return ["use_tolls": 0, "use_highways": 0, "use_trails": 0.5]
        case .corta: return ["use_tolls": 0, "shortest": true]
        }
    }
}

/// Una ruta propuesta, para previsualizarla en el mapa antes de empezar.
struct VarianteRuta: Identifiable {
    let tipo: TipoVariante
    let ruta: Route
    let geometria: [CLLocationCoordinate2D]

    var id: TipoVariante { tipo }
    var metros: Double { ruta.distance }
    var segundos: Double { ruta.steps.reduce(0) { $0 + $1.duration } }
}

/// Navegación giro a giro con Ferrostar y Valhalla (docs/DECISIONES.md).
/// Busca el destino con Apple Maps, propone variantes de ruta en moto (sin
/// peajes, en español) y, al iniciar, publica la maniobra, los metros que faltan
/// y la altitud del GPS.
///
/// De momento solo en primer plano y solo en la pantalla del iPhone: el envío al
/// cuadro (NAV y GPS) y el segundo plano llegan en los pasos siguientes.
@MainActor
final class Navegacion: ObservableObject {
    // MARK: Búsqueda
    @Published var consulta = ""
    @Published private(set) var sugerencias: [MKLocalSearchCompletion] = []
    @Published private(set) var aviso: String?

    // MARK: Rutas propuestas
    @Published private(set) var destino: ResultadoBusqueda?
    @Published private(set) var variantes: [VarianteRuta] = []
    @Published var elegida: TipoVariante = .rapida
    @Published private(set) var calculando = false

    // MARK: Guiado
    @Published private(set) var navegando = false
    @Published private(set) var llegada = false
    @Published private(set) var maniobra: Maniobra?
    @Published private(set) var metrosAlGiro: Double?
    @Published private(set) var metrosRestantes: Double?
    @Published private(set) var segundosRestantes: Double?
    @Published private(set) var fueraDeRuta = false
    @Published private(set) var recalculando = false

    /// Para el mapa del guiado: la ruta, la posición (ajustada a la ruta si se va
    /// por ella), el rumbo y el punto del próximo giro.
    @Published private(set) var geometriaRuta: [CLLocationCoordinate2D] = []
    @Published private(set) var posicionEnRuta: CLLocationCoordinate2D?
    @Published private(set) var rumbo: Double?
    @Published private(set) var puntoGiro: CLLocationCoordinate2D?

    /// Simulación: en vez del GPS, una posición que recorre la ruta sola, para ver
    /// cambiar las indicaciones sin moverse. Avanza 10 m por paso, y cada paso
    /// dura 1 s dividido por el factor de velocidad (factor 1 = 36 km/h).
    @Published var simular = false
    @Published var factorSimulacion: UInt64 = 2
    @Published private(set) var simulando = false

    // MARK: GPS
    /// Altitud del GPS (metros sobre el nivel del mar) y su precisión; nil sin dato.
    @Published private(set) var altitud: Double?
    @Published private(set) var precisionVertical: Double?
    @Published private(set) var posicionActual: CLLocationCoordinate2D?

    private let ubicacion = ProveedorUbicacion()
    private let buscador = BuscadorApple()
    private var nucleo: FerrostarCore?
    private var simulador: SimulatedLocationProvider?
    private var suscripcion: AnyCancellable?

    init() {
        ubicacion.alCambiar = { [weak self] posicion in
            MainActor.assumeIsolated {
                self?.posicionNueva(posicion)
            }
        }
        buscador.alCambiar = { [weak self] resultados in
            self?.sugerencias = resultados
        }
        buscador.alFallar = { [weak self] _ in
            self?.sugerencias = []
        }
        ubicacion.startUpdating()
    }

    // MARK: - Búsqueda

    /// Lo llama la vista cada vez que cambia el texto. Las sugerencias de Apple se
    /// pueden pedir mientras se escribe.
    func consultaCambiada() {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        if texto.isEmpty {
            sugerencias = []
        } else {
            buscador.sugerir(texto, cercaDe: posicionActual)
        }
    }

    func elegir(_ sugerencia: MKLocalSearchCompletion) {
        aviso = nil
        sugerencias = []
        Task {
            do {
                let lugar = try await buscador.resolver(sugerencia)
                consulta = lugar.nombre
                destino = lugar
                await calcularVariantes(hacia: lugar)
            } catch {
                aviso = "No se pudo localizar el lugar: \(error.localizedDescription)"
            }
        }
    }

    func cancelarRuta() {
        destino = nil
        variantes = []
        consulta = ""
        sugerencias = []
        aviso = nil
    }

    private func calcularVariantes(hacia lugar: ResultadoBusqueda) async {
        guard let origen = ubicacion.lastLocation else {
            aviso = "Todavía no hay posición GPS. Espera unos segundos y vuelve a elegir el destino."
            return
        }
        calculando = true
        defer { calculando = false }
        variantes = []
        let punto = Waypoint(
            coordinate: GeographicCoordinate(lat: lugar.latitud, lng: lugar.longitud),
            kind: .break
        )
        var nuevas: [VarianteRuta] = []
        for (indice, tipo) in TipoVariante.allCases.enumerated() {
            // El servidor de FOSSGIS admite como mucho una petición por segundo
            if indice > 0 {
                try? await Task.sleep(for: .seconds(1.1))
            }
            // Si mientras tanto se ha elegido otro destino o se ha cancelado, se para
            guard destino == lugar else { return }
            do {
                let nucleo = try crearNucleo(variante: tipo, ubicacion: ubicacion)
                guard let ruta = try await nucleo.getRoutes(initialLocation: origen, waypoints: [punto]).first
                else { continue }
                let geometria = ruta.geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                // Si sale igual que una anterior, no se repite
                let repetida = nuevas.contains {
                    abs($0.metros - ruta.distance) < 1 && $0.geometria.count == geometria.count
                }
                if !repetida {
                    nuevas.append(VarianteRuta(tipo: tipo, ruta: ruta, geometria: geometria))
                    variantes = nuevas
                    if nuevas.count == 1 {
                        elegida = tipo
                    }
                }
            } catch {
                aviso = "No se pudo calcular «\(tipo.nombre)»: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Navegación

    func iniciar() {
        guard let variante = variantes.first(where: { $0.tipo == elegida }) ?? variantes.first else { return }
        aviso = nil
        do {
            // Con simulación, Ferrostar recibe las posiciones del simulador en vez
            // de las del GPS; la altitud sigue saliendo del GPS real
            let simulador = simular ? SimulatedLocationProvider() : nil
            let fuente: LocationProviding
            if let simulador {
                fuente = simulador
            } else {
                fuente = ubicacion
            }
            let nucleo = try crearNucleo(variante: variante.tipo, ubicacion: fuente)
            if let simulador {
                try simulador.setSimulatedRoute(variante.ruta, resampleDistance: 10)
                simulador.warpFactor = max(1, factorSimulacion)
            }
            try nucleo.startNavigation(route: variante.ruta)
            self.nucleo = nucleo
            self.simulador = simulador
            simulando = simulador != nil
            navegando = true
            llegada = false
            suscripcion = nucleo.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] estado in
                    MainActor.assumeIsolated {
                        self?.actualizar(estado)
                    }
                }
        } catch {
            aviso = "No se pudo empezar la navegación: \(error.localizedDescription)"
        }
    }

    func terminar() {
        nucleo?.stopNavigation()
        nucleo = nil
        // El simulador guarda una referencia fuerte a Ferrostar: se suelta aquí
        simulador?.stopUpdating()
        simulador?.delegate = nil
        simulador = nil
        simulando = false
        suscripcion = nil
        navegando = false
        llegada = false
        maniobra = nil
        metrosAlGiro = nil
        metrosRestantes = nil
        segundosRestantes = nil
        fueraDeRuta = false
        recalculando = false
        geometriaRuta = []
        posicionEnRuta = nil
        rumbo = nil
        puntoGiro = nil
        cancelarRuta()
        // stopNavigation() también para la ubicación: se reanuda para la posición
        // y la altitud
        ubicacion.startUpdating()
    }

    private func crearNucleo(variante: TipoVariante, ubicacion fuente: LocationProviding) throws -> FerrostarCore {
        // Valores de la app de demostración de Ferrostar 0.57.0 (DemoModel.swift)
        let configuracion = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 30,
                distanceAfterEndOfStep: 5,
                minimumHorizontalAccuracy: 32
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(
                distance: 10,
                minimumHorizontalAccuracy: 32
            ),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 15, maxAcceptableDeviation: 50),
            snappedLocationCourseFiltering: .snapToRoute
        )
        // Moto, con las instrucciones en español y las opciones de la variante. Al
        // recalcular por desvío se usan las mismas opciones
        let opciones: [String: Any] = [
            "language": "es-ES",
            "units": "kilometers",
            "costing_options": ["motorcycle": variante.opcionesMoto],
        ]
        let proveedor = try WellKnownRouteProvider
            .valhalla(endpointUrl: Servidores.rutas, profile: "motorcycle")
            .withJsonOptions(options: opciones)
        return try FerrostarCore(
            wellKnownRouteProvider: proveedor,
            locationProvider: fuente,
            navigationControllerConfig: configuracion,
            networkSession: ClienteRutas(),
            // La app no habla: las indicaciones van a la pantalla y al cuadro
            spokenInstructionObserver: .initAVSpeechSynthesizer(isMuted: true)
        )
    }

    private func actualizar(_ estado: NavigationState?) {
        guard let estado else { return }
        recalculando = estado.isCalculatingNewRoute
        if let progreso = estado.currentProgress {
            metrosAlGiro = progreso.distanceToNextManeuver
            metrosRestantes = progreso.distanceRemaining
            segundosRestantes = progreso.durationRemaining
        }
        if let visual = estado.currentVisualInstruction {
            let principal = visual.primaryContent
            // Según el código de Valhalla, el número de salida de la próxima
            // rotonda va en el paso siguiente (sin probar con una ruta real)
            let salida = (estado.remainingSteps?.dropFirst().first)?.roundaboutExitNumber
            maniobra = Maniobra(
                tipo: principal.maneuverType,
                modificador: principal.maneuverModifier,
                gradosRotonda: principal.roundaboutExitDegrees,
                salidaRotonda: salida,
                texto: principal.text
            )
        }

        // Datos del mapa. La geometría solo cambia al recalcular la ruta
        let ruta = estado.routeGeometry
        let rutaCambiada = ruta.count != geometriaRuta.count
            || ruta.last?.lat != geometriaRuta.last?.latitude
            || ruta.last?.lng != geometriaRuta.last?.longitude
        if rutaCambiada {
            geometriaRuta = ruta.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
        if let yo = estado.preferredUserLocation {
            posicionEnRuta = CLLocationCoordinate2D(latitude: yo.coordinates.lat, longitude: yo.coordinates.lng)
            if let curso = yo.courseOverGround {
                rumbo = Double(curso.degrees)
            }
        }
        if let fin = estado.currentStep?.geometry.last {
            puntoGiro = CLLocationCoordinate2D(latitude: fin.lat, longitude: fin.lng)
        }

        if case .deviation? = estado.currentDeviation {
            fueraDeRuta = true
        } else {
            fueraDeRuta = false
        }
        if case .complete = estado.tripState {
            llegada = true
        }
    }

    private func posicionNueva(_ posicion: CLLocation) {
        posicionActual = posicion.coordinate
        if posicion.verticalAccuracy > 0 {
            altitud = posicion.altitude
            precisionVertical = posicion.verticalAccuracy
        } else {
            altitud = nil
            precisionVertical = nil
        }
    }
}
