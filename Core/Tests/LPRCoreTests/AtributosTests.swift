import Foundation
import XCTest
@testable import LPRCore

// Respuestas de /trace_attributes escritas a mano con la forma de las de
// Valhalla, con longitudes inventadas.
final class AtributosTests: XCTestCase {
    func testSumaTramoATramo() throws {
        // Como la maniobra de «tomar la SG-20»: 3,5 km de autovía y después la
        // nacional (trunk), más un enlace, un tramo de peaje y uno de tierra
        let datos = Data(#"""
        {
          "units": "kilometers",
          "edges": [
            { "road_class": "motorway", "use": "ramp", "length": 0.4, "toll": false, "unpaved": false },
            { "road_class": "motorway", "use": "road", "length": 3.5, "toll": false, "unpaved": false },
            { "road_class": "trunk", "use": "road", "length": 28.0, "toll": false, "unpaved": false },
            { "road_class": "motorway", "use": "road", "length": 1.0, "toll": true, "unpaved": false },
            { "road_class": "tertiary", "use": "road", "length": 0.5, "toll": false, "unpaved": true },
            { "road_class": "motorway", "length": 0.25 }
          ],
          "alternate_paths": []
        }
        """#.utf8)
        let detalle = try RespuestaAtributos.detalle(de: datos)
        XCTAssertEqual(detalle.metrosAutopista, 4_750, accuracy: 0.01)   // 3,5 + 1,0 + 0,25 (sin el enlace)
        XCTAssertEqual(detalle.metrosPeaje, 1_000, accuracy: 0.01)
        XCTAssertEqual(detalle.metrosSinAsfaltar, 500, accuracy: 0.01)
        XCTAssertEqual(detalle.metros, 33_650, accuracy: 0.01)
    }

    func testEnMillas() throws {
        let datos = Data(#"{ "units": "miles", "edges": [ { "road_class": "motorway", "use": "road", "length": 1.0 } ] }"#.utf8)
        XCTAssertEqual(try RespuestaAtributos.detalle(de: datos).metrosAutopista, 1_609.344, accuracy: 0.001)
    }

    func testNoEsUnaRespuesta() {
        XCTAssertThrowsError(try RespuestaAtributos.detalle(de: Data(#"{"error_code":443}"#.utf8)))
    }

    func testAristasQueCruzan() throws {
        // Como las de Valhalla con node.intersecting_edge (rumbos y usos
        // inventados): la primera arista acaba en el punto 1, con una calle y
        // una acera; la segunda, en el 3, sin nodo; la tercera, también en el
        // 3 (de longitud 0), con un camino y una arista sin rumbo; la última,
        // en el 5, con un nodo sin aristas que cruzan
        let datos = Data(#"""
        {
          "units": "kilometers",
          "edges": [
            { "road_class": "residential", "use": "road", "length": 0.1, "end_shape_index": 1,
              "end_node": { "intersecting_edges": [
                { "begin_heading": 91, "use": "road", "road_class": "residential" },
                { "begin_heading": 268, "use": "footway" }
              ], "type": "street_intersection" } },
            { "road_class": "residential", "use": "road", "length": 0.2, "end_shape_index": 3 },
            { "road_class": "residential", "use": "road", "length": 0.0, "end_shape_index": 3,
              "end_node": { "intersecting_edges": [ { "begin_heading": 45, "use": "path" }, { "use": "road" } ] } },
            { "road_class": "service_other", "use": "parking_aisle", "length": 0.05, "end_shape_index": 5,
              "end_node": { "type": "street_intersection" } }
          ],
          "alternate_paths": []
        }
        """#.utf8)
        let atributos = try RespuestaAtributos.leer(datos)
        XCTAssertEqual(atributos.detalle.metros, 350, accuracy: 0.01)
        XCTAssertEqual(atributos.detalle, try RespuestaAtributos.detalle(de: datos))
        XCTAssertEqual(atributos.aristasQueCruzan, [
            1: [AristaQueCruza(rumbo: 91, uso: "road"), AristaQueCruza(rumbo: 268, uso: "footway")],
            3: [AristaQueCruza(rumbo: 45, uso: "path")],
        ])
        XCTAssertEqual(atributos.ultimoIndice, 5)
        // Encaja con un trazado de 6 puntos (la última arista acaba en el
        // último), no con otro
        XCTAssertTrue(atributos.encaja(puntos: 6))
        XCTAssertFalse(atributos.encaja(puntos: 7))
        // Sin end_shape_index (una respuesta de antes de la 0.14.0): sin
        // aristas que cruzan y sin encajar con nada
        let antigua = try RespuestaAtributos.leer(Data(#"{ "edges": [ { "use": "road", "length": 1.0 } ] }"#.utf8))
        XCTAssertEqual(antigua.aristasQueCruzan, [:])
        XCTAssertNil(antigua.ultimoIndice)
        XCTAssertFalse(antigua.encaja(puntos: 2))
    }

    func testCuerpo() {
        let forma = [PuntoRuta(latitud: 40.0, longitud: -3.0), PuntoRuta(latitud: 40.0009, longitud: -3.0)]
        let cuerpo = RespuestaAtributos.cuerpo(forma: forma)
        XCTAssertEqual(cuerpo["encoded_polyline"] as? String, Polilinea.codificar(forma, precision: 6))
        XCTAssertEqual(cuerpo["shape_match"] as? String, "walk_or_snap")
        XCTAssertEqual(cuerpo["costing"] as? String, "motorcycle")
        let filtros = cuerpo["filters"] as? [String: Any]
        XCTAssertEqual(filtros?["action"] as? String, "include")
        XCTAssertEqual((filtros?["attributes"] as? [String])?.contains("edge.road_class"), true)
        // Para casar las calles de CRUCES con las aristas que cruzan (0.14.0)
        for atributo in ["edge.end_shape_index", "node.intersecting_edge.begin_heading", "node.intersecting_edge.use"] {
            XCTAssertEqual((filtros?["attributes"] as? [String])?.contains(atributo), true, atributo)
        }
    }
}
