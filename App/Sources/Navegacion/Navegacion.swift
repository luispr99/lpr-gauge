import Combine
import CoreLocation
import Foundation
import MapKit
import FerrostarCore
import FerrostarCoreFFI
import LPRCore

/// Las dos propuestas al elegir destino (docs/DECISIONES.md): la que menos
/// tarda y la de más curvas sin pasarse de tiempo. Valhalla no mide las curvas:
/// las cuenta la app sobre el trazado (LPRCore, Curvas.swift).
enum TipoVariante: String, CaseIterable, Identifiable {
    case rapida
    case divertida

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .rapida: return "La más rápida"
        case .divertida: return "La más divertida"
        }
    }
}

/// Peticiones a Valhalla de las que salen las candidatas, cada una con hasta dos
/// alternativas: la normal de la moto y otra que evita autovías y prefiere
/// carreteras secundarias, de donde suelen salir las rutas con más curvas.
private enum PeticionRutas: CaseIterable {
    case normal
    case secundarias
}

/// Claves de las preferencias de ruta en UserDefaults.
private enum ClavePreferencia {
    static let evitarPeajes = "rutas.evitarPeajes"
    static let evitarAutopistas = "rutas.evitarAutopistas"
    static let soloAsfalto = "rutas.soloAsfalto"

    static func valor(_ clave: String, porDefecto: Bool) -> Bool {
        UserDefaults.standard.object(forKey: clave) as? Bool ?? porDefecto
    }
}

/// Una ruta propuesta, para previsualizarla en el mapa antes de empezar.
struct VarianteRuta: Identifiable {
    let tipo: TipoVariante
    let ruta: Route
    let geometria: [CLLocationCoordinate2D]
    let sinuosidad: Sinuosidad
    /// Opciones de la moto con las que salió; al recalcular por desvío se usan
    /// las mismas.
    let opcionesMoto: [String: Any]

    var id: TipoVariante { tipo }
    var metros: Double { ruta.distance }
    var segundos: Double { VarianteRuta.segundos(ruta) }
    var curvas: Int { sinuosidad.curvas }

    static func segundos(_ ruta: Route) -> Double {
        ruta.steps.reduce(0) { $0 + $1.duration }
    }

    /// Curvas de la ruta. Cada paso se mide por separado, para no contar los giros
    /// de los cruces, y se saltan las rotondas (pasos cortos con número de
    /// salida), que si no contarían como curva.
    static func sinuosidad(_ ruta: Route) -> Sinuosidad {
        let tramos = ruta.steps
            .filter { paso in !(paso.roundaboutExitNumber != nil && paso.distance < 300) }
            .map { paso in paso.geometry.map { PuntoRuta(latitud: $0.lat, longitud: $0.lng) } }
        return Curvas.medir(tramos: tramos)
    }
}

/// Navegación giro a giro con Ferrostar y Valhalla (docs/DECISIONES.md).
/// Busca el destino con Apple Maps, propone la ruta más rápida y la más
/// divertida en moto (con las preferencias de peajes, autopistas y asfalto, en
/// español) y, al iniciar, publica la maniobra, los metros que faltan y la
/// altitud del GPS.
///
/// De momento solo en primer plano y solo en la pantalla del iPhone: el envío al
/// cuadro (NAV y GPS) y el segundo plano llegan en los pasos siguientes.
@MainActor
final class Navegacion: ObservableObject {
    // MARK: Búsqueda
    @Published var consulta = ""
    @Published private(set) var sugerencias: [MKLocalSearchCompletion] = []
    @Published private(set) var aviso: String?

    // MARK: Preferencias de ruta
    /// Se guardan entre usos. Valhalla las trata como preferencias, no como
    /// prohibiciones: si no hay otro camino, la ruta puede llevar algún tramo.
    @Published var evitarPeajes = ClavePreferencia.valor(ClavePreferencia.evitarPeajes, porDefecto: true) {
        didSet { preferenciaCambiada(ClavePreferencia.evitarPeajes, evitarPeajes) }
    }
    @Published var evitarAutopistas = ClavePreferencia.valor(ClavePreferencia.evitarAutopistas, porDefecto: false) {
        didSet { preferenciaCambiada(ClavePreferencia.evitarAutopistas, evitarAutopistas) }
    }
    @Published var soloAsfalto = ClavePreferencia.valor(ClavePreferencia.soloAsfalto, porDefecto: false) {
        didSet { preferenciaCambiada(ClavePreferencia.soloAsfalto, soloAsfalto) }
    }

    // MARK: Rutas propuestas
    @Published private(set) var destino: ResultadoBusqueda?
    @Published private(set) var variantes: [VarianteRuta] = []
    @Published var elegida: TipoVariante = .rapida
    @Published private(set) var calculando = false
    /// La más rápida es también la de más curvas dentro del margen de tiempo: se
    /// muestra una sola.
    @Published private(set) var rapidaEsLaDivertida = false

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

    /// Cálculo de rutas en curso. Cada cálculo nuevo cancela el anterior; la
    /// generación evita que uno viejo pise los datos del nuevo.
    private var tareaVariantes: Task<Void, Never>?
    private var generacion = 0
    /// Momento de la última petición de rutas, para no pasar de una por segundo.
    private var ultimaPeticion: ContinuousClock.Instant?

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
                pedirVariantes(hacia: lugar)
            } catch {
                aviso = "No se pudo localizar el lugar: \(error.localizedDescription)"
            }
        }
    }

    func cancelarRuta() {
        tareaVariantes?.cancel()
        tareaVariantes = nil
        generacion += 1
        calculando = false
        destino = nil
        variantes = []
        rapidaEsLaDivertida = false
        consulta = ""
        sugerencias = []
        aviso = nil
    }

    // MARK: - Rutas propuestas

    private func preferenciaCambiada(_ clave: String, _ valor: Bool) {
        UserDefaults.standard.set(valor, forKey: clave)
        // Con un destino elegido, se vuelven a pedir las rutas con las nuevas
        // preferencias
        if let destino, !navegando {
            pedirVariantes(hacia: destino)
        }
    }

    /// Opciones de la moto para Valhalla según las preferencias y la petición
    /// [F33]. Todas son preferencias: las exclusiones estrictas de peajes y
    /// autopistas dependen de la configuración del servidor.
    private func opcionesMoto(_ peticion: PeticionRutas) -> [String: Any] {
        var opciones: [String: Any] = [:]
        if evitarPeajes {
            opciones["use_tolls"] = 0
        }
        if evitarAutopistas {
            opciones["use_highways"] = 0
        }
        if soloAsfalto {
            // Sin tierra en mitad de la ruta, y evitando pistas y firmes malos
            opciones["exclude_unpaved"] = true
            opciones["use_trails"] = 0
        }
        if peticion == .secundarias {
            opciones["use_highways"] = 0
            // Hacia 1 evita las carreteras principales y va por secundarias; con
            // «solo asfalto» se queda en 0, porque también abre pistas
            if !soloAsfalto {
                opciones["use_trails"] = 0.5
            }
        }
        return opciones
    }

    private func pedirVariantes(hacia lugar: ResultadoBusqueda) {
        tareaVariantes?.cancel()
        generacion += 1
        let esta = generacion
        tareaVariantes = Task { [weak self] in
            await self?.calcularVariantes(hacia: lugar, generacion: esta)
        }
    }

    /// El servidor de FOSSGIS admite como mucho una petición por segundo [F20].
    private func esperarTurno() async {
        guard let ultimaPeticion else { return }
        let espera = ContinuousClock.now.duration(to: ultimaPeticion.advanced(by: .milliseconds(1100)))
        if espera > .zero {
            try? await Task.sleep(for: espera)
        }
    }

    private func calcularVariantes(hacia lugar: ResultadoBusqueda, generacion esta: Int) async {
        guard let origen = ubicacion.lastLocation else {
            aviso = "Todavía no hay posición GPS. Espera unos segundos y vuelve a elegir el destino."
            return
        }
        calculando = true
        defer {
            if generacion == esta {
                calculando = false
            }
        }
        aviso = nil
        variantes = []
        rapidaEsLaDivertida = false
        let punto = Waypoint(
            coordinate: GeographicCoordinate(lat: lugar.latitud, lng: lugar.longitud),
            kind: .break
        )

        var rutas: [(ruta: Route, opcionesMoto: [String: Any])] = []
        for peticion in PeticionRutas.allCases {
            await esperarTurno()
            // Si mientras tanto se ha pedido otro cálculo o se ha cancelado, se para
            guard generacion == esta else { return }
            let opciones = opcionesMoto(peticion)
            do {
                let nucleo = try crearNucleo(opcionesMoto: opciones, alternativas: 2, ubicacion: ubicacion)
                ultimaPeticion = .now
                let nuevas = try await nucleo.getRoutes(initialLocation: origen, waypoints: [punto])
                guard generacion == esta else { return }
                rutas += nuevas.map { (ruta: $0, opcionesMoto: opciones) }
            } catch {
                guard generacion == esta else { return }
                aviso = "No se pudieron calcular todas las rutas: \(error.localizedDescription)"
            }
        }

        let candidatas = rutas.map {
            Candidata(segundos: VarianteRuta.segundos($0.ruta), sinuosidad: VarianteRuta.sinuosidad($0.ruta))
        }
        guard let eleccion = Curvas.elegir(candidatas) else {
            if aviso == nil {
                aviso = "No se encontró ninguna ruta."
            }
            return
        }
        func variante(_ tipo: TipoVariante, _ indice: Int) -> VarianteRuta {
            let ruta = rutas[indice].ruta
            return VarianteRuta(
                tipo: tipo,
                ruta: ruta,
                geometria: ruta.geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
                sinuosidad: candidatas[indice].sinuosidad,
                opcionesMoto: rutas[indice].opcionesMoto
            )
        }
        var nuevas = [variante(.rapida, eleccion.rapida)]
        if eleccion.divertida != eleccion.rapida {
            nuevas.append(variante(.divertida, eleccion.divertida))
        }
        rapidaEsLaDivertida = eleccion.divertida == eleccion.rapida
        elegida = .rapida
        variantes = nuevas
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
            let nucleo = try crearNucleo(opcionesMoto: variante.opcionesMoto, alternativas: 0, ubicacion: fuente)
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

    /// `alternativas`: cuántas rutas alternativas pedir a Valhalla además de la
    /// principal (0 para guiar, porque al recalcular solo se usa la primera).
    private func crearNucleo(
        opcionesMoto: [String: Any],
        alternativas: Int,
        ubicacion fuente: LocationProviding
    ) throws -> FerrostarCore {
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
        // Moto, con las instrucciones en español y las opciones de la ruta. Al
        // recalcular por desvío se usan las mismas opciones
        var opciones: [String: Any] = [
            "language": "es-ES",
            "units": "kilometers",
            "costing_options": ["motorcycle": opcionesMoto],
        ]
        if alternativas > 0 {
            opciones["alternates"] = alternativas
        }
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
