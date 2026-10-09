import Foundation

/// Km de autopista, de peaje y sin asfaltar de una ruta, contados tramo a
/// tramo (cada arista del grafo de Valhalla), no por maniobras.
///
/// Por maniobras se pasaba: una maniobra es el trozo entre dos indicaciones, y
/// si empieza en una autovía y sigue por una nacional sin indicación nueva,
/// cuenta entera. Lo vio el autor con Segovia → Ávila → Talavera de la Reina
/// (2026-10-09): 44,3 km de autopista por maniobras (la de «tomar la SG-20»
/// mide 33,4 km y sigue 28 por la N-110), y 10,2 tramo a tramo, los que él
/// conoce (docs/DECISIONES.md).
public struct DetalleVias: Equatable {
    /// Clase autopista de OSM (`motorway`; en España, autopistas y autovías),
    /// sin los enlaces.
    public var metrosAutopista: Double
    public var metrosPeaje: Double
    public var metrosSinAsfaltar: Double
    /// La ruta entera, para comprobar que el ajuste al mapa ha ido bien.
    public var metros: Double

    public init(metrosAutopista: Double, metrosPeaje: Double, metrosSinAsfaltar: Double, metros: Double) {
        self.metrosAutopista = metrosAutopista
        self.metrosPeaje = metrosPeaje
        self.metrosSinAsfaltar = metrosSinAsfaltar
        self.metros = metros
    }
}

/// Una arista del grafo que cruza un nodo de la ruta sin ser de la ruta
/// (`node.intersecting_edge` de /trace_attributes): hacia dónde sale del nodo
/// y qué es. Para quitar de CRUCES las calles que no son carretera (v0.10).
public struct AristaQueCruza: Equatable {
    /// Grados desde el norte, en sentido horario, saliendo del nodo
    /// (`begin_heading`).
    public var rumbo: Double
    /// `use` de Valhalla («road», «footway», «parking_aisle»…); nil si no
    /// viene.
    public var uso: String?

    public init(rumbo: Double, uso: String?) {
        self.rumbo = rumbo
        self.uso = uso
    }
}

/// Lo que se saca de /trace_attributes de una ruta: los km por tipo de vía
/// (para las tarjetas) y las aristas que cruzan cada nodo (para CRUCES, v0.10).
public struct AtributosRuta: Equatable {
    public var detalle: DetalleVias
    /// Por índice del trazado pedido, las aristas que cruzan el nodo que hay
    /// en él: el nodo final de cada arista de la ruta (`end_shape_index`).
    /// Solo los nodos que tienen alguna, y solo las que traen rumbo. Si dos
    /// aristas acaban en el mismo índice, van las de las dos.
    public var aristasQueCruzan: [Int: [AristaQueCruza]]
    /// `end_shape_index` de la última arista; nil sin aristas o si no viene.
    public var ultimoIndice: Int?

    public init(detalle: DetalleVias, aristasQueCruzan: [Int: [AristaQueCruza]] = [:], ultimoIndice: Int? = nil) {
        self.detalle = detalle
        self.aristasQueCruzan = aristasQueCruzan
        self.ultimoIndice = ultimoIndice
    }

    /// Si los índices son de un trazado de `puntos` puntos: la última arista
    /// acaba en su último punto. Con `walk_or_snap`, si el recorrido de las
    /// aristas falla y Valhalla ajusta la forma al mapa, los índices serían
    /// de otra forma (supuesto: en las 3 rutas del estudio, del 2026-10-09,
    /// la última arista acababa en el último punto).
    public func encaja(puntos: Int) -> Bool {
        guard let ultimoIndice else { return false }
        return ultimoIndice == puntos - 1
    }
}

/// /trace_attributes de Valhalla: los atributos de cada arista de una forma.
/// Comprobado con valhalla1.openstreetmap.de el 2026-10-09: con la forma de
/// una ruta suya, `walk_or_snap` responde en menos de medio segundo y da
/// `road_class`, `use`, `length`, `toll` y `unpaved` de cada arista (con
/// `edge_walk` solo, la misma ruta fallaba con el error 443). Desde la 0.14.0,
/// también el índice del trazado en que acaba cada arista y, de su nodo
/// final, el rumbo y el uso de las aristas que lo cruzan (comprobado con 3
/// rutas reales el 2026-10-09: todas las calles laterales de sus cruces casan
/// con una de ellas a 4° o menos).
public enum RespuestaAtributos {
    static let atributos = [
        "edge.road_class", "edge.use", "edge.length", "edge.toll", "edge.unpaved", "edge.end_shape_index",
        "node.intersecting_edge.begin_heading", "node.intersecting_edge.use",
        // No se usa: va porque el estudio lo pedía y con él está comprobado
        // que llega end_node (sin él, no comprobado)
        "node.type",
    ]

    /// Cuerpo de la petición para la forma de una ruta, en polyline6.
    public static func cuerpo(forma: [PuntoRuta]) -> [String: Any] {
        [
            "encoded_polyline": Polilinea.codificar(forma, precision: 6),
            "shape_match": "walk_or_snap",
            "costing": "motorcycle",
            "filters": ["attributes": atributos, "action": "include"],
            "units": "kilometers",
        ]
    }

    /// Suma las aristas. Lanza un error si no es una respuesta de
    /// /trace_attributes.
    public static func detalle(de datos: Data) throws -> DetalleVias {
        try leer(datos).detalle
    }

    /// Las aristas sumadas y las que cruzan cada nodo. Lanza un error si no es
    /// una respuesta de /trace_attributes.
    public static func leer(_ datos: Data) throws -> AtributosRuta {
        let respuesta = try JSONDecoder().decode(Respuesta.self, from: datos)
        let metrosPorUnidad = respuesta.units == "miles" ? 1_609.344 : 1_000
        var detalle = DetalleVias(metrosAutopista: 0, metrosPeaje: 0, metrosSinAsfaltar: 0, metros: 0)
        var cruzan: [Int: [AristaQueCruza]] = [:]
        for arista in respuesta.edges {
            let metros = max(0, arista.length ?? 0) * metrosPorUnidad
            detalle.metros += metros
            // Los enlaces (use "ramp") no cuentan como autopista
            if arista.road_class == "motorway" && (arista.use == nil || arista.use == "road") {
                detalle.metrosAutopista += metros
            }
            if arista.toll == true {
                detalle.metrosPeaje += metros
            }
            if arista.unpaved == true {
                detalle.metrosSinAsfaltar += metros
            }
            guard let indice = arista.end_shape_index, indice >= 0 else { continue }
            let suyas = (arista.end_node?.intersecting_edges ?? []).compactMap { cruce -> AristaQueCruza? in
                guard let rumbo = cruce.begin_heading, rumbo.isFinite else { return nil }
                return AristaQueCruza(rumbo: rumbo, uso: cruce.use)
            }
            if !suyas.isEmpty {
                cruzan[indice, default: []].append(contentsOf: suyas)
            }
        }
        return AtributosRuta(detalle: detalle, aristasQueCruzan: cruzan,
                             ultimoIndice: respuesta.edges.last?.end_shape_index)
    }

    struct Respuesta: Decodable {
        let edges: [Arista]
        let units: String?
    }

    struct Arista: Decodable {
        let length: Double?
        let road_class: String?
        let use: String?
        let toll: Bool?
        let unpaved: Bool?
        let end_shape_index: Int?
        let end_node: Nodo?
    }

    struct Nodo: Decodable {
        let intersecting_edges: [AristaCruce]?
    }

    struct AristaCruce: Decodable {
        let begin_heading: Double?
        let use: String?
    }
}
