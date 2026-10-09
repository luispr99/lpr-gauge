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
    /// Su posición entre las candidatas del cálculo (Navegacion.detalles).
    let indice: Int

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
/// publica la maniobra, los metros que faltan y la altitud del GPS. Al cuadro
/// le pasa por el enlace el texto (NAV_TEXT), la siguiente maniobra (NAV), el
/// tramo de ruta con su escala (TRAZO) y las calles de sus cruces (CRUCES,
/// desde la 0.10.0), y el guiado sigue en segundo plano y con la pantalla
/// bloqueada (desde la 0.9.0).
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
    /// giro y, debajo, la instrucción; nil sin guiado.
    @Published private(set) var textoCuadro: String?
    /// El enlace con el cuadro (lo pone ContentView). El texto, la maniobra, el
    /// trazo y los cruces se le pasan directamente desde aquí, también con la
    /// app en segundo plano
    weak var enlace: EnlaceBLE?
    /// Escala del tramo del cuadro (TRAZO, §7 ter): el nivel y la maniobra para
    /// la que se eligió; con otra maniobra se elige de nuevo.
    private var nivelEscala: Int?
    private var maniobraEscala: ClaveManiobra?
    /// La ruta del guiado con sus cruces, para el cuadro (CRUCES): la de la
    /// respuesta en formato OSRM con el mismo trazado (RutasRecientes).
    private var rutaCruces: RutaConCruces? {
        didSet { crucesConAnillosGuardados = nil }
    }
    /// Los cruces de rutaCruces para un cuadro con anillos, sin las calles del
    /// anillo en las rotondas cuyo anillo va en el mensaje (esos índices): se
    /// guardan para no rehacerlos cada segundo mientras no cambian.
    private var crucesConAnillosGuardados: (indices: [Int], cruces: [Cruce])?
    /// Solo carreteras en CRUCES (v0.10): los atributos de /trace_attributes
    /// de las candidatas, por índice (llegan con los km tramo a tramo); la
    /// petición de los de la ruta del guiado cuando no es la de ninguna
    /// candidata (tras un recálculo), con el trazado para el que se hizo (una
    /// por ruta, sin repetirla si falla); y si ya se ha intentado el filtro en
    /// la rutaCruces de ahora (aplicarCarreteras).
    private var atributosCandidatas: [Int: AtributosRuta] = [:]
    private var tareaCarreteras: Task<Void, Never>?
    private var carreterasPedidas: [PuntoRuta]?
    private var carreterasHechas = false

    // MARK: Resumen del viaje (NAV, v0.10)
    /// Tiempo y distancia desde «Iniciar»; los recálculos no lo reinician.
    private var cuentakilometros: Cuentakilometros?
    /// Al llegar: el tiempo, la distancia y la velocidad media del viaje, para
    /// la pantalla; nil hasta entonces.
    @Published private(set) var resumenLlegada: ResumenViaje?

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
    /// Km de autopista, peaje y sin asfaltar de las rutas propuestas, tramo a
    /// tramo (ClienteValhalla.atributosVias), por índice de candidata: llegan un
    /// momento después que las rutas (a petición del autor, 2026-10-09: los de
    /// las maniobras se pasaban). Si la petición falla, va en detallesFallidos
    /// y la tarjeta usa los de las maniobras, como un máximo.
    @Published private(set) var detalles: [Int: DetalleVias] = [:]
    @Published private(set) var detallesFallidos: Set<Int> = []
    /// Hay otras rutas dentro del tiempo extra, aunque con menos curvas que la
    /// más rápida (elegirVariantes).
    @Published private(set) var otrasEnMargen = false
    private var tareaDetalles: Task<Void, Never>?
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
        olvidarDetalles()
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
        olvidarDetalles()
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
            otrasEnMargen = false
            return
        }
        // ¿Hay más rutas dentro del margen, aunque con menos curvas? Para que
        // la tarjeta vacía no diga «no hay coincidencia» cuando sí las hay
        // (lo vio la revisión de la 0.10.0)
        let limite = candidatas[eleccion.rapida].ruta.segundos * (1 + max(0, margenExtra))
        otrasEnMargen = candidatas.indices.contains {
            $0 != eleccion.rapida && !candidatas[$0].ruta.tierraEnMedio && candidatas[$0].ruta.segundos <= limite
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
        variantes = papeles.map { VarianteRuta(tipos: $0.tipos, candidata: candidatas[$0.indice], indice: $0.indice) }
        // Se mantiene la elegida si sigue entre las propuestas
        if !variantes.contains(where: { $0.tipos.contains(elegida) }) {
            elegida = .rapida
        }
        sinRutaDeAsfalto = eleccion.todasConTierra
        sinRutaPorTierra = !soloAsfalto && eleccion.porTierra == nil
        // Los km tramo a tramo de las que se ven y aún no los tienen
        pedirDetalles()
    }

    private func olvidarDetalles() {
        tareaDetalles?.cancel()
        tareaDetalles = nil
        detalles = [:]
        detallesFallidos = []
        atributosCandidatas = [:]
    }

    /// Pide, una detrás de otra y respetando el ritmo del servidor
    /// (esperarTurno), los km tramo a tramo de las rutas propuestas que aún no
    /// los tienen. Si ya hay una tarea, ella sigue con las nuevas.
    private func pedirDetalles() {
        guard tareaDetalles == nil, faltaDetalle != nil else { return }
        let esta = generacion
        tareaDetalles = Task { [weak self] in
            await self?.calcularDetalles(generacion: esta)
        }
    }

    private var faltaDetalle: Int? {
        variantes.map { $0.indice }.first { detalles[$0] == nil && !detallesFallidos.contains($0) }
    }

    private func calcularDetalles(generacion esta: Int) async {
        defer {
            if generacion == esta {
                tareaDetalles = nil
            }
        }
        while generacion == esta, let indice = faltaDetalle, indice < candidatas.count {
            await esperarTurno()
            guard generacion == esta, !Task.isCancelled else { return }
            do {
                let atributos = try await ClienteValhalla.atributosVias(candidatas[indice].ruta.puntos)
                guard generacion == esta else { return }
                detalles[indice] = atributos.detalle
                atributosCandidatas[indice] = atributos
            } catch {
                guard generacion == esta else { return }
                detallesFallidos.insert(indice)
            }
            // Si ya se guía por ella, sus cruces (solo carreteras)
            aplicarCarreteras()
        }
    }

    // MARK: - Navegación

    func iniciar() {
        guard !preparando,
              let variante = variantes.first(where: { $0.tipos.contains(elegida) }) ?? variantes.first
        else { return }
        aviso = nil
        preparando = true
        // Aquí, en primer plano (al pulsar «Iniciar»): Core Location no deja
        // activar el segundo plano desde él. Si no llega a empezar, se quita
        // (defer de iniciar(_:generacion:))
        ubicacion.guiadoEnFondo(true)
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
        defer {
            if generacion == esta {
                preparando = false
            }
            // Sin guiar y sin otro «Iniciar» en marcha (si se canceló y se volvió
            // a pulsar, preparando es del nuevo, que necesita el segundo plano)
            if !navegando && !preparando {
                ubicacion.guiadoEnFondo(false)
            }
        }
        guard generacion == esta else { return }
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
            // El resumen del viaje cuenta desde aquí (NAV, v0.10)
            cuentakilometros = Cuentakilometros(inicio: Date())
            resumenLlegada = nil
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
        enlace?.ponerTextoNavegacion(nil)
        enlace?.ponerNav(nil)
        enlace?.ponerTrazo(nil)
        nivelEscala = nil
        maniobraEscala = nil
        rutaCruces = nil
        RutasRecientes.compartida.olvidar()
        tareaCarreteras?.cancel()
        tareaCarreteras = nil
        carreterasPedidas = nil
        carreterasHechas = false
        cuentakilometros = nil
        resumenLlegada = nil
        posicionEnRuta = nil
        rumbo = nil
        puntoGiro = nil
        cancelarRuta()
        // stopNavigation() también para la ubicación: se reanuda para la posición
        // y la altitud, ya sin el segundo plano
        ubicacion.guiadoEnFondo(false)
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
        // Datos del mapa. La geometría solo cambia al recalcular la ruta. Con
        // ella cambian los cruces y las vías de los pasos: los de la respuesta
        // con el mismo trazado (si no aparece, sin cruces). Antes de la
        // maniobra, que usa sus vías
        let ruta = estado.routeGeometry
        if ruta != geometriaGuiado {
            geometriaGuiado = ruta
            geometriaRuta = ruta.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            let puntos = ruta.map { PuntoRuta(latitud: $0.lat, longitud: $0.lng) }
            rutaCruces = Cruces.buscar(puntos, en: RutasRecientes.compartida.todas())
            // Solo carreteras (v0.10), en cuanto haya atributos de esta ruta
            carreterasHechas = false
            aplicarCarreteras()
        }

        // Con simulación, la distancia del viaje sale de las posiciones que
        // ve Ferrostar (las del simulador; las del GPS, en posicionNueva), con
        // la hora de ahora
        if simulando, !llegada,
           case let .navigating(currentStepGeometryIndex: _, userLocation: simulada, snappedUserLocation: _,
                                remainingSteps: _, remainingWaypoints: _, progress: _, summary: _,
                                deviation: _, visualInstruction: _, spokenInstruction: _,
                                annotationJson: _) = estado.tripState {
            cuentakilometros?.anadir(PuntoRuta(latitud: simulada.coordinates.lat, longitud: simulada.coordinates.lng),
                                     precision: simulada.horizontalAccuracy, instante: Date())
        }

        if let visual = estado.currentVisualInstruction {
            let principal = visual.primaryContent
            // El número de salida de la próxima rotonda va en el paso
            // siguiente; ya dentro de ella (instrucción «salga de la
            // rotonda»), en el actual, que es el de la rotonda
            // (Flechas.salidaRotonda; la misma regla vale para el «y luego»).
            // El lado de la circulación, del paso de la maniobra
            let siguiente = estado.remainingSteps?.dropFirst().first
            let salidaRotonda = Flechas.salidaRotonda(tipo: principal.maneuverType, paso: estado.currentStep,
                                                      despues: siguiente)
            maniobra = Maniobra(
                tipo: principal.maneuverType,
                modificador: principal.maneuverModifier,
                gradosRotonda: principal.roundaboutExitDegrees,
                salidaRotonda: salidaRotonda,
                ladoCirculacion: siguiente?.drivingSide ?? estado.currentStep?.drivingSide,
                // Solo la vía, la salida o «Destino», no la frase de la
                // instrucción (Flechas.nombre). La vía, la del paso siguiente
                texto: Flechas.nombre(
                    tipo: principal.maneuverType,
                    salidaRotonda: salidaRotonda,
                    salidas: principal.exitNumbers.isEmpty ? (siguiente?.exits ?? []) : principal.exitNumbers,
                    via: viaSiguiente(estado) ?? siguiente?.roadName
                )
            )
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
        if case .complete = estado.tripState, !llegada {
            llegada = true
            // El resumen del viaje se queda como está al llegar
            cuentakilometros?.parar(Date())
            resumenLlegada = cuentakilometros?.resumen(ahora: Date())
            // Ferrostar no para el GPS al llegar: sin esto seguiría en segundo
            // plano, con el iPhone bloqueado, hasta pulsar «Terminar» (lo vio la
            // revisión de la 0.9.0). Quitarlo se puede también en segundo plano
            ubicacion.guiadoEnFondo(false)
        }

        let texto: String?
        if llegada {
            texto = "Has llegado"
        } else if recalculando {
            texto = "Recalculando la ruta…"
        } else if fueraDeRuta {
            texto = "Fuera de ruta"
        } else if let maniobra {
            // La distancia y, en otra línea, la vía (si la tiene)
            texto = [metrosAlGiro.map { Flechas.distancia($0) }, maniobra.texto.isEmpty ? nil : maniobra.texto]
                .compactMap { $0 }
                .joined(separator: "\n")
        } else {
            texto = nil
        }
        // Al cuadro directamente, no a través de la vista: con la app en segundo
        // plano SwiftUI puede no evaluar las vistas
        if texto != textoCuadro {
            textoCuadro = texto
            enlace?.ponerTextoNavegacion(texto)
        }
        // También directamente: la siguiente maniobra (NAV), el tramo con su
        // escala (TRAZO) y las calles de sus cruces (CRUCES)
        if let enlace {
            enlace.ponerNav(navParaCuadro(estado))
            if enlace.admiteTrazo,
               let calculo = trazoParaCuadro(estado, maximoPuntos: enlace.puntosTrazoQueCaben,
                                             conMovimiento: enlace.admiteMovimiento) {
                // Solo los cruces de este trozo de la ruta entera: desde la moto
                // (lo que falta, restado de la longitud) hasta el final del tramo
                // (con movimiento, v0.9, el tramo lleva 100 m más por delante).
                // Con 50 m de holgura por detrás: Ferrostar mide lo que falta del
                // paso con otra fórmula (Haversine) y la moto podía quedar unos
                // metros adelantada, quitando los primeros cruces (lo vio la
                // revisión de la 0.10.0); los ya pasados los quita igual
                // Cruces.calles, por la posición en el tramo
                let ventana: ClosedRange<Double>? = rutaCruces.flatMap { ruta in
                    estado.currentProgress.map { progreso in
                        let moto = max(0, ruta.longitud - progreso.distanceRemaining)
                        return max(0, moto - 50)...(moto + calculo.metros)
                    }
                }
                // Con un cuadro que dibuja los anillos de las rotondas (v0.8),
                // los de este tramo, con la misma ventana, y las calles sin las
                // del anillo solo en esas rotondas: si no caben todas, las
                // demás van con sus calles (crucesParaAnillos)
                let conAnillos = enlace.admiteAnillos
                var anillos: [AnilloCruce] = []
                var indicesAnillos: [Int] = []
                if conAnillos, let rutaCruces, let ventana {
                    let elegidos = Cruces.anillosConIndices(de: rutaCruces.anillos, ruta: calculo.tramo.ruta,
                                                            sentido: calculo.tramo.sentido, ventana: ventana)
                    anillos = elegidos.anillos
                    indicesAnillos = elegidos.indices
                }
                let cruces = conAnillos ? crucesParaAnillos(indicesAnillos) : (rutaCruces?.cruces ?? [])
                let calles = enlace.admiteCruces
                    ? Cruces.calles(de: cruces, ruta: calculo.tramo.ruta,
                                    sentido: calculo.tramo.sentido,
                                    maximo: enlace.callesCrucesQueCaben(anillos: anillos.count),
                                    ventana: ventana)
                    : []
                // Las calles y los anillos, en los ejes del tramo (la moto en el
                // origen), también con movimiento
                enlace.ponerTrazo((puntos: calculo.tramo.puntos, giro: calculo.tramo.giro),
                                  escala: UInt8(calculo.nivel), calles: calles, anillos: anillos,
                                  atras: calculo.tramo.atras, recorrido: calculo.recorrido)
            } else {
                enlace.ponerTrazo(nil)
            }
        }
    }

    // MARK: - Solo carreteras en CRUCES (v0.10)

    /// Quita de los cruces del guiado las calles que no son carretera
    /// (RutaConCruces.conSoloCarreteras), con los atributos de
    /// /trace_attributes de su trazado: los de la candidata con el mismo
    /// trazado, que se piden con los km tramo a tramo, o, si no es la de
    /// ninguna (tras un recálculo), los suyos, pedidos una vez. Se llama al
    /// cambiar la ruta del guiado y al llegar los atributos de una candidata.
    /// Mientras no hay, los cruces van como llegan (§7 quater).
    private func aplicarCarreteras() {
        guard navegando, !carreterasHechas, let ruta = rutaCruces else { return }
        if let indice = candidatas.indices.first(where: {
            Cruces.mismoTrazado(candidatas[$0].ruta.puntos, ruta.puntos)
        }) {
            if let atributos = atributosCandidatas[indice] {
                filtrarCarreteras(atributos)
                return
            }
            // Si su petición falló, no se repite (una por ruta)
            if detallesFallidos.contains(indice) {
                carreterasHechas = true
                return
            }
            // Si aún está pendiente, llegará con los km de las propuestas
            if tareaDetalles != nil && variantes.contains(where: { $0.indice == indice }) {
                return
            }
        }
        pedirCarreteras(ruta.puntos)
    }

    /// Aplica el filtro a rutaCruces. Si los atributos no encajan con el
    /// trazado, se queda como está; en los dos casos, no se vuelve a intentar
    /// con esta ruta.
    private func filtrarCarreteras(_ atributos: AtributosRuta) {
        guard let ruta = rutaCruces else { return }
        carreterasHechas = true
        if let filtrada = ruta.conSoloCarreteras(atributos) {
            rutaCruces = filtrada
        }
    }

    /// Una sola petición por trazado: si ya se pidió (aunque fallara), nada.
    /// Una ruta nueva cancela la de la anterior.
    private func pedirCarreteras(_ puntos: [PuntoRuta]) {
        if let pedidas = carreterasPedidas, Cruces.mismoTrazado(pedidas, puntos) { return }
        carreterasPedidas = puntos
        tareaCarreteras?.cancel()
        tareaCarreteras = Task { [weak self] in
            await self?.calcularCarreteras(puntos)
        }
    }

    private func calcularCarreteras(_ puntos: [PuntoRuta]) async {
        // Respetando el ritmo del servidor, como las demás peticiones
        await esperarTurno()
        guard !Task.isCancelled, navegando else { return }
        guard let atributos = try? await ClienteValhalla.atributosVias(puntos) else { return }
        // La ruta puede haber cambiado mientras tanto
        guard !Task.isCancelled, navegando, !carreterasHechas, let ruta = rutaCruces,
              Cruces.mismoTrazado(ruta.puntos, puntos)
        else { return }
        filtrarCarreteras(atributos)
    }

    /// Los cruces para un cuadro con anillos, sin las calles del anillo solo en
    /// las rotondas `indices` (RutaConCruces.crucesConAnillosSoloEn(_:)). Los
    /// anillos del mensaje cambian pocas veces (al entrar uno en el tramo o al
    /// dejarlo atrás): mientras sean los mismos, los guardados.
    private func crucesParaAnillos(_ indices: [Int]) -> [Cruce] {
        guard let rutaCruces else { return [] }
        if let guardados = crucesConAnillosGuardados, guardados.indices == indices {
            return guardados.cruces
        }
        let cruces = rutaCruces.crucesConAnillosSoloEn(indices)
        crucesConAnillosGuardados = (indices: indices, cruces: cruces)
        return cruces
    }

    /// La siguiente maniobra para el cuadro (NAV, §5 y §8): código y ángulo de
    /// la flecha (Flechas), distancias, tiempo y hora de llegada. Nil sin
    /// guiado. Al llegar, con «ruta activa» y el bit de llegada, código de
    /// llegada y distancia 0, hasta pulsar «Terminar»: el cuadro enseña la
    /// bandera (a petición del autor, 2026-10-09; §5). Al terminar, nil: el
    /// enlace manda uno sin ruta activa. Con ruta, también al llegar, el
    /// tiempo de viaje y la distancia recorrida (v0.10), para el resumen. Y la
    /// maniobra que va después de la siguiente, con los metros entre las dos
    /// («y luego», v0.11; Flechas.luego); el cuadro decide si la enseña (la
    /// enseña si están a 150 m o menos, §5).
    private func navParaCuadro(_ estado: NavigationState) -> MensajeNav? {
        guard navegando else { return nil }
        let viaje = cuentakilometros?.resumen(ahora: Date())
        if llegada {
            return MensajeNav(secuencia: 0, banderas: [.rutaActiva, .llegada], maniobra: .llegada, distancia: 0,
                              tiempoViaje: viaje?.segundos, distanciaRecorrida: viaje?.metros)
        }
        guard case let .navigating(currentStepGeometryIndex: _, userLocation: _, snappedUserLocation: _,
                                   remainingSteps: pasos, remainingWaypoints: _, progress: progreso, summary: _,
                                   deviation: _, visualInstruction: _, spokenInstruction: _,
                                   annotationJson: _) = estado.tripState
        else { return nil }
        var banderas: BanderasNav = [.rutaActiva]
        if recalculando { banderas.insert(.recalculando) }
        if fueraDeRuta { banderas.insert(.fueraDeRuta) }
        let codigo = Flechas.codigo(maniobra)
        // Y luego (v0.11): solo si hay siguiente maniobra y no es la llegada
        // (después del destino no hay nada); sin ella, código 0 y lo demás
        // desconocido
        let luego: (maniobra: Maniobra, metros: Double)? =
            codigo == .desconocida || codigo == .llegada ? nil : Flechas.luego(pasos)
        let codigoLuego = Flechas.codigo(luego?.maniobra)
        return MensajeNav(
            secuencia: 0,
            banderas: banderas,
            maniobra: codigo,
            // En rotondas, el número de salida
            modificador: codigo == .rotonda ? (maniobra?.salidaRotonda ?? 0) : 0,
            distancia: progreso.distanceToNextManeuver,
            angulo: Flechas.angulo(maniobra),
            distanciaRestante: progreso.distanceRemaining,
            tiempoRestante: progreso.durationRemaining,
            horaLlegada: Self.horaLlegada(dentroDe: progreso.durationRemaining),
            // El paso actual entero, para el avance hacia la maniobra
            longitudPaso: pasos.first?.distance,
            tiempoViaje: viaje?.segundos,
            distanciaRecorrida: viaje?.metros,
            maniobraLuego: codigoLuego,
            modificadorLuego: codigoLuego == .rotonda ? (luego?.maniobra.salidaRotonda ?? 0) : 0,
            anguloLuego: Flechas.angulo(luego?.maniobra),
            // El paso siguiente entero: de la siguiente maniobra a la de luego
            distanciaLuego: luego?.metros
        )
    }

    /// La vía del paso siguiente (el que empieza en la maniobra), con su
    /// número de carretera: de la respuesta OSRM de la ruta del guiado
    /// (RutaConCruces.vias). Los pasos de Ferrostar son los mismos y en el
    /// mismo orden, así que el siguiente es el total menos los que quedan, más
    /// uno. Nil si no se sabe o si la vía no tiene nombre ni número.
    private func viaSiguiente(_ estado: NavigationState) -> String? {
        guard let vias = rutaCruces?.vias, let pasos = estado.remainingSteps else { return nil }
        let indice = vias.count - pasos.count + 1
        guard vias.indices.contains(indice), !vias[indice].isEmpty else { return nil }
        return vias[indice]
    }

    /// Hora de llegada prevista (NAV, v0.6): en minutos desde la medianoche,
    /// con la hora local del iPhone, redondeada al minuto. Nil sin tiempo.
    private static func horaLlegada(dentroDe segundos: Double) -> Int? {
        guard segundos.isFinite, segundos >= 0 else { return nil }
        let llegada = Date().addingTimeInterval(segundos + 30)
        let partes = Calendar.current.dateComponents([.hour, .minute], from: llegada)
        guard let hora = partes.hour, let minuto = partes.minute else { return nil }
        return hora * 60 + minuto
    }

    /// El tramo de ruta por delante para el cuadro (TRAZO), en los ejes de la
    /// moto, y su nivel de escala (§7 ter, v0.6, elegida por el autor el
    /// 2026-10-09): según lo que falte para la maniobra, y dentro de la misma
    /// maniobra solo baja (Trazo.nivel). Se mandan 1,25 veces los metros del
    /// nivel (hasta la 0.9.4, hasta 150 m después del giro, entre 250 y 1000:
    /// al acercarse, el cuadro se acercaba y parecía que faltaba más). Nil
    /// fuera de ruta, recalculando o al llegar: el cuadro deja de dibujarlo.
    /// Con movimiento (v0.9, un cuadro con el bit 10), 100 m más por delante,
    /// hasta 150 m de la ruta ya hecha por detrás y el recorrido de la moto en
    /// la ruta (rutaHecha); si no se puede saber lo hecho, sin los de detrás y
    /// sin recorrido (el enlace manda entonces el formato de siempre).
    /// Devuelve también los metros por delante, para la ventana de los cruces.
    private func trazoParaCuadro(_ estado: NavigationState, maximoPuntos: Int, conMovimiento: Bool)
        -> (tramo: TramoTrazo, nivel: Int, metros: Double, recorrido: Double?)? {
        guard maximoPuntos >= 2, !llegada, !estado.isCalculatingNewRoute,
              case let .navigating(currentStepGeometryIndex: indice, userLocation: _, snappedUserLocation: ajustada,
                                   remainingSteps: pasos, remainingWaypoints: _, progress: progreso, summary: _,
                                   deviation: desvio, visualInstruction: _, spokenInstruction: _,
                                   annotationJson: _) = estado.tripState,
              desvio == .noDeviation
        else { return nil }
        // Una maniobra nueva (otro paso actual) elige el nivel de nuevo
        let clave = ClaveManiobra(pasos: pasos.count, giro: pasos.first?.geometry.last)
        let nivel = Trazo.nivel(metrosAlGiro: progreso.distanceToNextManeuver,
                                anterior: clave == maniobraEscala ? nivelEscala : nil)
        maniobraEscala = clave
        nivelEscala = nivel
        let metros = conMovimiento ? Trazo.metrosTramoConMovimiento(nivel: nivel) : Trazo.metrosTramo(nivel: nivel)
        // Solo los pasos que hacen falta: del actual cuenta lo que queda
        let cuantos = Trazo.pasosNecesarios(distancias: pasos.map { $0.distance },
                                            restanteEnActual: progreso.distanceToNextManeuver, metros: metros)
        let geometrias = pasos.prefix(cuantos).map { paso in
            paso.geometry.map { PuntoRuta(latitud: $0.lat, longitud: $0.lng) }
        }
        let origen = PuntoRuta(latitud: ajustada.coordinates.lat, longitud: ajustada.coordinates.lng)
        let hecha = conMovimiento ? rutaHecha(pasos: pasos, progreso: progreso) : nil
        guard let tramo = Trazo.tramo(pasos: geometrias, indice: indice.map { Int($0) }, desde: origen,
                                      metros: metros, giro: geometrias.first?.last, maximoPuntos: maximoPuntos,
                                      anteriores: hecha?.anteriores)
        else { return nil }
        return (tramo: tramo, nivel: nivel, metros: metros, recorrido: hecha?.recorrido)
    }

    /// Lo ya hecho de la ruta del guiado, para TRAZO con movimiento (v0.9):
    /// el recorrido de la moto, en metros desde el inicio de la ruta, y los
    /// pasos ya hechos que hacen falta para los 150 m de detrás (en el orden
    /// de la ruta; del actual, Trazo.tramo usa el trozo antes de la moto).
    /// Ferrostar solo da los pasos que quedan: los hechos salen de su ruta
    /// (FerrostarCore.route, que cambia con una ruta recalculada), los
    /// primeros, como en viaSiguiente. El recorrido es la suma de las
    /// distancias de los pasos hechos más lo hecho del actual (su distancia
    /// menos lo que falta para la maniobra); es la longitud de la ruta menos
    /// lo que falta (distanceRemaining), pero sin mezclar la longitud de la
    /// ruta con la de los pasos. Con una ruta nueva vuelve a empezar. Nil si
    /// la ruta de Ferrostar no casa con los pasos (por ejemplo, justo al
    /// cambiar de ruta).
    private func rutaHecha(pasos: [RouteStep], progreso: TripProgress)
        -> (recorrido: Double, anteriores: [[PuntoRuta]])? {
        guard let ruta = nucleo?.route, let actual = pasos.first else { return nil }
        let hechos = ruta.steps.count - pasos.count
        guard hechos >= 0, ruta.steps[hechos].geometry == actual.geometry else { return nil }
        let antes = ruta.steps[0..<hechos].reduce(0.0) { $0 + max(0, $1.distance) }
        let longitudActual = max(0, actual.distance)
        let enActual = min(longitudActual, max(0, longitudActual - progreso.distanceToNextManeuver))
        let recorrido = antes + enActual
        guard recorrido.isFinite else { return nil }
        // Los pasos hechos que hacen falta, del más cercano hacia atrás, con 50 m
        // de margen (como Trazo.pasosNecesarios)
        var anteriores: [[PuntoRuta]] = []
        var suma = enActual
        var i = hechos - 1
        while i >= 0 && suma < Trazo.metrosDetras + 50 {
            anteriores.insert(ruta.steps[i].geometry.map { PuntoRuta(latitud: $0.lat, longitud: $0.lng) }, at: 0)
            suma += max(0, ruta.steps[i].distance)
            i -= 1
        }
        return (recorrido: recorrido, anteriores: anteriores)
    }

    private func posicionNueva(_ posicion: CLLocation) {
        posicionActual = posicion.coordinate
        // La distancia del viaje (NAV, v0.10), con el GPS de verdad; con
        // simulación, en actualizar. Precisión negativa: sin dato (no cuenta)
        if navegando, !simulando, !llegada {
            cuentakilometros?.anadir(
                PuntoRuta(latitud: posicion.coordinate.latitude, longitud: posicion.coordinate.longitude),
                precision: posicion.horizontalAccuracy,
                instante: posicion.timestamp
            )
        }
        // Al cuadro, para el indicador de calidad del GPS (GPS, v0.7)
        enlace?.ponerPosicion(posicion)
        if posicion.verticalAccuracy > 0 {
            altitud = posicion.altitude
            precisionVertical = posicion.verticalAccuracy
        } else {
            altitud = nil
            precisionVertical = nil
        }
    }
}

/// La maniobra en curso, para la escala del tramo del cuadro: cambia al pasar
/// al paso siguiente (quedan menos pasos) o con una ruta nueva (otro punto de
/// giro).
private struct ClaveManiobra: Equatable {
    let pasos: Int
    let giro: GeographicCoordinate?
}

private extension ClavePreferencia {
    /// Margen guardado, entre 0 y 2; si no hay, el 25 % (Eleccion.margenPorDefecto).
    static func margenGuardado() -> Double {
        let guardado = UserDefaults.standard.object(forKey: margenExtra) as? Double
        return min(2, max(0, guardado ?? Eleccion.margenPorDefecto))
    }
}
