import Combine
import CoreLocation
import Foundation
import MapKit
import FerrostarCore
import FerrostarCoreFFI
import LPRCore

/// Las propuestas al elegir destino (docs/DECISIONES.md): la que menos tarda,
/// la de más curvas y, sin «Solo asfalto», la de más tierra; las dos últimas
/// sin pasar del margen de tiempo de la barra. Valhalla no mide las curvas: las
/// cuenta la app sobre el trazado (LPRCore, Curvas.swift).
enum TipoVariante: String, CaseIterable, Identifiable {
    case rapida
    case divertida
    case tierra

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .rapida: return "La más rápida"
        case .divertida: return "Mayor cantidad de curvas"
        case .tierra: return "Por tierra"
        }
    }

    var icono: String {
        switch self {
        case .rapida: return "hare.fill"
        case .divertida: return "road.lanes.curved.right"
        case .tierra: return "mountain.2.fill"
        }
    }
}

/// Peticiones a Valhalla de las que salen las candidatas, cada una con hasta dos
/// alternativas.
private enum TipoPeticion {
    /// Las opciones normales de la moto, con las preferencias.
    case normal
    /// Además evita autovías, de donde suelen salir las rutas con más curvas.
    case secundarias
    /// Además prefiere pistas y tierra (solo sin «Solo asfalto»).
    case tierra
}

/// Claves de las preferencias de ruta en UserDefaults. «Solo asfalto» no se
/// guarda: se marca cada vez que se abre la app.
private enum ClavePreferencia {
    static let evitarPeajes = "rutas.evitarPeajes"
    static let evitarAutopistas = "rutas.evitarAutopistas"
    static let margenExtra = "rutas.margenExtra"

    static func valor(_ clave: String, porDefecto: Bool) -> Bool {
        UserDefaults.standard.object(forKey: clave) as? Bool ?? porDefecto
    }
}

/// Una ruta candidata: lo que devolvió Valhalla, la petición de la que salió y
/// su posición en la respuesta (0, la principal; después, las alternativas),
/// para pedirla otra vez a Ferrostar al empezar.
struct RutaCandidata {
    let ruta: RutaValhalla
    let peticion: PeticionRutas
    let indice: Int
    let sinuosidad: Sinuosidad
    let geometria: [CLLocationCoordinate2D]
    let trazo: TrazoMapa

    init(ruta: RutaValhalla, peticion: PeticionRutas, indice: Int) {
        self.ruta = ruta
        self.peticion = peticion
        self.indice = indice
        sinuosidad = Curvas.medir(tramos: ruta.tramosParaCurvas)
        geometria = ruta.puntos.map { CLLocationCoordinate2D(latitude: $0.latitud, longitude: $0.longitud) }
        trazo = TrazoMapa(geometria)
    }
}

/// Una ruta propuesta en el mapa. Puede tener varios papeles: la más rápida
/// puede ser también la más divertida.
struct VarianteRuta: Identifiable {
    let tipos: [TipoVariante]
    let candidata: RutaCandidata

    /// El papel principal, que da el color y el icono.
    var tipo: TipoVariante { tipos[0] }
    var id: TipoVariante { tipo }
    var nombre: String { tipos.map(\.nombre).joined(separator: " · ") }
    var metros: Double { candidata.ruta.metros }
    var segundos: Double { candidata.ruta.segundos }
    var curvas: Int { candidata.sinuosidad.curvas }
    var metrosPeaje: Double { candidata.ruta.metrosPeaje }
    var metrosAutopista: Double { candidata.ruta.metrosAutopista }
    var metrosSinAsfaltar: Double { candidata.ruta.metrosSinAsfaltar }
    var geometria: [CLLocationCoordinate2D] { candidata.geometria }
    var trazo: TrazoMapa { candidata.trazo }
}

/// Navegación giro a giro con Ferrostar y Valhalla (docs/DECISIONES.md).
/// Busca el destino con Apple Maps, propone rutas en moto según las
/// preferencias (peajes, autopistas, asfalto y margen de tiempo) y, al iniciar,
/// publica la maniobra, los metros que faltan y la altitud del GPS.
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
    /// Valhalla las trata como preferencias, no como prohibiciones: si no hay
    /// otro camino, la ruta puede llevar algún tramo (se avisa en cada ruta).
    @Published var evitarPeajes = ClavePreferencia.valor(ClavePreferencia.evitarPeajes, porDefecto: true) {
        didSet {
            UserDefaults.standard.set(evitarPeajes, forKey: ClavePreferencia.evitarPeajes)
            preferenciaCambiada()
        }
    }
    @Published var evitarAutopistas = ClavePreferencia.valor(ClavePreferencia.evitarAutopistas, porDefecto: false) {
        didSet {
            UserDefaults.standard.set(evitarAutopistas, forKey: ClavePreferencia.evitarAutopistas)
            preferenciaCambiada()
        }
    }
    /// Primera fase: solo rutas por carretera (decisión del autor, 2026-10-09).
    /// Sin botón: siempre activado, así que tampoco se propone «Por tierra».
    let soloAsfalto = true
    /// Tiempo extra admitido para la de más curvas (y la de tierra) sobre la más
    /// rápida (0,25 = un 25 % más), de 0 a 2. Cambiarlo no pide rutas nuevas:
    /// vuelve a elegir entre las candidatas.
    @Published var margenExtra = ClavePreferencia.margenGuardado() {
        didSet {
            UserDefaults.standard.set(margenExtra, forKey: ClavePreferencia.margenExtra)
            elegirVariantes()
        }
    }

    /// Botones − y + de la barra: al múltiplo de 25 % anterior o siguiente,
    /// entre 0 y 200 %.
    func cambiarMargen(pasos: Int) {
        let paso = 0.25
        let posicion = margenExtra / paso
        // Un pequeño margen para que 0,5 no cuente como «entre» 0,25 y 0,5
        let nuevo = pasos > 0
            ? (floor(posicion + 1e-6) + Double(pasos)) * paso
            : (ceil(posicion - 1e-6) + Double(pasos)) * paso
        margenExtra = min(2, max(0, nuevo))
    }

    // MARK: Rutas propuestas
    @Published private(set) var destino: ResultadoBusqueda?
    @Published private(set) var variantes: [VarianteRuta] = []
    @Published var elegida: TipoVariante = .rapida
    @Published private(set) var calculando = false
    /// Sube cada vez que termina un cálculo de rutas (para encuadrar el mapa).
    @Published private(set) var calculos = 0
    /// Todas las candidatas llevan tierra en medio.
    @Published private(set) var sinRutaDeAsfalto = false
    /// Sin «Solo asfalto», ninguna candidata dentro del margen lleva tierra.
    @Published private(set) var sinRutaPorTierra = false
    /// Pidiendo la ruta elegida a Ferrostar para empezar.
    @Published private(set) var preparando = false

    // MARK: Guiado
    @Published private(set) var navegando = false
    @Published private(set) var llegada = false
    @Published private(set) var maniobra: Maniobra?
    @Published private(set) var metrosAlGiro: Double?
    @Published private(set) var metrosRestantes: Double?
    @Published private(set) var segundosRestantes: Double?
    @Published private(set) var fueraDeRuta = false
    @Published private(set) var recalculando = false
    /// Texto para la cara de navegación del cuadro (NAV_TEXT): la distancia al
    /// giro y, debajo, la instrucción; nil sin guiado. ContentView se lo pasa
    /// al enlace con la placa
    @Published private(set) var textoCuadro: String?

    /// Para el mapa del guiado: la ruta, la posición (ajustada a la ruta si se va
    /// por ella), el rumbo y el punto del próximo giro.
    @Published private(set) var geometriaRuta: [CLLocationCoordinate2D] = []
    @Published private(set) var posicionEnRuta: CLLocationCoordinate2D?
    @Published private(set) var rumbo: Double?
    @Published private(set) var puntoGiro: CLLocationCoordinate2D?

    /// Simulación: en vez del GPS, una posición que recorre la ruta sola, para ver
    /// cambiar las indicaciones sin moverse. El simulador de Ferrostar avanza un
    /// paso cada 1 s dividido por el factor de velocidad; con pasos de 50/3,6 m,
    /// el factor 1 son 50 km/h, el 2 100 y el 3 150 (a petición del autor).
    @Published var simular = false
    @Published var factorSimulacion: UInt64 = 2
    static let metrosPorPasoSimulacion = 50.0 / 3.6
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
    /// Geometría de la ruta del guiado, para saber cuándo cambia.
    private var geometriaGuiado: [GeographicCoordinate] = []

    /// Las candidatas del último cálculo, para volver a elegir sin pedir nada.
    private var candidatas: [RutaCandidata] = []
    /// Cálculo de rutas o inicio en curso. Cada cálculo nuevo cancela el
    /// anterior; la generación evita que uno viejo pise los datos del nuevo.
    private var tareaVariantes: Task<Void, Never>?
    private var tareaInicio: Task<Void, Never>?
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
        tareaInicio?.cancel()
        tareaInicio = nil
        generacion += 1
        calculando = false
        preparando = false
        destino = nil
        candidatas = []
        variantes = []
        sinRutaDeAsfalto = false
        sinRutaPorTierra = false
        consulta = ""
        sugerencias = []
        aviso = nil
    }

    // MARK: - Rutas propuestas

    private func preferenciaCambiada() {
        // Con un destino elegido, se vuelven a pedir las rutas
        if let destino, !navegando {
            pedirVariantes(hacia: destino)
        }
    }

    /// Opciones de la moto para Valhalla [F33]. Todas son preferencias: en moto
    /// Valhalla no permite excluir la tierra (ignora `exclude_unpaved`), y las
    /// exclusiones estrictas de peajes y autopistas dependen del servidor.
    private func opcionesMoto(_ peticion: TipoPeticion) -> [String: Any] {
        var opciones: [String: Any] = [:]
        if evitarPeajes {
            opciones["use_tolls"] = 0
        }
        if evitarAutopistas {
            opciones["use_highways"] = 0
        }
        if soloAsfalto {
            // La máxima penalización a firmes sin asfaltar y a pistas
            opciones["use_trails"] = 0
            opciones["use_tracks"] = 0
        }
        switch peticion {
        case .normal:
            break
        case .secundarias:
            opciones["use_highways"] = 0
        case .tierra:
            opciones["use_highways"] = 0
            opciones["use_trails"] = 1
            opciones["use_tracks"] = 1
        }
        return opciones
    }

    /// `aviso`: lo que se muestra mientras se calcula (por qué se recalcula).
    private func pedirVariantes(hacia lugar: ResultadoBusqueda, aviso avisoInicial: String? = nil) {
        tareaVariantes?.cancel()
        tareaInicio?.cancel()
        preparando = false
        generacion += 1
        let esta = generacion
        tareaVariantes = Task { [weak self] in
            await self?.calcularVariantes(hacia: lugar, generacion: esta, aviso: avisoInicial)
        }
    }

    /// El servidor de FOSSGIS admite como mucho una petición por segundo [F20].
    /// Si la tarea se cancela mientras espera, no cuenta como petición.
    private func esperarTurno() async {
        if let ultimaPeticion {
            let espera = ContinuousClock.now.duration(to: ultimaPeticion.advanced(by: .milliseconds(1100)))
            if espera > .zero {
                do {
                    try await Task.sleep(for: espera)
                } catch {
                    return
                }
            }
        }
        guard !Task.isCancelled else { return }
        ultimaPeticion = .now
    }

    private func calcularVariantes(
        hacia lugar: ResultadoBusqueda,
        generacion esta: Int,
        aviso avisoInicial: String?
    ) async {
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
        aviso = avisoInicial
        candidatas = []
        variantes = []
        sinRutaDeAsfalto = false
        sinRutaPorTierra = false
        let punto = Waypoint(
            coordinate: GeographicCoordinate(lat: lugar.latitud, lng: lugar.longitud),
            kind: .break
        )

        // Con «Evitar autopistas», la normal ya es la de secundarias: no se repite
        var tipos: [TipoPeticion] = [.normal]
        if !evitarAutopistas {
            tipos.append(.secundarias)
        }
        if !soloAsfalto {
            tipos.append(.tierra)
        }
        var nuevas: [RutaCandidata] = []
        for tipo in tipos {
            await esperarTurno()
            // Si mientras tanto se ha pedido otro cálculo o se ha cancelado, se para
            guard generacion == esta else { return }
            let peticion = PeticionRutas(opcionesMoto: opcionesMoto(tipo), alternativas: 2, origen: origen, destino: punto)
            do {
                let rutas = try await ClienteValhalla.rutasPropuestas(peticion)
                guard generacion == esta else { return }
                for (indice, ruta) in rutas.enumerated() {
                    // Las que salen iguales en varias peticiones, una sola vez
                    let repetida = nuevas.contains {
                        abs($0.ruta.metros - ruta.metros) < 1
                            && abs($0.ruta.segundos - ruta.segundos) < 1
                            && $0.ruta.puntos.count == ruta.puntos.count
                    }
                    if !repetida {
                        nuevas.append(RutaCandidata(ruta: ruta, peticion: peticion, indice: indice))
                    }
                }
            } catch {
                guard generacion == esta else { return }
                aviso = "No se pudieron calcular todas las rutas: \(error.localizedDescription)"
            }
        }

        candidatas = nuevas
        elegirVariantes()
        if variantes.isEmpty && aviso == nil {
            aviso = "No se encontró ninguna ruta."
        }
        calculos += 1
    }

    /// Elige las propuestas entre las candidatas con el margen actual (LPRCore,
    /// Eleccion.swift).
    private func elegirVariantes() {
        let entradas = candidatas.map {
            Candidata(
                segundos: $0.ruta.segundos,
                sinuosidad: $0.sinuosidad,
                metrosSinAsfaltar: $0.ruta.metrosSinAsfaltarEnMedio,
                tierraEnMedio: $0.ruta.tierraEnMedio
            )
        }
        guard let eleccion = Eleccion.elegir(entradas, margen: margenExtra, buscarTierra: !soloAsfalto) else {
            variantes = []
            sinRutaDeAsfalto = false
            sinRutaPorTierra = false
            return
        }
        // Una ruta con varios papeles sale una sola vez
        var papeles: [(indice: Int, tipos: [TipoVariante])] = []
        func anadir(_ indice: Int, _ tipo: TipoVariante) {
            if let posicion = papeles.firstIndex(where: { $0.indice == indice }) {
                papeles[posicion].tipos.append(tipo)
            } else {
                papeles.append((indice: indice, tipos: [tipo]))
            }
        }
        anadir(eleccion.rapida, .rapida)
        anadir(eleccion.divertida, .divertida)
        if let tierra = eleccion.porTierra {
            anadir(tierra, .tierra)
        }
        variantes = papeles.map { VarianteRuta(tipos: $0.tipos, candidata: candidatas[$0.indice]) }
        // Se mantiene la elegida si sigue entre las propuestas
        if !variantes.contains(where: { $0.tipos.contains(elegida) }) {
            elegida = .rapida
        }
        sinRutaDeAsfalto = eleccion.todasConTierra
        sinRutaPorTierra = !soloAsfalto && eleccion.porTierra == nil
    }

    // MARK: - Navegación

    func iniciar() {
        guard !preparando,
              let variante = variantes.first(where: { $0.tipos.contains(elegida) }) ?? variantes.first
        else { return }
        aviso = nil
        preparando = true
        let esta = generacion
        tareaInicio = Task { [weak self] in
            await self?.iniciar(variante, generacion: esta)
        }
    }

    /// Pide a Valhalla la ruta elegida en formato OSRM (la misma petición que la
    /// propuesta) y empieza a guiar con Ferrostar. Si ya no se está cerca de la
    /// ruta o el servidor devuelve otras rutas, no empieza: vuelve a calcular
    /// las propuestas y avisa.
    private func iniciar(_ variante: VarianteRuta, generacion esta: Int) async {
        guard generacion == esta else { return }
        defer {
            if generacion == esta {
                preparando = false
            }
        }
        let candidata = variante.candidata
        let simular = self.simular
        // Las rutas se piden desde la posición del momento de proponerlas. Si
        // desde entonces se ha alejado de la ruta, Ferrostar la daría por
        // desviada nada más empezar y recalcularía otra
        if !simular, let destino, seHaAlejado(de: candidata) {
            pedirVariantes(
                hacia: destino,
                aviso: "Te has alejado de la ruta desde que se calculó: se vuelven a calcular las rutas."
            )
            return
        }
        do {
            await esperarTurno()
            guard generacion == esta else { return }
            let rutas = try await ClienteValhalla.rutasFerrostar(candidata.peticion)
            guard generacion == esta, !navegando else { return }
            guard let ruta = Self.emparejar(candidata, en: rutas) else {
                let aviso = "Las rutas han cambiado en el servidor desde que se calcularon. Se vuelven a calcular: elige otra vez y pulsa «Iniciar»."
                if let destino {
                    pedirVariantes(hacia: destino, aviso: aviso)
                } else {
                    self.aviso = aviso
                }
                return
            }

            // Con simulación, Ferrostar recibe las posiciones del simulador en vez
            // de las del GPS; la altitud sigue saliendo del GPS real
            let simulador = simular ? SimulatedLocationProvider() : nil
            let fuente: LocationProviding
            if let simulador {
                fuente = simulador
            } else {
                fuente = ubicacion
            }
            let nucleo = try crearNucleo(
                proveedor: candidata.peticion.proveedor(alternativas: 0),
                ubicacion: fuente
            )
            if let simulador {
                try simulador.setSimulatedRoute(ruta, resampleDistance: Self.metrosPorPasoSimulacion)
                simulador.warpFactor = max(1, factorSimulacion)
            }
            try nucleo.startNavigation(route: ruta)
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
            guard generacion == esta else { return }
            aviso = "No se pudo empezar la navegación: \(error.localizedDescription)"
        }
    }

    /// La ruta de Ferrostar que corresponde a la propuesta: la de la misma
    /// posición si coincide en distancia y tiempo; si no, otra que coincida. Nil
    /// si ninguna coincide (por ejemplo, porque el servidor ha cargado datos
    /// nuevos o ha devuelto menos alternativas).
    static func emparejar(_ candidata: RutaCandidata, en rutas: [Route]) -> Route? {
        let metros = candidata.ruta.metros
        let segundos = candidata.ruta.segundos
        func coincide(_ ruta: Route) -> Bool {
            let duracion = ruta.steps.reduce(0) { $0 + $1.duration }
            return abs(ruta.distance - metros) <= max(5, metros * 0.002)
                && abs(duracion - segundos) <= max(5, segundos * 0.002)
        }
        if rutas.indices.contains(candidata.indice), coincide(rutas[candidata.indice]) {
            return rutas[candidata.indice]
        }
        return rutas.first(where: coincide)
    }

    /// Cuánto puede haberse alejado de la ruta desde que se calculó. Por debajo
    /// de los 50 m a partir de los que Ferrostar marca desvío (supuesto).
    private static let metrosMaximosAlejado = 40.0

    /// Si, con buena precisión del GPS (≤25 m), la posición está ahora más lejos
    /// de la ruta que el origen con el que se calculó, en más de
    /// `metrosMaximosAlejado`. Se compara con el origen porque Valhalla ajusta
    /// la salida a la carretera más cercana: desde una casa o un aparcamiento
    /// lejos de la carretera, la ruta empieza lejos y no hay que recalcularla.
    private func seHaAlejado(de candidata: RutaCandidata) -> Bool {
        guard let actual = ubicacion.lastLocation,
              actual.horizontalAccuracy > 0, actual.horizontalAccuracy <= 25
        else { return false }
        let ahora = PuntoRuta(latitud: actual.coordinates.lat, longitud: actual.coordinates.lng)
        let origen = candidata.peticion.origen.coordinates
        let alCalcular = PuntoRuta(latitud: origen.lat, longitud: origen.lng)
        guard let lejos = Simplificar.distancia(de: ahora, a: candidata.ruta.puntos),
              let antes = Simplificar.distancia(de: alCalcular, a: candidata.ruta.puntos)
        else { return false }
        return lejos - antes > Self.metrosMaximosAlejado
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
        geometriaGuiado = []
        geometriaRuta = []
        textoCuadro = nil
        posicionEnRuta = nil
        rumbo = nil
        puntoGiro = nil
        cancelarRuta()
        // stopNavigation() también para la ubicación: se reanuda para la posición
        // y la altitud
        ubicacion.startUpdating()
    }

    /// Núcleo de Ferrostar para guiar. Al recalcular por desvío usa el mismo
    /// proveedor, con las opciones de la ruta elegida.
    private func crearNucleo(proveedor: WellKnownRouteProvider, ubicacion fuente: LocationProviding) throws -> FerrostarCore {
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
        if ruta != geometriaGuiado {
            geometriaGuiado = ruta
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

        let texto: String?
        if llegada {
            texto = "Has llegado"
        } else if let maniobra {
            texto = [metrosAlGiro.map { Flechas.distancia($0) }, maniobra.texto]
                .compactMap { $0 }
                .joined(separator: "\n")
        } else {
            texto = nil
        }
        if texto != textoCuadro {
            textoCuadro = texto
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

private extension ClavePreferencia {
    /// Margen guardado, entre 0 y 2; si no hay, el 25 % (Eleccion.margenPorDefecto).
    static func margenGuardado() -> Double {
        let guardado = UserDefaults.standard.object(forKey: margenExtra) as? Double
        return min(2, max(0, guardado ?? Eleccion.margenPorDefecto))
    }
}
