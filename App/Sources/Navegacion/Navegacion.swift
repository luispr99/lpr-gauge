import Combine
import CoreLocation
import Foundation
import FerrostarCore
import FerrostarCoreFFI

/// Navegación giro a giro con Ferrostar y Valhalla (docs/DECISIONES.md).
/// Busca el destino con Nominatim, pide la ruta en moto (sin peajes, en
/// español) al servidor Valhalla configurado y publica la maniobra, los metros
/// que faltan y la altitud del GPS.
///
/// De momento solo en primer plano y solo en la pantalla del iPhone: el envío al
/// cuadro (NAV y GPS) y el segundo plano llegan en los pasos siguientes.
@MainActor
final class Navegacion: ObservableObject {
    @Published var consulta = ""
    @Published private(set) var resultados: [ResultadoBusqueda] = []
    @Published private(set) var buscando = false
    @Published private(set) var calculando = false
    @Published private(set) var aviso: String?

    @Published private(set) var navegando = false
    @Published private(set) var llegada = false
    @Published private(set) var destino: ResultadoBusqueda?
    @Published private(set) var maniobra: Maniobra?
    @Published private(set) var metrosAlGiro: Double?
    @Published private(set) var metrosRestantes: Double?
    @Published private(set) var segundosRestantes: Double?
    @Published private(set) var fueraDeRuta = false
    @Published private(set) var recalculando = false

    /// Altitud del GPS (metros sobre el nivel del mar) y su precisión; nil sin dato.
    @Published private(set) var altitud: Double?
    @Published private(set) var precisionVertical: Double?
    @Published private(set) var hayPosicion = false

    private let ubicacion = ProveedorUbicacion()
    private let buscador = BuscadorNominatim()
    private var nucleo: FerrostarCore?
    private var suscripcion: AnyCancellable?

    init() {
        ubicacion.alCambiar = { [weak self] posicion in
            MainActor.assumeIsolated {
                self?.posicionNueva(posicion)
            }
        }
        ubicacion.startUpdating()
    }

    // MARK: - Búsqueda

    func buscar() {
        let texto = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !buscando else { return }
        buscando = true
        aviso = nil
        Task {
            defer { self.buscando = false }
            do {
                let encontrados = try await buscador.buscar(texto)
                resultados = encontrados
                if encontrados.isEmpty {
                    aviso = "No se ha encontrado nada para «\(texto)»"
                }
            } catch {
                aviso = "Error al buscar: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Navegación

    func navegar(a destino: ResultadoBusqueda) {
        guard !calculando else { return }
        guard let origen = ubicacion.lastLocation else {
            aviso = "Todavía no hay posición GPS. Espera unos segundos y vuelve a intentarlo."
            return
        }
        calculando = true
        aviso = nil
        Task {
            defer { self.calculando = false }
            do {
                let nucleo = try crearNucleo()
                let punto = Waypoint(
                    coordinate: GeographicCoordinate(lat: destino.latitud, lng: destino.longitud),
                    kind: .break
                )
                let rutas = try await nucleo.getRoutes(initialLocation: origen, waypoints: [punto])
                guard let ruta = rutas.first else {
                    aviso = "El servidor no ha devuelto ninguna ruta"
                    return
                }
                try nucleo.startNavigation(route: ruta)
                self.nucleo = nucleo
                self.destino = destino
                navegando = true
                llegada = false
                resultados = []
                suscripcion = nucleo.$state
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] estado in
                        MainActor.assumeIsolated {
                            self?.actualizar(estado)
                        }
                    }
            } catch {
                aviso = "No se pudo calcular la ruta: \(error.localizedDescription)"
            }
        }
    }

    func terminar() {
        nucleo?.stopNavigation()
        nucleo = nil
        suscripcion = nil
        navegando = false
        llegada = false
        destino = nil
        maniobra = nil
        metrosAlGiro = nil
        metrosRestantes = nil
        segundosRestantes = nil
        fueraDeRuta = false
        recalculando = false
        // stopNavigation() también para la ubicación: se reanuda para la altitud
        ubicacion.startUpdating()
    }

    private func crearNucleo() throws -> FerrostarCore {
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
        // Moto, sin peajes y con las instrucciones en español, como en
        // valhalla.openstreetmap.de (profile=motorcycle, use_tolls=0, lang=es-ES)
        let opciones: [String: Any] = [
            "language": "es-ES",
            "units": "kilometers",
            "costing_options": ["motorcycle": ["use_tolls": 0]],
        ]
        let proveedor = try WellKnownRouteProvider
            .valhalla(endpointUrl: Servidores.rutas, profile: "motorcycle")
            .withJsonOptions(options: opciones)
        return try FerrostarCore(
            wellKnownRouteProvider: proveedor,
            locationProvider: ubicacion,
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
        hayPosicion = true
        if posicion.verticalAccuracy > 0 {
            altitud = posicion.altitude
            precisionVertical = posicion.verticalAccuracy
        } else {
            altitud = nil
            precisionVertical = nil
        }
    }
}
