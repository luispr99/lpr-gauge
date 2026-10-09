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
        // Para los cruces: la ruta sin simplificar desde la moto (origen, los
        // tres vértices hacia el norte, dos hacia el este y el corte) y el
        // sentido de la marcha (norte)
        XCTAssertEqual(tramo.ruta.count, 7)
        XCTAssertEqual(tramo.ruta.first, punto(0, 50))
        XCTAssertEqual(tramo.sentido, 0, accuracy: 0.1)
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

    // MARK: Escala por niveles (v0.6)

    func testNivelSegunLaDistancia() {
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 1_200, anterior: nil), 3)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 500.1, anterior: nil), 3)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 500, anterior: nil), 2)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 200, anterior: nil), 2)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 199.9, anterior: nil), 1)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 0, anterior: nil), 1)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: .nan, anterior: nil), 3)
    }

    func testNivelSoloBajaEnLaMismaManiobra() {
        // Acercándose a un giro: dos saltos, y el GPS que hace crecer un poco
        // la distancia no lo hace subir
        var nivel: Int? = nil
        var niveles: [Int] = []
        for metros in [1_500.0, 600, 499, 510, 230, 199, 230, 5] {
            let nuevo = Trazo.nivel(metrosAlGiro: metros, anterior: nivel)
            niveles.append(nuevo)
            nivel = nuevo
        }
        XCTAssertEqual(niveles, [3, 3, 2, 2, 2, 1, 1, 1])
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 800, anterior: 2), 2)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 450, anterior: 3), 2)
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: .nan, anterior: 2), 2)
        // Con la maniobra siguiente (anterior nil) se elige de nuevo
        XCTAssertEqual(Trazo.nivel(metrosAlGiro: 2_000, anterior: nil), 3)
    }

    func testMetrosDeCadaNivel() {
        XCTAssertEqual(Trazo.metros(nivel: 1), 250)
        XCTAssertEqual(Trazo.metros(nivel: 2), 500)
        XCTAssertEqual(Trazo.metros(nivel: 3), 1_000)
        // Se mandan 1,25 veces, para que el tramo llegue hasta arriba
        XCTAssertEqual(Trazo.metrosTramo(nivel: 1), 312.5)
        XCTAssertEqual(Trazo.metrosTramo(nivel: 3), 1_250)
        // Con movimiento (v0.9), 100 m más
        XCTAssertEqual(Trazo.metrosTramoConMovimiento(nivel: 1), 412.5)
        XCTAssertEqual(Trazo.metrosTramoConMovimiento(nivel: 3), 1_350)
    }

    // MARK: Con movimiento (v0.9)

    func testRecorrerAtrasCortaEnLosMetros() {
        // Un paso hacia el norte con puntos cada 100 m; la moto en el segundo segmento
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let atras = Trazo.recorrerAtras(anteriores: [], actual: norte, indice: 1, desde: punto(0, 150), metros: 80)
        // El de 100 m y el cortado en 70 m
        XCTAssertEqual(atras.count, 2)
        XCTAssertEqual(Trazo.distancia(atras[0], punto(0, 100)), 0, accuracy: 0.5)
        XCTAssertEqual(Trazo.distancia(atras[1], punto(0, 70)), 0, accuracy: 0.5)
        // Al principio de la ruta, hasta donde empieza
        let todo = Trazo.recorrerAtras(anteriores: [], actual: norte, indice: 1, desde: punto(0, 150), metros: 1_000)
        XCTAssertEqual(todo.count, 2)
        XCTAssertEqual(Trazo.distancia(todo[1], punto(0, 0)), 0, accuracy: 0.5)
        XCTAssertEqual(Trazo.recorrerAtras(anteriores: [], actual: norte, indice: 1, desde: punto(0, 150), metros: 0),
                       [])
    }

    func testRecorrerAtrasPasaAlPasoAnteriorSinRepetir() {
        // El paso anterior va hacia el este y acaba en (0, 0), donde empieza el
        // actual, hacia el norte
        let este = (0...3).map { punto(Double($0 - 3) * 100, 0) }
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let atras = Trazo.recorrerAtras(anteriores: [este], actual: norte, indice: 1, desde: punto(0, 150),
                                        metros: 200)
        // (0, 100), (0, 0) una sola vez y el cortado en (-50, 0)
        XCTAssertEqual(atras.count, 3)
        XCTAssertEqual(Trazo.distancia(atras[1], punto(0, 0)), 0, accuracy: 0.5)
        XCTAssertEqual(Trazo.distancia(atras[2], punto(-50, 0)), 0, accuracy: 0.5)
        // Sin índice: el paso actual no sirve y se sigue por el anterior
        let sinIndice = Trazo.recorrerAtras(anteriores: [este], actual: norte, indice: nil, desde: punto(0, 20),
                                            metros: 70)
        XCTAssertEqual(sinIndice.count, 2)
        XCTAssertEqual(Trazo.distancia(sinIndice[0], punto(0, 0)), 0, accuracy: 0.5)
        XCTAssertEqual(Trazo.distancia(sinIndice[1], punto(-50, 0)), 0, accuracy: 0.5)
    }

    func testTramoConMovimiento() {
        // Como testTramoConGiro, con la ruta hecha: el paso anterior, hacia el
        // este, acaba donde empieza el actual
        let este = (0...3).map { punto(Double($0 - 3) * 100, 0) }
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let salida = (0...4).map { punto(Double($0) * 100, 300) }
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [norte, salida], indice: 0, desde: punto(0, 50),
                                               metros: 500, giro: punto(0, 300), anteriores: [este]))
        // 150 m por detrás: la esquina (0, 0) y el corte en (-100, 0); del más
        // lejano al más cercano, y después la moto, el giro y el final
        XCTAssertEqual(tramo.atras, 2)
        XCTAssertEqual(tramo.puntos.count, 5)
        XCTAssertEqual(tramo.puntos[0].x, -100, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[0].y, -50, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].x, 0, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].y, -50, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[2].x, 0, accuracy: 0.01)
        XCTAssertEqual(tramo.puntos[2].y, 0, accuracy: 0.01)
        // El giro cuenta los de detrás
        XCTAssertEqual(tramo.giro, 3)
        XCTAssertEqual(tramo.puntos[3].y, 250, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[4].x, 250, accuracy: 0.5)
        // Los cruces, como siempre: la ruta desde la moto y el mismo sentido
        XCTAssertEqual(tramo.ruta.count, 7)
        XCTAssertEqual(tramo.ruta.first, punto(0, 50))
        XCTAssertEqual(tramo.sentido, 0, accuracy: 0.1)
        // Sin movimiento, nada detrás
        let sinMovimiento = try! XCTUnwrap(Trazo.tramo(pasos: [norte, salida], indice: 0, desde: punto(0, 50),
                                             metros: 500, giro: punto(0, 300)))
        XCTAssertEqual(sinMovimiento.atras, 0)
        XCTAssertEqual(sinMovimiento.giro, 1)
        XCTAssertEqual(sinMovimiento.puntos.count, 3)
    }

    func testTramoConMovimientoDejaPrimeroLosDeDelante() {
        let este = (0...3).map { punto(Double($0 - 3) * 100, 0) }
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let salida = (0...4).map { punto(Double($0) * 100, 300) }
        // Con sitio para 4: los 3 de delante y uno detrás, más simplificado (la
        // esquina se va y queda el corte)
        let cuatro = try! XCTUnwrap(Trazo.tramo(pasos: [norte, salida], indice: 0, desde: punto(0, 50),
                                                metros: 500, giro: punto(0, 300), maximoPuntos: 4,
                                                anteriores: [este]))
        XCTAssertEqual(cuatro.atras, 1)
        XCTAssertEqual(cuatro.puntos.count, 4)
        XCTAssertEqual(cuatro.puntos[0].x, -100, accuracy: 0.5)
        XCTAssertEqual(cuatro.puntos[0].y, -50, accuracy: 0.5)
        XCTAssertEqual(cuatro.giro, 2)
        // Con sitio para 3: ninguno detrás
        let tres = try! XCTUnwrap(Trazo.tramo(pasos: [norte, salida], indice: 0, desde: punto(0, 50),
                                              metros: 500, giro: punto(0, 300), maximoPuntos: 3,
                                              anteriores: [este]))
        XCTAssertEqual(tres.atras, 0)
        XCTAssertEqual(tres.puntos.count, 3)
        XCTAssertEqual(tres.giro, 1)
    }

    func testTramoConMovimientoAlEmpezarLaRuta() {
        // Sin pasos hechos: solo el trozo del paso actual antes de la moto
        let norte = (0...3).map { punto(0, Double($0) * 100) }
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [norte], indice: 0, desde: punto(0, 50), metros: 200,
                                               giro: nil, anteriores: []))
        XCTAssertEqual(tramo.atras, 1)
        XCTAssertEqual(tramo.puntos[0].x, 0, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[0].y, -50, accuracy: 0.5)
        XCTAssertEqual(tramo.puntos[1].y, 0, accuracy: 0.01)
        // La moto justo en el inicio: nada detrás
        let alSalir = try! XCTUnwrap(Trazo.tramo(pasos: [norte], indice: 0, desde: punto(0, 0), metros: 200,
                                                 giro: nil, anteriores: []))
        XCTAssertEqual(alSalir.atras, 0)
        XCTAssertEqual(alSalir.puntos[0].y, 0, accuracy: 0.01)
    }

    func testTramoConMovimientoComoMuchoDiezDetras() {
        // Un zigzag de ±5 m cada 2 m por detrás: muchos más de 10 puntos en 150 m
        let zigzag = (0...100).map { punto($0 % 2 == 0 ? -5 : 5, -200 + Double($0) * 2) } + [punto(0, 0)]
        let norte = [punto(0, 0), punto(0, 100), punto(0, 200)]
        let tramo = try! XCTUnwrap(Trazo.tramo(pasos: [norte], indice: 0, desde: punto(0, 5), metros: 100,
                                               giro: nil, anteriores: [zigzag]))
        XCTAssertGreaterThanOrEqual(tramo.atras, 1)
        XCTAssertLessThanOrEqual(tramo.atras, MensajeTrazo.maximoAtras)
        // La moto, en el índice `atras`, y los de detrás, por detrás
        XCTAssertEqual(tramo.puntos[tramo.atras].x, 0, accuracy: 0.01)
        XCTAssertEqual(tramo.puntos[tramo.atras].y, 0, accuracy: 0.01)
        for detras in tramo.puntos.prefix(tramo.atras) {
            XCTAssertLessThan(detras.y, 0)
        }
        XCTAssertEqual(tramo.puntos.count, tramo.atras + 2)
    }
}
