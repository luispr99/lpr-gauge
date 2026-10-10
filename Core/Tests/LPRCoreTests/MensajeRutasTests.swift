import Foundation
import XCTest
@testable import LPRCore

final class MensajeRutasTests: XCTestCase {
    /// Rutas de prueba (nombres inventados).
    private let dos = [
        RutaCuadro(tipo: 1, peajes: false, autovias: false, margen: 50, nombre: "Madrid"),
        RutaCuadro(tipo: 0, peajes: true, autovias: true, margen: 25, nombre: "Taller ñ"),
    ]

    func testCodificaYDecodifica() {
        // docs/vectores/mensajes.md: secuencia 7, calculando, eco 3, dos rutas.
        // La primera: curvas (1), sin peajes ni autovías (0), +50 %, «Madrid»
        let mensaje = MensajeRutas(secuencia: 7, estado: .calculando, ecoOrden: 3, rutas: dos)
        let bytes = mensaje.codificar()
        XCTAssertEqual(Array(bytes.prefix(5)), [0x01, 0x07, 0x01, 0x03, 0x02])
        XCTAssertEqual(Array(bytes[5..<15]), [0x01, 0x00, 0x32, 0x06, 0x4D, 0x61, 0x64, 0x72, 0x69, 0x64])
        // La segunda: peajes y autovías (3), +25 %, «Taller ñ» (9 bytes)
        XCTAssertEqual(Array(bytes[15..<19]), [0x00, 0x03, 0x19, 0x09])
        XCTAssertEqual(bytes.count, 5 + 10 + 13)
        XCTAssertEqual(MensajeRutas.decodificar(bytes), mensaje)
    }

    func testConPropuesta() {
        // Estado 4: la propuesta detrás. Curvas, sin cambio de tipo, 58 km
        // (5800 dam), 65 min, 112 curvas, 18 min de más, sin peaje, 2,1 km
        // de autopista (210 dam)
        let propuesta = PropuestaRuta(tipo: 1, metros: 58_000, segundos: 3_900, curvas: 112, segundosDeMas: 1_080,
                                      metrosPeaje: 0, metrosAutopista: 2_100)
        let mensaje = MensajeRutas(secuencia: 8, estado: .propuesta, ecoOrden: 4, rutas: Array(dos.prefix(1)),
                                   propuesta: propuesta)
        let bytes = mensaje.codificar()
        XCTAssertEqual(Array(bytes.suffix(14)), [
            0x01, 0x00, 0xA8, 0x16, 0x41, 0x00, 0x70, 0x00, 0x12, 0x00, 0x00, 0x00, 0xD2, 0x00,
        ])
        XCTAssertEqual(MensajeRutas.decodificar(bytes), mensaje)
        // Sin la propuesta entera, se descarta
        XCTAssertNil(MensajeRutas.decodificar(Array(bytes.dropLast())))
        // Estado 4 sin propuesta: va como 3 (no se pudo)
        let sin = MensajeRutas(secuencia: 9, estado: .propuesta, rutas: dos).codificar()
        XCTAssertEqual(sin[2], 0x03)
        // La más rápida en vez de la de curvas, y datos sin saber
        let otra = PropuestaRuta(tipo: 0, otroTipo: true, metros: nil, segundos: nil, curvas: nil, segundosDeMas: nil,
                                 metrosPeaje: nil, metrosAutopista: nil)
        let bytesOtra = MensajeRutas(secuencia: 1, estado: .propuesta, rutas: [], propuesta: otra).codificar()
        XCTAssertEqual(Array(bytesOtra.suffix(14)), [0x00, 0x01] + Array(repeating: 0xFF, count: 12))
        XCTAssertEqual(MensajeRutas.decodificar(bytesOtra)?.propuesta, otra)
    }

    func testNombresCortadosParaCaber() {
        let largo = String(repeating: "á", count: 30)   // 60 bytes
        let tres = (0..<3).map { RutaCuadro(tipo: 0, peajes: true, autovias: false, margen: 0, nombre: largo + "\($0)") }
        let mensaje = MensajeRutas(secuencia: 1, rutas: tres)
        // Sin límite: 40 bytes cada uno (20 «á»)
        let entero = mensaje.codificar()
        XCTAssertEqual(entero.count, 5 + 3 * 44)
        XCTAssertEqual(MensajeRutas.decodificar(entero)?.rutas.map(\.nombre),
                       Array(repeating: String(repeating: "á", count: 20), count: 3))
        // Con 60 bytes: 5 + 3 × 4 = 17 fijos; 43 para nombres, 14 cada uno
        // como mucho (7 «á»)
        let justo = mensaje.codificar(maximo: 60)
        XCTAssertLessThanOrEqual(justo.count, 60)
        XCTAssertEqual(MensajeRutas.decodificar(justo)?.rutas.map(\.nombre),
                       Array(repeating: String(repeating: "á", count: 7), count: 3))
        // Con propuesta y 30 bytes: 5 + 14 = 19; caben dos rutas sin nombre
        let p = PropuestaRuta(tipo: 0, metros: 1, segundos: 1, curvas: 1, segundosDeMas: 0, metrosPeaje: 0,
                              metrosAutopista: 0)
        var con = mensaje
        con.estado = .propuesta
        con.propuesta = p
        let corto = con.codificar(maximo: 30)
        XCTAssertLessThanOrEqual(corto.count, 30)
        XCTAssertEqual(MensajeRutas.decodificar(corto)?.rutas.count, 2)
        XCTAssertNotNil(MensajeRutas.decodificar(corto)?.propuesta)
    }

    func testDescartesYMargen() {
        let bytes = MensajeRutas(secuencia: 2, rutas: [RutaCuadro(tipo: 0, peajes: false, autovias: true, margen: 250,
                                                                  nombre: "X")]).codificar()
        // El margen se satura en 200
        XCTAssertEqual(Array(bytes[5..<10]), [0x00, 0x02, 0xC8, 0x01, 0x58])
        var mal = bytes
        mal[4] = 4
        XCTAssertNil(MensajeRutas.decodificar(mal))
        XCTAssertNil(MensajeRutas.decodificar(Array(bytes.dropLast())))
        mal = bytes
        mal[0] = 2
        XCTAssertNil(MensajeRutas.decodificar(mal))
        mal = bytes
        mal[9] = 0xFF
        XCTAssertNil(MensajeRutas.decodificar(mal))
        // Más de tres rutas: van las tres primeras
        XCTAssertEqual(MensajeRutas.decodificar(MensajeRutas(secuencia: 3, rutas: dos + dos).codificar())?.rutas.count, 3)
    }

    func testDesdeUnaGuardada() {
        let guardada = RutaGuardada(nombre: "Sitio", latitud: 40, longitud: -3, tipo: "divertida", evitarPeajes: true,
                                    evitarAutopistas: false, margen: 0.5, metros: 20_000, segundos: 1_500, curvas: 40,
                                    fecha: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(RutaCuadro(guardada), RutaCuadro(tipo: 1, peajes: false, autovias: true, margen: 50, nombre: "Sitio"))
        XCTAssertEqual(RutaCuadro.codigo(tipo: "tierra"), 2)
        XCTAssertEqual(RutaCuadro.codigo(tipo: "otro"), 0)
    }
}
