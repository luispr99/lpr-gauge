import XCTest
@testable import LPRCore

final class EleccionTests: XCTestCase {
    private func candidata(
        _ minutos: Double,
        curvas: Int,
        gradosPorKm: Double = 0,
        tierra: Double = 0
    ) -> Candidata {
        Candidata(
            segundos: minutos * 60,
            sinuosidad: Sinuosidad(curvas: curvas, gradosPorKm: gradosPorKm, metros: 0),
            metrosSinAsfaltar: tierra
        )
    }

    func testSinCandidatas() {
        XCTAssertNil(Eleccion.elegir([]))
    }

    func testRapidaYDivertidaDentroDelMargen() {
        let candidatas = [
            candidata(70, curvas: 40),
            candidata(60, curvas: 10),
            candidata(74, curvas: 90),   // +23 %: dentro
            candidata(80, curvas: 200),  // +33 %: fuera
        ]
        let eleccion = Eleccion.elegir(candidatas, margen: 0.25)
        XCTAssertEqual(eleccion?.rapida, 1)
        XCTAssertEqual(eleccion?.divertida, 2)
        XCTAssertNil(eleccion?.porTierra)
    }

    func testMargenMasAmplio() {
        let candidatas = [candidata(60, curvas: 10), candidata(74, curvas: 90), candidata(150, curvas: 300)]
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 0.25)?.divertida, 1)
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 1.5)?.divertida, 2)
        // Margen 0: solo vale la más rápida
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 0)?.divertida, 0)
    }

    func testDivertidaPuedeSerLaRapida() {
        let candidatas = [candidata(60, curvas: 50), candidata(65, curvas: 20)]
        let eleccion = Eleccion.elegir(candidatas, margen: 0.25)
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
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 0.25)?.divertida, 2)
    }

    func testPorTierra() {
        let candidatas = [
            candidata(60, curvas: 10),
            candidata(70, curvas: 40, tierra: 2_000),
            candidata(72, curvas: 20, tierra: 6_000),
            candidata(90, curvas: 20, tierra: 20_000),  // +50 %: fuera con margen 0,25
        ]
        XCTAssertNil(Eleccion.elegir(candidatas, margen: 0.25, buscarTierra: false)?.porTierra)
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 0.25, buscarTierra: true)?.porTierra, 2)
        XCTAssertEqual(Eleccion.elegir(candidatas, margen: 0.5, buscarTierra: true)?.porTierra, 3)
    }

    func testRapidaYDivertidaEvitanLaTierraEnMedio() {
        var conTierra = candidata(50, curvas: 300, tierra: 3_000)
        conTierra.tierraEnMedio = true
        let candidatas = [conTierra, candidata(60, curvas: 10), candidata(70, curvas: 40)]
        let eleccion = Eleccion.elegir(candidatas, margen: 0.25, buscarTierra: true)
        XCTAssertEqual(eleccion?.rapida, 1)
        XCTAssertEqual(eleccion?.divertida, 2)
        // La de tierra sí puede ser esa, y está dentro del margen
        XCTAssertEqual(eleccion?.porTierra, 0)
        XCTAssertEqual(eleccion?.todasConTierra, false)
    }

    func testSiTodasLlevanTierraSeEligeEntreTodas() {
        var a = candidata(60, curvas: 10, tierra: 1_000)
        var b = candidata(65, curvas: 30, tierra: 1_000)
        a.tierraEnMedio = true
        b.tierraEnMedio = true
        let eleccion = Eleccion.elegir([a, b], margen: 0.25)
        XCTAssertEqual(eleccion?.rapida, 0)
        XCTAssertEqual(eleccion?.divertida, 1)
        XCTAssertEqual(eleccion?.todasConTierra, true)
    }

    func testPorTierraNecesitaUnMinimo() {
        let candidatas = [
            candidata(60, curvas: 10, tierra: 100),
            candidata(65, curvas: 10, tierra: Eleccion.minimoTierra - 1),
        ]
        XCTAssertNil(Eleccion.elegir(candidatas, margen: 0.25, buscarTierra: true)?.porTierra)
    }
}
