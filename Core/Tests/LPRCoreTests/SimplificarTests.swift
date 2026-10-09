import Foundation
import XCTest
@testable import LPRCore

// Trazados sintéticos con coordenadas inventadas (base 40,0 N 3,0 O), en metros
// respecto a esa base.
final class SimplificarTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    func testRectaQuedaEnDosPuntos() {
        let recta = (0...100).map { punto(0, Double($0) * 10) }
        let simple = Simplificar.douglasPeucker(recta, tolerancia: 1)
        XCTAssertEqual(simple.count, 2)
        XCTAssertEqual(simple.first, recta.first)
        XCTAssertEqual(simple.last, recta.last)
    }

    func testZigzagSegunTolerancia() {
        // Zigzag de ±10 m cada 100 m
        let zigzag = (0...20).map { punto($0 % 2 == 0 ? -10 : 10, Double($0) * 100) }
        XCTAssertEqual(Simplificar.douglasPeucker(zigzag, tolerancia: 5).count, zigzag.count)
        XCTAssertEqual(Simplificar.douglasPeucker(zigzag, tolerancia: 30).count, 2)
    }

    func testConservaElVertice() {
        // Una L: el vértice se separa 500 m de la línea entre los extremos
        let ele = (0...10).map { punto(0, Double($0) * 100) } + (1...10).map { punto(Double($0) * 100, 1000) }
        let simple = Simplificar.douglasPeucker(ele, tolerancia: 10)
        XCTAssertEqual(simple, [punto(0, 0), punto(0, 1000), punto(1000, 1000)])
    }

    func testSinToleranciaOPocosPuntos() {
        let pocos = [punto(0, 0), punto(5, 5)]
        XCTAssertEqual(Simplificar.douglasPeucker(pocos, tolerancia: 100), pocos)
        let tres = [punto(0, 0), punto(1, 50), punto(0, 100)]
        XCTAssertEqual(Simplificar.douglasPeucker(tres, tolerancia: 0), tres)
    }

    func testDistanciaAlTrazado() {
        let trazado = (0...10).map { punto(0, Double($0) * 100) }
        XCTAssertEqual(try XCTUnwrap(Simplificar.distancia(de: punto(30, 450), a: trazado)), 30, accuracy: 0.5)
        // Antes del principio: distancia al primer punto
        XCTAssertEqual(try XCTUnwrap(Simplificar.distancia(de: punto(0, -40), a: trazado)), 40, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(Simplificar.distancia(de: punto(30, 40), a: [punto(0, 0)])), 50, accuracy: 0.5)
        XCTAssertNil(Simplificar.distancia(de: punto(0, 0), a: []))
    }

    func testDistanciaASegmento() {
        XCTAssertEqual(Simplificar.distanciaASegmento((x: 5, y: 3), (x: 0, y: 0), (x: 10, y: 0)), 3, accuracy: 1e-9)
        // Más allá del extremo: distancia al extremo, no a la recta
        XCTAssertEqual(Simplificar.distanciaASegmento((x: 13, y: 4), (x: 0, y: 0), (x: 10, y: 0)), 5, accuracy: 1e-9)
    }
}
