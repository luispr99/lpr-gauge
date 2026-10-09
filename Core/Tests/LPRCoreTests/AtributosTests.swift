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

    func testCuerpo() {
        let forma = [PuntoRuta(latitud: 40.0, longitud: -3.0), PuntoRuta(latitud: 40.0009, longitud: -3.0)]
        let cuerpo = RespuestaAtributos.cuerpo(forma: forma)
        XCTAssertEqual(cuerpo["encoded_polyline"] as? String, Polilinea.codificar(forma, precision: 6))
        XCTAssertEqual(cuerpo["shape_match"] as? String, "walk_or_snap")
        XCTAssertEqual(cuerpo["costing"] as? String, "motorcycle")
        let filtros = cuerpo["filters"] as? [String: Any]
        XCTAssertEqual(filtros?["action"] as? String, "include")
        XCTAssertEqual((filtros?["attributes"] as? [String])?.contains("edge.road_class"), true)
    }
}
