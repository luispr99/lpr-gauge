import Foundation
import XCTest
@testable import LPRCore

// Posiciones inventadas (base 40,0 N 3,0 O), en metros respecto a esa base: x
// hacia el este, y hacia el norte.
final class ViajeTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    private let inicio = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func segundo(_ s: Double) -> Date {
        inicio.addingTimeInterval(s)
    }

    func testCuentakilometros() {
        var cuenta = Cuentakilometros(inicio: inicio)
        // La primera cuenta, sin sumar nada
        XCTAssertTrue(cuenta.anadir(punto(0, 0), precision: 5, instante: segundo(1)))
        XCTAssertEqual(cuenta.metros, 0)
        // 20 m en 1 s
        XCTAssertTrue(cuenta.anadir(punto(0, 20), precision: 5, instante: segundo(2)))
        XCTAssertEqual(cuenta.metros, 20, accuracy: 0.01)
        // Imprecisa (80 m) o sin precisión (negativa, como Core Location): no
        XCTAssertFalse(cuenta.anadir(punto(0, 40), precision: 80, instante: segundo(3)))
        XCTAssertFalse(cuenta.anadir(punto(0, 40), precision: -1, instante: segundo(3)))
        // Un salto imposible: 500 m en 2 s (250 m/s); se descarta
        XCTAssertFalse(cuenta.anadir(punto(500, 20), precision: 5, instante: segundo(4)))
        XCTAssertEqual(cuenta.metros, 20, accuracy: 0.01)
        // La siguiente, desde la última buena: 40 m en 3 s
        XCTAssertTrue(cuenta.anadir(punto(0, 60), precision: 10, instante: segundo(5)))
        XCTAssertEqual(cuenta.metros, 60, accuracy: 0.01)
        // En otro sitio en el mismo instante: imposible. En el mismo sitio, nada
        XCTAssertFalse(cuenta.anadir(punto(0, 70), precision: 5, instante: segundo(5)))
        XCTAssertTrue(cuenta.anadir(punto(0, 60), precision: 5, instante: segundo(5)))
        XCTAssertEqual(cuenta.metros, 60, accuracy: 0.01)
        // Con 50 m de precisión justos, cuenta: 70 m en 2 s
        XCTAssertTrue(cuenta.anadir(punto(0, 130), precision: 50, instante: segundo(7)))
        XCTAssertEqual(cuenta.metros, 130, accuracy: 0.01)
        // Por debajo de 70 m/s, cuenta: 138 m en 2 s (69 m/s)
        XCTAssertTrue(cuenta.anadir(punto(0, 268), precision: 5, instante: segundo(9)))
        XCTAssertEqual(cuenta.metros, 268, accuracy: 0.01)

        // Mientras sigue, el tiempo es hasta ahora (paradas incluidas)
        XCTAssertEqual(cuenta.resumen(ahora: segundo(20)), ResumenViaje(segundos: 20, metros: cuenta.metros))
        // Al llegar se para: ni el tiempo ni la distancia cambian después
        cuenta.parar(segundo(10))
        XCTAssertFalse(cuenta.anadir(punto(0, 300), precision: 5, instante: segundo(11)))
        cuenta.parar(segundo(30))
        let resumen = cuenta.resumen(ahora: segundo(100))
        XCTAssertEqual(resumen.segundos, 10)
        XCTAssertEqual(resumen.metros, 268, accuracy: 0.01)
        // 268 m en 10 s: 26,8 m/s
        XCTAssertEqual(try XCTUnwrap(resumen.velocidadMedia), 26.8, accuracy: 0.01)
    }

    func testResumenSinTiempo() {
        XCTAssertNil(ResumenViaje(segundos: 0, metros: 100).velocidadMedia)
        XCTAssertNil(ResumenViaje(segundos: .infinity, metros: 100).velocidadMedia)
        // Antes del inicio, 0 s
        XCTAssertEqual(Cuentakilometros(inicio: inicio).resumen(ahora: segundo(-5)).segundos, 0)
        // 123 456 m en 5025 s: 88,4 km/h (el vector de NAV con el resumen)
        let media = ResumenViaje(segundos: 5_025, metros: 123_456).velocidadMedia ?? 0
        XCTAssertEqual(media * 3.6, 88.45, accuracy: 0.01)
    }
}
