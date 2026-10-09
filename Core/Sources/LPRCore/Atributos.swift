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

/// /trace_attributes de Valhalla: los atributos de cada arista de una forma.
/// Comprobado con valhalla1.openstreetmap.de el 2026-10-09: con la forma de
/// una ruta suya, `walk_or_snap` responde en menos de medio segundo y da
/// `road_class`, `use`, `length`, `toll` y `unpaved` de cada arista (con
/// `edge_walk` solo, la misma ruta fallaba con el error 443).
public enum RespuestaAtributos {
    static let atributos = ["edge.road_class", "edge.use", "edge.length", "edge.toll", "edge.unpaved"]

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
        let respuesta = try JSONDecoder().decode(Respuesta.self, from: datos)
        let metrosPorUnidad = respuesta.units == "miles" ? 1_609.344 : 1_000
        var detalle = DetalleVias(metrosAutopista: 0, metrosPeaje: 0, metrosSinAsfaltar: 0, metros: 0)
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
        }
        return detalle
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
    }
}
