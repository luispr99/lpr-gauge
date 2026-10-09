import Foundation
import XCTest
@testable import LPRCore

final class MensajeRutasTests: XCTestCase {
    /// Rutas de prueba (nombres y datos inventados).
    private let dos = [
        RutaCuadro(tipo: 1, metros: 58_000, segundos: 3_900, curvas: 112, metrosPeaje: 0, metrosAutopista: 12_340,
                   nombre: "Puerto"),
        RutaCuadro(tipo: 0, metros: 12_000, segundos: 1_080, curvas: 9, metrosPeaje: 2_500, metrosAutopista: 0,
                   nombre: "Taller ñ"),
    ]

    func testCodificaYDecodifica() {
        // docs/vectores/mensajes.md: secuencia 7, calculando, eco 3, dos rutas.
        // La primera: curvas (1), 5800 dam, 65 min, 112 curvas, sin peaje,
        // 1234 dam de autopista, «Puerto» (6 bytes)
        let mensaje = MensajeRutas(secuencia: 7, estado: .calculando, ecoOrden: 3, rutas: dos)
        let bytes = mensaje.codificar()
        XCTAssertEqual(Array(bytes.prefix(5)), [0x01, 0x07, 0x01, 0x03, 0x02])
        XCTAssertEqual(Array(bytes[5..<23]), [
            0x01, 0xA8, 0x16, 0x41, 0x00, 0x70, 0x00, 0x00, 0x00, 0xD2, 0x04, 0x06,
            0x50, 0x75, 0x65, 0x72, 0x74, 0x6F,
        ])
        // La segunda: «Taller ñ» son 9 bytes (la ñ, dos)
        XCTAssertEqual(bytes.count, 5 + 18 + 12 + 9)
        XCTAssertEqual(MensajeRutas.decodificar(bytes), mensaje)
    }

    func testNombresCortadosParaCaber() {
        let largo = String(repeating: "á", count: 30)   // 60 bytes
        let tres = (0..<3).map { RutaCuadro(tipo: 0, metros: 1_000, segundos: 60, curvas: 1, nombre: largo + "\($0)") }
        let mensaje = MensajeRutas(secuencia: 1, rutas: tres)
        // Sin límite: 40 bytes cada uno (20 «á»), sin partir ninguna
        let entero = mensaje.codificar()
        XCTAssertEqual(entero.count, MensajeRutas.longitudMaxima)
        XCTAssertEqual(MensajeRutas.decodificar(entero)?.rutas.map(\.nombre), Array(repeating: String(repeating: "á", count: 20), count: 3))
        // Con 100 bytes: 5 + 3 × 12 = 41 fijos; 59 para nombres, 19 cada uno
        // como mucho, que sin partir una «á» se quedan en 18
        let justo = mensaje.codificar(maximo: 100)
        XCTAssertLessThanOrEqual(justo.count, 100)
        XCTAssertEqual(MensajeRutas.decodificar(justo)?.rutas.map(\.nombre), Array(repeating: String(repeating: "á", count: 9), count: 3))
        // Con 30 bytes no caben las tres ni sin nombre: van dos
        let corto = mensaje.codificar(maximo: 30)
        XCTAssertEqual(MensajeRutas.decodificar(corto)?.rutas.count, 2)
        XCTAssertEqual(MensajeRutas.decodificar(corto)?.rutas.first?.nombre, "")
    }

    func testDesconocidosYDescartes() {
        let sin = MensajeRutas(secuencia: 2, rutas: [RutaCuadro(tipo: 0, metros: nil, segundos: nil, curvas: nil,
                                                                 nombre: "X")])
        let bytes = sin.codificar()
        XCTAssertEqual(Array(bytes[6..<16]), Array(repeating: 0xFF, count: 10))
        XCTAssertEqual(MensajeRutas.decodificar(bytes), sin)
        // Más de tres, cortado, otra versión, nombre que no es UTF-8
        var mal = bytes
        mal[4] = 4
        XCTAssertNil(MensajeRutas.decodificar(mal))
        XCTAssertNil(MensajeRutas.decodificar(Array(bytes.dropLast())))
        mal = bytes
        mal[0] = 2
        XCTAssertNil(MensajeRutas.decodificar(mal))
        mal = bytes
        mal[17] = 0xFF
        XCTAssertNil(MensajeRutas.decodificar(mal))
        // Más de tres rutas: van las tres primeras
        let cuatro = MensajeRutas(secuencia: 3, rutas: dos + dos)
        XCTAssertEqual(MensajeRutas.decodificar(cuatro.codificar())?.rutas.count, 3)
    }

    func testDesdeUnaGuardada() {
        let guardada = RutaGuardada(nombre: "Sitio", latitud: 40, longitud: -3, tipo: "divertida", evitarPeajes: true,
                                    evitarAutopistas: false, margen: 0.25, metros: 20_000, segundos: 1_500, curvas: 40,
                                    metrosPeaje: 300, metrosAutopista: 4_000, fecha: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(RutaCuadro(guardada), RutaCuadro(tipo: 1, metros: 20_000, segundos: 1_500, curvas: 40,
                                                        metrosPeaje: 300, metrosAutopista: 4_000, nombre: "Sitio"))
    }
}
