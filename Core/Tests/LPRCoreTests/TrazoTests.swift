import Foundation
import XCTest
@testable import LPRCore

// Rutas sintéticas con coordenadas inventadas (base 40,0 N 3,0 O), en metros
// respecto a esa base: x hacia el este, y hacia el norte.
final class TrazoTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    func testRumbo() {
        XCTAssertEqual(Trazo.rumbo(de: punto(0, 0), a: punto(0, 100)), 0, accuracy: 0.1)
        XCTAssertEqual(Trazo.rumbo(de: punto(0, 0), a: punto(100, 0)), 90, accuracy: 0.1)
        XCTAssertEqual(Trazo.rumbo(de: punto(0, 0), a: punto(0, -100)), 180, accuracy: 0.1)
        XCTAssertEqual(Trazo.rumbo(de: punto(0, 0), a: punto(-100, 0)), 270, accuracy: 0.1)
    }

    func testRecorrerCortaEnLosMetros() {
        // Un paso hacia el norte con puntos cada 100 m; la moto en el primer segmento
        let paso = (0...5).map { punto(0, Double($0) * 100) }
        let ruta = Trazo.recorrer(pasos: [paso], indice: 0, desde: punto(0, 20), metros: 150)
        XCTAssertEqual(ruta.count, 3)                 // origen, el de 100 m y el cortado
        XCTAssertEqual(Trazo.distancia(ruta.last!, punto(0, 170)), 0, accuracy: 0.5)
    }

    func testRecorrerPasaAlPasoSiguienteSinRepetir() {
        // Dos pasos que comparten el vértice (0, 200): norte y luego este
        let norte = (0...2).map { punto(0, Double($0) * 100) }
        let este = (0...3).map { punto(Double($0) * 100, 200) }
        let ruta = Trazo.recorrer(pasos: [norte, este], indice: 1, desde: punto(0, 150), metros: 1_000)
        // origen, (0,200), (100,200), (200,200), (300,200): el vértice compartido, una vez
        XCTAssertEqual(ruta.count, 5)
        XCTAssertEqual(Trazo.distancia(ruta[1], punto(0, 200)), 0, accuracy: 0.5)
        XCTAssertEqual(Trazo.distancia(ruta[2], punto(100, 200)), 0, accuracy: 0.5)
    }

    func testRecorrerSinIndiceEmpiezaEnElPasoSiguiente() {
        let primero = [punto(0, 0)]
        let segundo = [punto(0, 0), punto(0, 100)]
        let ruta = Trazo.recorrer(pasos: [primero, segundo], indice: nil, desde: punto(0, 0), metros: 500)
        XCTAssertEqual(ruta.count, 2)
    }

    func testEjesDeLaMoto() {
        // Rumbo 90 (hacia el este): lo del este queda delante y lo del norte, a la izquierda
        let ejes = Trazo.aEjesMoto([punto(100, 0), punto(0, 100)], origen: punto(0, 0), rumbo: 90)
        XCTAssertEqual(ejes[0].x, 0, accuracy: 0.5)
        XCTAssertEqual(ejes[0].y, 100, accuracy: 0.5)
        XCTAssertEqual(ejes[1].x, -100, accuracy: 0.5)
        XCTAssertEqual(ejes[1].y, 0, accuracy: 0.5)
    }

    func testTramoConGiro() {
        // Hacia el norte 300 m y giro a la derecha (este)
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let este = (0...4).map { punto(Double($0) * 100, 300) }
        let resultado = Trazo.tramo(pasos: [norte, este], indice: 0, desde: punto(0, 50),
                                    metros: 500, giro: punto(0, 300))
        let tramo = try! XCTUnwrap(resultado)
        // Simplificado: la moto, el giro y el final (250 m después del giro)
        XCTAssertEqual(tramo.puntos.count, 3)
        XCTAssertEqual(tramo.puntos[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(tramo.puntos[0].y, 0, accuracy: 0.01)
        // El giro, 250 m delante; el final, 250 m a la derecha de él
        XCTAssertEqual(tramo.giro, 1)
        XCTAssertEqual(tramo.puntos[1].x, 0, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].y, 250, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[2].x, 250, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[2].y, 250, accuracy: 0.5)
    }

    func testTramoCabeEnElMaximo() {
        // Zigzag de muchos puntos: se simplifica hasta que quepan
        let zigzag = (0...200).map { punto($0 % 2 == 0 ? -20 : 20, Double($0) * 10) }
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [zigzag], indice: 0, desde: punto(0, 5),
                                               metros: 1_500, giro: nil, maximoPuntos: 10))
        XCTAssertLessThanOrEqual(tramo.puntos.count, 10)
        XCTAssertGreaterThanOrEqual(tramo.puntos.count, 2)
        XCTAssertNil(tramo.giro)
    }

    func testTramoCercaDelGiroNoRota() {
        // A 10 m de un giro de 90° a la derecha: el giro sigue recto delante y
        // la salida, a la derecha (antes, la cuerda de 25 m cruzaba el giro y
        // el dibujo rotaba hacia la salida; revisión de la 0.9.0)
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let este = (0...4).map { punto(Double($0) * 100, 300) }
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [norte, este], indice: 2, desde: punto(0, 290),
                                               metros: 300, giro: punto(0, 300)))
        XCTAssertEqual(tramo.giro, 1)
        XCTAssertEqual(tramo.puntos[1].x, 0, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].y, 10, accuracy: 0.5)
        XCTAssertGreaterThan(tramo.puntos.last!.x, 250)
        XCTAssertEqual(tramo.puntos.last!.y, 10, accuracy: 0.5)
        // A 1 m: el rumbo del último segmento del paso
        let pegado = try! XCTUnwrap(Trazo.tramo(pasos: [norte, este], indice: 2, desde: punto(0, 299),
                                                metros: 300, giro: punto(0, 300)))
        XCTAssertEqual(pegado.puntos.last!.y, 1, accuracy: 0.5)
        XCTAssertGreaterThan(pegado.puntos.last!.x, 250)
        XCTAssertEqual(pegado.giro, 1)
    }

    func testTramoConservaUnGiroSuave() {
        // Salida de 3° a la derecha con la moto a 40 m: el vértice está a menos
        // de 2 m de la cuerda y Douglas-Peucker lo quitaría (revisión de la 0.9.1)
        let norte = [punto(0, 0), punto(0, 500), punto(0, 1000)]
        let rad = 3.0 * .pi / 180
        let salida = (0...2).map { punto(Double($0) * 500 * sin(rad), 1000 + Double($0) * 500 * cos(rad)) }
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [norte, salida], indice: 1, desde: punto(0, 960),
                                               metros: 250, giro: punto(0, 1000)))
        XCTAssertEqual(tramo.giro, 1)
        XCTAssertEqual(tramo.puntos[1].x, 0, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].y, 40, accuracy: 0.5)
    }

    func testPasosNecesariosCuentaLoQueQuedaDelActual() {
        // Paso actual de 2000 m con 300 por delante: hace falta el siguiente
        // para ver la salida del giro (revisión de la 0.9.0)
        XCTAssertEqual(Trazo.pasosNecesarios(distancias: [2000, 500, 800], restanteEnActual: 300, metros: 450), 2)
        XCTAssertEqual(Trazo.pasosNecesarios(distancias: [2000, 500, 800], restanteEnActual: 1500, metros: 1000), 1)
        XCTAssertEqual(Trazo.pasosNecesarios(distancias: [100, 50, 60], restanteEnActual: 80, metros: 1000), 3)
        XCTAssertEqual(Trazo.pasosNecesarios(distancias: [], restanteEnActual: 0, metros: 500), 0)
    }

    func testSinRutaPorDelante() {
        XCTAssertNil(Trazo.tramo(pasos: [], indice: nil, desde: punto(0, 0), metros: 500, giro: nil))
    }
}
