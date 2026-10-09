import Foundation
import XCTest
@testable import LPRCore

// Geometrías sintéticas con coordenadas inventadas (base 40,0 N 3,0 O), en
// metros respecto a esa base.
final class CurvasTests: XCTestCase {
    private let base = PuntoRuta(latitud: 40.0, longitud: -3.0)

    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: base.latitud + y / 111_320,
            longitud: base.longitud + x / (111_320 * cos(base.latitud * .pi / 180))
        )
    }

    /// Recta hacia el norte de `desde` a `hasta` metros, en la x dada.
    private func recta(x: Double, desde: Double, hasta: Double) -> [PuntoRuta] {
        stride(from: desde, through: hasta, by: 50).map { punto(x, $0) }
    }

    /// Arco de `grados` con centro (cx, cy) y radio `r`, desde el ángulo
    /// `inicio` (radianes, medido como en trigonometría).
    private func arco(cx: Double, cy: Double, r: Double, inicio: Double, grados: Double) -> [PuntoRuta] {
        let pasos = Int(abs(grados) / 5)
        return (0...pasos).map { i in
            let angulo = inicio + Double(i) * (grados / Double(pasos)) * .pi / 180
            return punto(cx + r * cos(angulo), cy + r * sin(angulo))
        }
    }

    func testRectaSinCurvas() {
        let resultado = Curvas.medir(tramos: [recta(x: 0, desde: 0, hasta: 2000)])
        XCTAssertEqual(resultado.curvas, 0)
        XCTAssertEqual(resultado.gradosPorKm, 0, accuracy: 0.001)
        XCTAssertEqual(resultado.metros, 2000, accuracy: 5)
    }

    func testUnaCurvaDeNoventaGrados() {
        // Hacia el norte, curva a la derecha de 90° (radio 100 m) y hacia el este
        let entrada = recta(x: 0, desde: -300, hasta: 0)
        let curva = arco(cx: 100, cy: 0, r: 100, inicio: .pi, grados: -90)
        let salida = (1...6).map { punto(100 + Double($0) * 50, 100) }
        let resultado = Curvas.medir(tramos: [entrada + curva + salida])
        XCTAssertEqual(resultado.curvas, 1)
    }

    func testEseSonDosCurvas() {
        // Derecha 90° y luego izquierda 90°
        let entrada = recta(x: 0, desde: -300, hasta: 0)
        let derecha = arco(cx: 100, cy: 0, r: 100, inicio: .pi, grados: -90)
        let recto = (1...4).map { punto(100 + Double($0) * 50, 100) }
        let izquierda = arco(cx: 300, cy: 200, r: 100, inicio: -.pi / 2, grados: 90)
        let salida = (1...6).map { punto(400, 200 + Double($0) * 50) }
        let resultado = Curvas.medir(tramos: [entrada + derecha + recto + izquierda + salida])
        XCTAssertEqual(resultado.curvas, 2)
    }

    func testRuidoLateralNoCuenta() {
        // Recta con un zigzag de ±0,3 m cada 25 m: cambios de rumbo de menos de 4°
        let puntos = (0...80).map { i in punto(i % 2 == 0 ? 0.3 : -0.3, Double(i) * 25) }
        XCTAssertEqual(Curvas.medir(tramos: [puntos]).curvas, 0)
    }

    func testGiroEnCruceNoCuenta() {
        // Dos tramos rectos perpendiculares: el giro es una maniobra, no una curva
        let norte = recta(x: 0, desde: 0, hasta: 1000)
        let este = (0...20).map { punto(Double($0) * 50, 1000) }
        XCTAssertEqual(Curvas.medir(tramos: [norte, este]).curvas, 0)
    }

    private func candidata(_ minutos: Double, curvas: Int, gradosPorKm: Double = 0) -> Candidata {
        Candidata(
            segundos: minutos * 60,
            sinuosidad: Sinuosidad(curvas: curvas, gradosPorKm: gradosPorKm, metros: 0)
        )
    }

    func testElegirSinCandidatas() {
        XCTAssertNil(Curvas.elegir([]))
    }

    func testElegirRapidaYDivertidaDentroDelMargen() {
        let candidatas = [
            candidata(70, curvas: 40),
            candidata(60, curvas: 10),
            candidata(74, curvas: 90),   // +23 %: dentro
            candidata(80, curvas: 200),  // +33 %: fuera
        ]
        let eleccion = Curvas.elegir(candidatas, margen: 0.25)
        XCTAssertEqual(eleccion?.rapida, 1)
        XCTAssertEqual(eleccion?.divertida, 2)
    }

    func testDivertidaPuedeSerLaRapida() {
        let candidatas = [candidata(60, curvas: 50), candidata(65, curvas: 20)]
        let eleccion = Curvas.elegir(candidatas, margen: 0.25)
        XCTAssertEqual(eleccion?.rapida, 0)
        XCTAssertEqual(eleccion?.divertida, 0)
    }

    func testEmpateDeCurvasPorGradosYTiempo() {
        let candidatas = [
            candidata(60, curvas: 5, gradosPorKm: 10),
            candidata(70, curvas: 30, gradosPorKm: 40),
            candidata(65, curvas: 30, gradosPorKm: 40),
            candidata(66, curvas: 30, gradosPorKm: 20),
        ]
        XCTAssertEqual(Curvas.elegir(candidatas, margen: 0.25)?.divertida, 2)
    }

    func testNormalizarRumbo() {
        XCTAssertEqual(Curvas.normalizar(350), -10, accuracy: 0.001)
        XCTAssertEqual(Curvas.normalizar(-350), 10, accuracy: 0.001)
        XCTAssertEqual(Curvas.normalizar(90), 90, accuracy: 0.001)
    }
}
