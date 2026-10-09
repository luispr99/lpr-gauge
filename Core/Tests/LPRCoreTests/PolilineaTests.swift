import XCTest
@testable import LPRCore

final class PolilineaTests: XCTestCase {
    // Ejemplo de la documentación del formato (Google, precisión 5)
    private let ejemplo = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    private let puntosEjemplo = [
        PuntoRuta(latitud: 38.5, longitud: -120.2),
        PuntoRuta(latitud: 40.7, longitud: -120.95),
        PuntoRuta(latitud: 43.252, longitud: -126.453),
    ]

    func testDecodificarEjemplo() {
        let puntos = Polilinea.decodificar(ejemplo, precision: 5)
        XCTAssertEqual(puntos.count, 3)
        for (punto, esperado) in zip(puntos, puntosEjemplo) {
            XCTAssertEqual(punto.latitud, esperado.latitud, accuracy: 1e-9)
            XCTAssertEqual(punto.longitud, esperado.longitud, accuracy: 1e-9)
        }
    }

    func testCodificarEjemplo() {
        XCTAssertEqual(Polilinea.codificar(puntosEjemplo, precision: 5), ejemplo)
    }

    func testIdaYVueltaConSeisDecimales() {
        let puntos = [
            PuntoRuta(latitud: 40.416800, longitud: -3.703800),
            PuntoRuta(latitud: 40.416912, longitud: -3.703455),
            PuntoRuta(latitud: 40.942900, longitud: -4.108800),
        ]
        let vuelta = Polilinea.decodificar(Polilinea.codificar(puntos))
        XCTAssertEqual(vuelta.count, puntos.count)
        for (punto, esperado) in zip(vuelta, puntos) {
            XCTAssertEqual(punto.latitud, esperado.latitud, accuracy: 1e-9)
            XCTAssertEqual(punto.longitud, esperado.longitud, accuracy: 1e-9)
        }
    }

    func testTextoVacioOIncompleto() {
        XCTAssertEqual(Polilinea.decodificar(""), [])
        // Solo la latitud del primer punto: se descarta
        XCTAssertEqual(Polilinea.decodificar("_p~iF", precision: 5), [])
    }
}
