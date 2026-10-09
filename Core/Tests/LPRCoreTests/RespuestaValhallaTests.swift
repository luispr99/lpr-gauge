import Foundation
import XCTest
@testable import LPRCore

// Respuesta inventada con la forma de /route de Valhalla en formato "json"
// (coordenadas inventadas, base 40,0 N 3,0 O, en metros).
final class RespuestaValhallaTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    private func maniobra(
        _ tipo: Int,
        km: Double,
        _ desde: Int,
        _ hasta: Int,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var datos: [String: Any] = [
            "type": tipo,
            "length": km,
            "time": km * 100,
            "begin_shape_index": desde,
            "end_shape_index": hasta,
            "instruction": "Instrucción inventada",
        ]
        datos.merge(extra) { _, nuevo in nuevo }
        return datos
    }

    private func viaje(forma: [PuntoRuta], maniobras: [[String: Any]], km: Double, segundos: Double) -> [String: Any] {
        [
            "legs": [["shape": Polilinea.codificar(forma), "maneuvers": maniobras]],
            "summary": ["length": km, "time": segundos, "has_toll": false],
        ]
    }

    private var respuesta: Data {
        // Principal: empieza en tierra, pasa una rotonda y sigue por peaje
        let principal = viaje(
            forma: (0...5).map { punto(0, Double($0) * 100) },
            maniobras: [
                maniobra(1, km: 0.2, 0, 2, extra: ["rough": true]),
                maniobra(26, km: 0.1, 2, 3, extra: ["roundabout_exit_count": 2]),
                maniobra(27, km: 0.2, 3, 5, extra: ["toll": true, "highway": true]),
                maniobra(4, km: 0, 5, 5),
            ],
            km: 0.5,
            segundos: 60
        )
        // Alternativa: tierra en una maniobra intermedia
        let alternativa = viaje(
            forma: (0...3).map { punto(Double($0) * 100, 0) },
            maniobras: [
                maniobra(1, km: 0.1, 0, 1),
                maniobra(10, km: 0.1, 1, 2, extra: ["rough": true]),
                maniobra(8, km: 0.1, 2, 3),
                maniobra(4, km: 0, 3, 3),
            ],
            km: 0.3,
            segundos: 40
        )
        let json: [String: Any] = ["trip": principal, "alternates": [["trip": alternativa]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testRutasEnOrden() throws {
        let rutas = try RespuestaValhalla.rutas(de: respuesta)
        XCTAssertEqual(rutas.count, 2)
        XCTAssertEqual(rutas[0].metros, 500, accuracy: 0.001)
        XCTAssertEqual(rutas[0].segundos, 60, accuracy: 0.001)
        XCTAssertEqual(rutas[1].metros, 300, accuracy: 0.001)
        XCTAssertEqual(rutas[0].puntos.count, 6)
        XCTAssertEqual(rutas[1].puntos.count, 4)
    }

    func testPeajeYTierra() throws {
        let rutas = try RespuestaValhalla.rutas(de: respuesta)
        XCTAssertEqual(rutas[0].metrosPeaje, 200, accuracy: 0.001)
        XCTAssertEqual(rutas[0].metrosSinAsfaltar, 200, accuracy: 0.001)
        // Empieza en tierra: no cuenta como tierra en medio
        XCTAssertFalse(rutas[0].tierraEnMedio)
        XCTAssertEqual(rutas[0].metrosAutopista, 200, accuracy: 0.001)
        XCTAssertEqual(rutas[1].metrosPeaje, 0)
        XCTAssertEqual(rutas[1].metrosAutopista, 0)
        XCTAssertEqual(rutas[1].metrosSinAsfaltar, 100, accuracy: 0.001)
        XCTAssertTrue(rutas[1].tierraEnMedio)
    }

    func testTierraEnMedioSoloEntreAsfalto() throws {
        let rutas = try RespuestaValhalla.rutas(de: respuesta)
        XCTAssertEqual(rutas[0].metrosSinAsfaltarEnMedio, 0)
        XCTAssertEqual(rutas[1].metrosSinAsfaltarEnMedio, 100, accuracy: 0.001)
    }

    func testTierraSeguidaDesdeLaSalidaNoCuenta() throws {
        // Dos maniobras de tierra seguidas al salir, luego asfalto
        let viajeTierra = viaje(
            forma: (0...4).map { punto(0, Double($0) * 100) },
            maniobras: [
                maniobra(1, km: 0.1, 0, 1, extra: ["rough": true]),
                maniobra(10, km: 0.1, 1, 2, extra: ["rough": true]),
                maniobra(15, km: 0.2, 2, 4),
                maniobra(4, km: 0, 4, 4),
            ],
            km: 0.4,
            segundos: 50
        )
        let datos = try JSONSerialization.data(withJSONObject: ["trip": viajeTierra])
        let ruta = try XCTUnwrap(try RespuestaValhalla.rutas(de: datos).first)
        XCTAssertFalse(ruta.tierraEnMedio)
        XCTAssertEqual(ruta.metrosSinAsfaltar, 200, accuracy: 0.001)
        XCTAssertEqual(ruta.metrosSinAsfaltarEnMedio, 0)
    }

    func testTramoEnteroDeTierra() throws {
        let viajeTierra = viaje(
            forma: (0...2).map { punto(0, Double($0) * 100) },
            maniobras: [
                maniobra(1, km: 0.1, 0, 1, extra: ["rough": true]),
                maniobra(8, km: 0.1, 1, 2, extra: ["rough": true]),
                maniobra(4, km: 0, 2, 2),
            ],
            km: 0.2,
            segundos: 30
        )
        let datos = try JSONSerialization.data(withJSONObject: ["trip": viajeTierra])
        let ruta = try XCTUnwrap(try RespuestaValhalla.rutas(de: datos).first)
        // Como exclude_unpaved: empieza y acaba en tierra
        XCTAssertFalse(ruta.tierraEnMedio)
        XCTAssertEqual(ruta.metrosSinAsfaltarEnMedio, 200, accuracy: 0.001)
    }

    func testTramosSinRotondas() throws {
        let rutas = try RespuestaValhalla.rutas(de: respuesta)
        // Principal: la salida (0–2) y lo que sigue a la rotonda (3–5)
        XCTAssertEqual(rutas[0].tramosParaCurvas.map(\.count), [3, 3])
        XCTAssertEqual(rutas[1].tramosParaCurvas.map(\.count), [2, 2, 2])
    }

    func testSinAlternativas() throws {
        var json = try JSONSerialization.jsonObject(with: respuesta) as! [String: Any]
        json["alternates"] = nil
        let datos = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try RespuestaValhalla.rutas(de: datos).count, 1)
    }

    func testMensajeDeError() {
        let fallo = Data(#"{"error_code":442,"error":"No path could be found for input","status_code":400}"#.utf8)
        XCTAssertEqual(RespuestaValhalla.mensajeDeError(fallo), "No path could be found for input")
        XCTAssertNil(RespuestaValhalla.mensajeDeError(respuesta))
    }
}
