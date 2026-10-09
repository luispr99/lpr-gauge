import Foundation

/// Un cruce de la ruta: dónde está y los rumbos de las calles que salen de él,
/// sin la de llegada ni la de salida de la ruta (CRUCES, docs/PROTOCOLO.md
/// §7 quater).
public struct Cruce: Equatable {
    public var punto: PuntoRuta
    /// Grados desde el norte, en sentido horario, desde el cruce hacia fuera.
    public var rumbos: [Double]
    /// Por cada rumbo, en el mismo orden, si se puede entrar por esa calle
    /// desde el cruce (`entry` de Valhalla): false en una calle de un sentido
    /// que solo llega a la ruta, en una acera, un paso de peatones o un carril
    /// bici; nil si no se sabe. Siempre de la misma longitud que `rumbos` al
    /// crearlo; para leerlo, `entrada(_:)`, que no se sale del array.
    public var entradas: [Bool?]
    /// Metros desde el principio de la ruta hasta el cruce, por la ruta (de su
    /// índice en el trazado, `geometry_index`); nil si no se conoce. Sirve para
    /// no tomar los cruces de otra pasada por el mismo sitio ni los ya pasados.
    public var recorrido: Double?
    /// La rotonda del cruce, si se le ha ajustado anillo: su índice en
    /// RutaConCruces.anillos. Son de la rotonda los cruces de su paso y el
    /// primero del paso siguiente (la salida). Nil en los demás.
    public var anillo: Int?
    /// Índice del cruce en el trazado de la ruta (`geometry_index`); nil si no
    /// se conoce. Para casarlo con los nodos de /trace_attributes (v0.10).
    public var indiceTrazado: Int?

    /// `entradas` con otra longitud que `rumbos` (o sin dar) se toma como
    /// desconocida en todas las calles.
    public init(punto: PuntoRuta, rumbos: [Double], recorrido: Double? = nil, entradas: [Bool?]? = nil,
                anillo: Int? = nil, indiceTrazado: Int? = nil) {
        self.punto = punto
        self.rumbos = rumbos
        self.recorrido = recorrido
        if let entradas, entradas.count == rumbos.count {
            self.entradas = entradas
        } else {
            self.entradas = [Bool?](repeating: nil, count: rumbos.count)
        }
        self.anillo = anillo
        self.indiceTrazado = indiceTrazado
    }

    /// Si se puede entrar por la calle `indice` (de `rumbos`); nil si no se
    /// sabe o si no hay dato para ese índice.
    public func entrada(_ indice: Int) -> Bool? {
        entradas.indices.contains(indice) ? entradas[indice] : nil
    }
}

/// Una ruta de una respuesta en formato OSRM: su trazado y sus cruces.
public struct RutaConCruces: Equatable {
    public var puntos: [PuntoRuta]
    /// Los cruces con calles laterales, en el orden de la ruta, para un cuadro
    /// que no dibuja los anillos de las rotondas. Ya con la regla 2 de las
    /// rayas dobles, aplicada una vez a la ruta entera (Cruces.juntarDobles(en:),
    /// 0.12.1).
    public private(set) var cruces: [Cruce]
    /// Metros del trazado entero (los de `recorrido` de los cruces llegan
    /// hasta aquí).
    public var longitud: Double
    /// La vía de cada paso, en orden (los de todos los tramos seguidos), como
    /// se escribe junto a la flecha (RespuestaOSRM.via); vacío si no tiene
    /// nombre ni número. Ferrostar 0.57.0 lee el `ref` de cada paso pero no lo
    /// da en sus RouteStep, y sin él las carreteras que solo tienen número
    /// (M-510, N-6) se quedaban sin texto (lo vio la revisión de la 0.10.0).
    public var vias: [String]
    /// Los anillos de las rotondas de la ruta que se han podido ajustar
    /// (Anillo.ajustar), en el orden de la ruta (v0.8).
    public private(set) var anillos: [Anillo]
    /// Los cruces para un cuadro que dibuja los anillos (Capacidades.anillos),
    /// con todas las rotondas con anillo: en ellas, sin las calles que son el
    /// propio anillo y con los brazos con isleta juntados (Cruces.conAnillos);
    /// y después, la regla 2, como en `cruces`. Se calculan al crear la ruta,
    /// una vez. Para el mensaje, `crucesConAnillosSoloEn(_:)`.
    public private(set) var crucesConAnillos: [Cruce]
    /// Los cruces con la regla 1, sin la 2, para rehacer los de un cuadro con
    /// anillos con solo algunas rotondas.
    private var crucesSinJuntar: [Cruce]
    /// Los cruces como llegan (sin la regla 1), para rehacerlo todo con solo
    /// las calles de carretera (`conSoloCarreteras(_:)`, v0.10).
    private var crucesLlegados: [Cruce]
    /// Si ya lleva solo las calles de carretera (`conSoloCarreteras(_:)`).
    public private(set) var soloCarreteras = false

    /// `cruces`: los de la ruta, como llegan, cada uno con sus calles
    /// laterales. Aquí se les aplican la regla 1 (Cruces.quitarSinEntrada) y,
    /// después, las rotondas y la regla 2.
    public init(puntos: [PuntoRuta], cruces: [Cruce], vias: [String] = [], anillos: [Anillo] = []) {
        self.puntos = puntos
        self.crucesLlegados = cruces
        let utiles = Cruces.quitarSinEntrada(cruces)
        self.crucesSinJuntar = utiles
        self.cruces = Cruces.juntarDobles(en: utiles)
        self.longitud = RespuestaOSRM.recorridos(puntos).last ?? 0
        self.vias = vias
        self.anillos = anillos
        // La regla 2 después de las rotondas: las calles del anillo ya no
        // cuentan y la del brazo con isleta, sí (como en el estudio)
        self.crucesConAnillos = Cruces.juntarDobles(en: Cruces.conAnillos(utiles, anillos: anillos))
    }

    /// La misma ruta con solo las calles de carretera (Cruces.soloCarreteras,
    /// v0.10), con los atributos de /trace_attributes de su trazado: el filtro
    /// va antes que las reglas 1 y 2 y que las rotondas, que se rehacen. Nil
    /// si los atributos no encajan con el trazado (AtributosRuta.encaja): se
    /// queda como está.
    public func conSoloCarreteras(_ atributos: AtributosRuta) -> RutaConCruces? {
        guard atributos.encaja(puntos: puntos.count) else { return nil }
        var ruta = RutaConCruces(
            puntos: puntos,
            cruces: Cruces.soloCarreteras(crucesLlegados, aristas: atributos.aristasQueCruzan),
            vias: vias,
            anillos: anillos
        )
        ruta.crucesLlegados = crucesLlegados
        ruta.soloCarreteras = true
        return ruta
    }

    /// Los cruces para un cuadro que dibuja los anillos, sin las calles del
    /// anillo solo en las rotondas `indices` (en `anillos`): las de los anillos
    /// que van en el mensaje (Cruces.anillosConIndices). En las demás, como en
    /// `cruces`: el cuadro no dibuja su anillo y sus calles lo dibujan (si hay
    /// más anillos en el tramo de los que caben; revisión de la 0.12.0). Los
    /// índices que no están en `anillos` no cuentan. Con todas, es
    /// `crucesConAnillos`; sin ninguna, `cruces`. Si no, se calcula (conAnillos
    /// de esas rotondas y la regla 2 de la ruta entera): cuesta poco más que
    /// ordenar las calles de la ruta, unos cientos o pocos miles, y la app lo
    /// guarda mientras no cambian los anillos del mensaje.
    public func crucesConAnillosSoloEn(_ indices: [Int]) -> [Cruce] {
        let elegidos = Set(indices.filter { anillos.indices.contains($0) })
        if elegidos.isEmpty { return cruces }
        if elegidos.count == anillos.count { return crucesConAnillos }
        return Cruces.juntarDobles(en: Cruces.conAnillos(crucesSinJuntar, anillos: anillos, soloEn: elegidos))
    }
}

/// Respuesta de /route de Valhalla en formato OSRM, la que pide Ferrostar para
/// guiar. Solo lo que hace falta para los cruces: el trazado de cada ruta
/// (`geometry`, polyline6) y, de cada paso, su maniobra (`maneuver`, para las
/// rotondas) y sus cruces (`intersections`), con la posición (`location`,
/// longitud y latitud), los rumbos de todas las calles (`bearings`), si se
/// puede entrar por cada una (`entry`) y cuáles son la de llegada (`in`) y la
/// de salida (`out`). Comprobado con valhalla1.openstreetmap.de el 2026-10-09,
/// también con las opciones que pone Ferrostar 0.57.0 en su petición
/// (docs/DECISIONES.md).
public enum RespuestaOSRM {
    /// Regla 1 de las rayas dobles (v0.12.0): un cruce con al menos estas
    /// calles laterales y ninguna por la que se pueda entrar (`entry` false en
    /// todas) se queda sin ellas. Es el patrón de las aceras y los pasos de
    /// peatones: Valhalla da una calle por cada vía de OpenStreetMap del nodo.
    /// Con una sola (una calle de un sentido que llega a la ruta) se queda.
    /// Supuesto, sacado de 3 rutas reales (Madrid y Segovia, 2026-10-09).
    static let minimoLateralesSinEntrada = 2

    /// Tipos de maniobra de las rotondas en formato OSRM (`maneuver.type`).
    static let tiposRotonda: Set<String> = ["roundabout", "rotary"]

    /// Las rutas, en el orden de la respuesta. Los cruces sin calles laterales
    /// (la salida, la llegada, una curva sin cruce) no se guardan; los que
    /// caen en la regla 1 los quita RutaConCruces (desde la 0.14.0, para que
    /// el filtro de carreteras vaya antes). Lanza un error si no es una
    /// respuesta OSRM (por ejemplo, la del formato propio de Valhalla).
    public static func rutas(de datos: Data) throws -> [RutaConCruces] {
        let respuesta = try JSONDecoder().decode(Respuesta.self, from: datos)
        return respuesta.routes.map { ruta(de: $0) }
    }

    static func ruta(de ruta: Ruta) -> RutaConCruces {
        let puntos = Polilinea.decodificar(ruta.geometry, precision: 6)
        let hastaPunto = recorridos(puntos)
        // Los pasos de todos los tramos seguidos: geometry_index es de la ruta
        // entera
        let pasos = (ruta.legs ?? []).flatMap { $0.steps ?? [] }
        var cruces: [Cruce] = []
        var vias: [String] = []
        // De cada paso, los índices en `cruces` de los suyos y el de su primer
        // cruce (si tiene calles), para las rotondas
        var crucesDelPaso: [[Int]] = []
        var primeroDelPaso: [Int?] = []
        for paso in pasos {
            vias.append(via(nombre: paso.name, numero: paso.ref))
            var suyos: [Int] = []
            var primero: Int?
            for (numero, interseccion) in (paso.intersections ?? []).enumerated() {
                guard let nuevo = cruce(de: interseccion, hastaPunto: hastaPunto) else { continue }
                if numero == 0 { primero = cruces.count }
                suyos.append(cruces.count)
                cruces.append(nuevo)
            }
            crucesDelPaso.append(suyos)
            primeroDelPaso.append(primero)
        }

        // Las rotondas: el arco que recorre la ruta va del primer cruce del paso
        // de la rotonda al primero del paso siguiente (la salida)
        var anillos: [Anillo] = []
        for (numero, paso) in pasos.enumerated() where numero + 1 < pasos.count {
            guard let tipo = paso.maneuver?.type, tiposRotonda.contains(tipo),
                  let inicio = paso.intersections?.first?.indiceTrazado,
                  let fin = pasos[numero + 1].intersections?.first?.indiceTrazado,
                  inicio >= 0, inicio < fin, fin < puntos.count, fin < hastaPunto.count,
                  let anillo = Anillo.ajustar(arco: Array(puntos[inicio...fin]),
                                              recorridoEntrada: hastaPunto[inicio],
                                              recorridoSalida: hastaPunto[fin])
            else { continue }
            let indice = anillos.count
            anillos.append(anillo)
            var suyos = crucesDelPaso[numero]
            if let salida = primeroDelPaso[numero + 1] { suyos.append(salida) }
            // Un cruce que fuera de dos rotondas seguidas se queda en la primera
            for c in suyos where cruces.indices.contains(c) && cruces[c].anillo == nil {
                cruces[c].anillo = indice
            }
        }
        return RutaConCruces(puntos: puntos, cruces: cruces, vias: vias, anillos: anillos)
    }

    /// El cruce de una intersección con sus calles laterales (todas salvo la de
    /// llegada y la de salida); nil si no tiene o si le falta la posición. La
    /// regla 1 va después, en RutaConCruces. `entry` solo se usa si tiene la
    /// misma longitud que `bearings`; si no, las entradas quedan desconocidas.
    static func cruce(de interseccion: Interseccion, hastaPunto: [Double]) -> Cruce? {
        guard interseccion.location.count >= 2, let rumbos = interseccion.bearings else { return nil }
        let entry: [Bool]? = interseccion.entry.flatMap { $0.count == rumbos.count ? $0 : nil }
        let laterales = rumbos.indices.filter { $0 != interseccion.entrada && $0 != interseccion.salida }
        guard !laterales.isEmpty else { return nil }
        let entradas: [Bool?] = laterales.map { i -> Bool? in
            guard let entry, entry.indices.contains(i) else { return nil }
            return entry[i]
        }
        let indice = interseccion.indiceTrazado ?? -1
        return Cruce(
            punto: PuntoRuta(latitud: interseccion.location[1], longitud: interseccion.location[0]),
            rumbos: laterales.map { rumbos[$0] },
            recorrido: hastaPunto.indices.contains(indice) ? hastaPunto[indice] : nil,
            entradas: entradas,
            indiceTrazado: interseccion.indiceTrazado
        )
    }

    /// La vía de un paso como se escribe junto a la flecha: el número y el
    /// nombre («A-6, Autovía del Noroeste»), o el que haya («M-510», «Calle
    /// Mayor»); vacío si no hay ninguno.
    public static func via(nombre: String?, numero: String?) -> String {
        let partes = [numero, nombre]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return partes.joined(separator: ", ")
    }

    /// Metros recorridos hasta cada punto del trazado, desde el primero.
    static func recorridos(_ puntos: [PuntoRuta]) -> [Double] {
        guard let primero = puntos.first else { return [] }
        var lista = [0.0]
        var previo = primero
        for punto in puntos.dropFirst() {
            lista.append(lista[lista.count - 1] + Trazo.distancia(previo, punto))
            previo = punto
        }
        return lista
    }

    // Solo los campos que usa la app
    struct Respuesta: Decodable {
        let routes: [Ruta]
    }

    struct Ruta: Decodable {
        let geometry: String
        let legs: [Tramo]?
    }

    struct Tramo: Decodable {
        let steps: [Paso]?
    }

    struct Paso: Decodable {
        let intersections: [Interseccion]?
        let name: String?
        let ref: String?
        let maneuver: Maniobra?
    }

    struct Maniobra: Decodable {
        /// «roundabout» y «rotary» son rotondas (`tiposRotonda`).
        let type: String?
        /// En las rotondas, el número de salida.
        let exit: Int?
    }

    struct Interseccion: Decodable {
        /// Longitud y latitud.
        let location: [Double]
        /// Valhalla los da enteros; como Double valen igual.
        let bearings: [Double]?
        /// Por cada rumbo de `bearings`, si se puede entrar por esa calle.
        let entry: [Bool]?
        /// Índices en `bearings` de la calle de llegada (no está en la salida)
        /// y de la de salida (no está en la llegada).
        let entrada: Int?
        let salida: Int?
        /// Índice del cruce en el trazado de la ruta (Valhalla lo da para la
        /// ruta entera: crece de paso en paso).
        let indiceTrazado: Int?

        enum CodingKeys: String, CodingKey {
            case location
            case bearings
            case entry
            case entrada = "in"
            case salida = "out"
            case indiceTrazado = "geometry_index"
        }
    }
}

/// Las calles que salen del tramo de TRAZO, para CRUCES (§7 quater, v0.6).
public enum Cruces {
    /// Metros como mucho entre un cruce y la ruta del tramo para que sea suyo.
    /// Valhalla pone cada cruce en un vértice del trazado, así que basta poco.
    static let tolerancia = 5.0

    /// Regla 2 de las rayas dobles (v0.12.0): de cada grupo de calles casi
    /// paralelas, a estos metros o menos a lo largo de la ruta y a estos grados
    /// o menos de rumbo, se queda una (`juntarDobles(en:)`, una vez por ruta
    /// desde la 0.12.1). Son la otra calzada de
    /// las avenidas, las aceras y los carriles bici que Valhalla da como calles
    /// aparte. Supuestos, sacados de 3 rutas reales (Madrid y Segovia,
    /// 2026-10-09): con las reglas 1 y 2, de 151, 142 y 122 calles se pasa a
    /// 78, 78 y 68; se quedan el 95 % de las calles por las que se puede
    /// entrar, el 80 % de las de un sentido que llegan a la ruta y el 7 % de
    /// las peatonales, y no queda ninguna pareja doble.
    static let metrosDobles = 30.0
    static let gradosDobles = 30.0

    /// La ruta de `rutas` con el mismo trazado que `geometria` (la del guiado de
    /// Ferrostar): el mismo número de puntos y todos a menos de 1 m. Todos, no
    /// solo los extremos: las alternativas de una respuesta los comparten (lo
    /// vio la revisión de la 0.10.0). Solo se hace al cambiar de ruta. Nil si no
    /// hay ninguna.
    public static func buscar(_ geometria: [PuntoRuta], en rutas: [RutaConCruces]) -> RutaConCruces? {
        rutas.first { mismoTrazado($0.puntos, geometria) }
    }

    /// Si dos trazados son el mismo: no vacíos, con el mismo número de puntos
    /// y todos a menos de 1 m (como `buscar`).
    public static func mismoTrazado(_ a: [PuntoRuta], _ b: [PuntoRuta]) -> Bool {
        !a.isEmpty && a.count == b.count && zip(a, b).allSatisfy { Trazo.distancia($0, $1) < 1 }
    }

    /// Regla 1 de las rayas dobles (RespuestaOSRM.minimoLateralesSinEntrada):
    /// quita los cruces con dos calles laterales o más y ninguna por la que se
    /// pueda entrar (`entry` false en todas). Hasta la 0.13.0 se aplicaba al
    /// leer la respuesta; desde la 0.14.0, en RutaConCruces, para que el
    /// filtro de carreteras vaya antes: así, de una calle de un sentido que
    /// llega a la ruta junto a una acera, queda la calle.
    public static func quitarSinEntrada(_ cruces: [Cruce]) -> [Cruce] {
        cruces.filter { cruce in
            !(cruce.rumbos.count >= RespuestaOSRM.minimoLateralesSinEntrada
                && cruce.rumbos.indices.allSatisfy { cruce.entrada($0) == false })
        }
    }

    /// Usos de Valhalla (`use`) de las calles que se mandan en CRUCES (v0.10,
    /// a petición del autor: «solo quiero carreteras»): las calles normales,
    /// los enlaces, los ramales de giro, las calles residenciales de
    /// prioridad peatonal, las vías de servicio y los fondos de saco. Fuera
    /// quedan, entre otros, los accesos a garajes (`driveway`), los pasillos
    /// de aparcamiento (`parking_aisle`), los callejones (`alley`), las pistas
    /// (`track`), los caminos, los carriles bici, las aceras, los pasos de
    /// peatones y las escaleras.
    static let usosDeCarretera: Set<String> = [
        "road", "ramp", "turn_channel", "living_street", "service_road", "culdesac",
    ]

    /// Grados como mucho entre una calle lateral y la arista que cruza el
    /// nodo para que sean la misma (como en el estudio del 2026-10-09: con 3
    /// rutas reales, todas las calles casaron).
    static let gradosCasado = 4.0

    /// Solo carreteras (v0.10): de cada cruce con aristas que cruzan su nodo
    /// (`aristas`, por índice del trazado; el del cruce es su
    /// `indiceTrazado`), quita las calles laterales que casan con una arista
    /// cuyo uso no es de carretera (`usosDeCarretera`). Cada calle casa con
    /// la arista de rumbo más parecido (la primera, si hay empate) si está a
    /// `gradosCasado` o menos. Se quedan como están las calles que no casan
    /// con ninguna, las que casan con una arista sin uso y los cruces sin
    /// índice o sin aristas. Los cruces que se quedan sin calles se quitan.
    /// El orden no cambia.
    public static func soloCarreteras(_ cruces: [Cruce], aristas: [Int: [AristaQueCruza]]) -> [Cruce] {
        guard !aristas.isEmpty else { return cruces }
        var resultado: [Cruce] = []
        for cruce in cruces {
            guard let indice = cruce.indiceTrazado, let cruzan = aristas[indice], !cruzan.isEmpty else {
                resultado.append(cruce)
                continue
            }
            let quedan = cruce.rumbos.indices.filter { k in
                guard let uso = usoCasado(rumbo: cruce.rumbos[k], en: cruzan) else { return true }
                return usosDeCarretera.contains(uso)
            }
            if quedan.count == cruce.rumbos.count {
                resultado.append(cruce)
                continue
            }
            if quedan.isEmpty { continue }
            var copia = cruce
            copia.rumbos = quedan.map { cruce.rumbos[$0] }
            copia.entradas = quedan.map { cruce.entrada($0) }
            resultado.append(copia)
        }
        return resultado
    }

    /// El uso de la arista de `cruzan` que casa con una calle de este rumbo
    /// (la de rumbo más parecido, a `gradosCasado` o menos); nil si no casa
    /// ninguna o si la que casa no trae uso.
    static func usoCasado(rumbo: Double, en cruzan: [AristaQueCruza]) -> String? {
        var mejor: AristaQueCruza?
        var menor = Double.infinity
        for arista in cruzan {
            let diferencia = abs(diferenciaAngular(arista.rumbo, rumbo))
            if diferencia < menor {
                menor = diferencia
                mejor = arista
            }
        }
        guard let mejor, menor <= gradosCasado else { return nil }
        return mejor.uso
    }

    /// Las calles de los `cruces` que quedan sobre el tramo (a menos de
    /// `tolerancia` metros de `ruta`, la del tramo sin simplificar, que empieza
    /// en la moto), en los ejes de la moto (el origen en el primer punto de
    /// `ruta` y `sentido` hacia arriba, como TRAZO). Los cruces más cercanos a
    /// la moto, a lo largo de la ruta, primero, y como mucho `maximo` calles.
    /// Solo elige y recorta: la regla 2 ya va en los cruces de la ruta
    /// (RutaConCruces). Aquí, tramo a tramo, al pasar la moto el ancla de un
    /// grupo el grupo se rehacía y aparecían y desaparecían calles que seguían
    /// por delante (revisión de la 0.12.0).
    /// `ventana`: los metros de la ruta entera que cubre el tramo, desde la moto
    /// (Cruce.recorrido); un cruce con recorrido fuera de ella no cuenta, aunque
    /// caiga cerca del tramo (otra pasada por la misma calle o un cruce ya
    /// pasado; revisión de la 0.10.0). Tampoco el que queda en la moto o detrás.
    public static func calles(
        de cruces: [Cruce],
        ruta: [PuntoRuta],
        sentido: Double,
        maximo: Int = MensajeCruces.maximoCalles,
        ventana: ClosedRange<Double>? = nil
    ) -> [CalleCruce] {
        guard let origen = ruta.first, ruta.count >= 2, maximo > 0, !cruces.isEmpty else { return [] }

        // La ruta en metros (proyección local, como aEjesMoto) y lo recorrido
        // hasta cada punto
        let coseno = cos(origen.latitud * .pi / 180)
        func plano(_ punto: PuntoRuta) -> (x: Double, y: Double) {
            ((punto.longitud - origen.longitud) * Trazo.metrosPorGrado * coseno,
             (punto.latitud - origen.latitud) * Trazo.metrosPorGrado)
        }
        let planos = ruta.map { plano($0) }
        var recorrido = [0.0]
        var minimoX = planos[0].x, maximoX = planos[0].x
        var minimoY = planos[0].y, maximoY = planos[0].y
        for i in 1..<planos.count {
            recorrido.append(recorrido[i - 1] + hypot(planos[i].x - planos[i - 1].x, planos[i].y - planos[i - 1].y))
            minimoX = min(minimoX, planos[i].x)
            maximoX = max(maximoX, planos[i].x)
            minimoY = min(minimoY, planos[i].y)
            maximoY = max(maximoY, planos[i].y)
        }

        // Cada cruce, en el segmento más cercano (el primero, si hay empate);
        // un recuadro alrededor de la ruta descarta deprisa los lejanos, que con
        // una ruta larga son casi todos
        var encontrados: [(recorrido: Double, orden: Int)] = []
        for (orden, cruce) in cruces.enumerated() {
            if let ventana, let enRuta = cruce.recorrido,
               enRuta <= ventana.lowerBound || enRuta > ventana.upperBound + tolerancia {
                continue
            }
            let p = plano(cruce.punto)
            guard p.x >= minimoX - tolerancia, p.x <= maximoX + tolerancia,
                  p.y >= minimoY - tolerancia, p.y <= maximoY + tolerancia
            else { continue }
            var mejor = tolerancia
            var donde: Double?
            for i in 0..<(planos.count - 1) {
                let a = planos[i]
                let b = planos[i + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let largo2 = dx * dx + dy * dy
                let t = largo2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / largo2)) : 0
                let distancia = hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
                if distancia < mejor {
                    mejor = distancia
                    donde = recorrido[i] + t * largo2.squareRoot()
                }
            }
            // En la moto (o detrás, recortado a ella) no: ya se está pasando
            if let donde, donde >= 1 {
                encontrados.append((recorrido: donde, orden: orden))
            }
        }
        encontrados.sort { $0.recorrido != $1.recorrido ? $0.recorrido < $1.recorrido : $0.orden < $1.orden }

        // Las calles de esos cruces, en ese orden, hasta el máximo
        var calles: [CalleCruce] = []
        for encontrado in encontrados where calles.count < maximo {
            let cruce = cruces[encontrado.orden]
            guard let enEjes = Trazo.aEjesMoto([cruce.punto], origen: origen, rumbo: sentido).first else { continue }
            for rumbo in cruce.rumbos where calles.count < maximo {
                calles.append(CalleCruce(x: enEjes.x, y: enEjes.y, direccion: direccion(rumbo: rumbo, sentido: sentido)))
            }
        }
        return calles
    }

    /// Regla 2 de las rayas dobles para la ruta entera (`juntarDobles`), por
    /// Cruce.recorrido (como la función `juntar` del estudio, que la aplica a
    /// la ruta entera): así cada grupo es siempre el mismo, vaya la moto por
    /// donde vaya. A igual recorrido, en el orden de `cruces`. Los cruces que
    /// se quedan sin calles se quitan; los que no tienen recorrido se quedan
    /// como están (Valhalla da `geometry_index` en las 840 intersecciones de 6
    /// respuestas reales, comprobado el 2026-10-09). El orden no cambia.
    public static func juntarDobles(en cruces: [Cruce]) -> [Cruce] {
        // Los cruces con recorrido, por él
        var conRecorrido: [(recorrido: Double, cruce: Int)] = []
        for (c, cruce) in cruces.enumerated() {
            if let recorrido = cruce.recorrido, recorrido.isFinite {
                conRecorrido.append((recorrido: recorrido, cruce: c))
            }
        }
        conRecorrido.sort { $0.recorrido != $1.recorrido ? $0.recorrido < $1.recorrido : $0.cruce < $1.cruce }

        // Sus calles, en ese orden, y de qué cruce y calle es cada una
        var laterales: [LateralEnRuta] = []
        var origenes: [(cruce: Int, calle: Int)] = []
        for elemento in conRecorrido {
            let cruce = cruces[elemento.cruce]
            for (k, rumbo) in cruce.rumbos.enumerated() {
                laterales.append(LateralEnRuta(donde: elemento.recorrido, rumbo: rumbo, entrada: cruce.entrada(k)))
                origenes.append((cruce: elemento.cruce, calle: k))
            }
        }
        var quedan = [Bool](repeating: false, count: laterales.count)
        for i in juntarDobles(laterales) {
            quedan[i] = true
        }
        var fuera = [Set<Int>](repeating: [], count: cruces.count)
        for (i, origen) in origenes.enumerated() where !quedan[i] {
            fuera[origen.cruce].insert(origen.calle)
        }

        var resultado: [Cruce] = []
        for (c, cruce) in cruces.enumerated() {
            if fuera[c].isEmpty {
                resultado.append(cruce)
                continue
            }
            let calles = cruce.rumbos.indices.filter { !fuera[c].contains($0) }
            if calles.isEmpty { continue }
            var copia = cruce
            copia.rumbos = calles.map { cruce.rumbos[$0] }
            copia.entradas = calles.map { cruce.entrada($0) }
            resultado.append(copia)
        }
        return resultado
    }

    /// Una calle de un cruce, para la regla 2: los metros por la ruta hasta su
    /// cruce, su rumbo y si se puede entrar por ella.
    struct LateralEnRuta: Equatable {
        var donde: Double
        var rumbo: Double
        var entrada: Bool?
    }

    /// Regla 2 de las rayas dobles: los índices de `laterales` (ordenadas por
    /// `donde`) que se quedan, en orden. Cada grupo se ancla en la primera
    /// calle que queda: con ella van las siguientes a `metrosDobles` o menos
    /// por la ruta y a `gradosDobles` o menos de rumbo (de ella, no entre sí).
    /// De cada grupo se queda la primera por la que se puede entrar o, si no
    /// hay, la primera. Es la función `juntar` del estudio con las rutas reales
    /// (docs/DECISIONES.md, 0.12.0).
    static func juntarDobles(_ laterales: [LateralEnRuta]) -> [Int] {
        var fuera = [Bool](repeating: false, count: laterales.count)
        for i in laterales.indices {
            if fuera[i] { continue }
            var grupo = [i]
            var j = i + 1
            while j < laterales.count && laterales[j].donde - laterales[i].donde <= metrosDobles {
                if !fuera[j] && abs(diferenciaAngular(laterales[i].rumbo, laterales[j].rumbo)) <= gradosDobles {
                    grupo.append(j)
                }
                j += 1
            }
            guard grupo.count >= 2 else { continue }
            let queda = grupo.first { laterales[$0].entrada == true } ?? i
            for k in grupo where k != queda {
                fuera[k] = true
            }
        }
        return laterales.indices.filter { !fuera[$0] }
    }

    /// `a` menos `b`, en grados, entre -180 y 180 (180 incluido). Lo que no es
    /// finito da NaN, que no pasa ninguna comparación.
    static func diferenciaAngular(_ a: Double, _ b: Double) -> Double {
        var diferencia = (a - b).truncatingRemainder(dividingBy: 360)
        if diferencia > 180 {
            diferencia -= 360
        } else if diferencia <= -180 {
            diferencia += 360
        }
        return diferencia
    }

    /// Dirección de una calle respecto al sentido de la marcha, en 1/256 de
    /// vuelta y en sentido horario: 0 delante, 64 derecha, 128 atrás, 192
    /// izquierda.
    static func direccion(rumbo: Double, sentido: Double) -> UInt8 {
        guard rumbo.isFinite, sentido.isFinite else { return 0 }
        var relativo = (rumbo - sentido).truncatingRemainder(dividingBy: 360)
        if relativo < 0 { relativo += 360 }
        return UInt8(Int((relativo * 256 / 360).rounded()) % 256)
    }
}
