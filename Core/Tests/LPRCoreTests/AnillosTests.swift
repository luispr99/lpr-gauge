import Foundation
import XCTest
@testable import LPRCore

// Anillos de rotondas inventadas (base 40,0 N 3,0 O, como CrucesTests), en
// metros respecto a esa base: x hacia el este, y hacia el norte.
final class AnillosTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    /// Puntos de un arco, en metros, de `desde` a `hasta` grados (sentido
    /// contrario a las agujas del reloj, desde el este) cada `paso`. Con
    /// `ruido`, cada punto se aleja y se acerca al centro por turnos.
    private func arco(centro: (x: Double, y: Double), radio: Double, desde: Double, hasta: Double, paso: Double,
                      ruido: Double = 0) -> [PuntoPlano] {
        stride(from: desde, through: hasta, by: paso).enumerated().map { elemento -> PuntoPlano in
            let r = radio + (elemento.offset % 2 == 0 ? -ruido : ruido)
            let grados = elemento.element
            return PuntoPlano(x: centro.x + r * cos(grados * .pi / 180), y: centro.y + r * sin(grados * .pi / 180))
        }
    }

    /// El mismo arco en grados, con `cuantos` puntos, centrado en la base.
    private func arcoEnGrados(radio: Double, desde: Double, hasta: Double, cuantos: Int) -> [PuntoRuta] {
        (0..<cuantos).map { i -> PuntoRuta in
            let grados = desde + (hasta - desde) * Double(i) / Double(cuantos - 1)
            return punto(radio * cos(grados * .pi / 180), radio * sin(grados * .pi / 180))
        }
    }

    // MARK: Ajuste del círculo

    func testAjusteDeUnArcoExacto() throws {
        // 120° de un círculo de 20 m con el centro en (3, -4)
        let puntos = arco(centro: (3, -4), radio: 20, desde: 0, hasta: 120, paso: 10)
        let circulo = try XCTUnwrap(AjusteCirculo.ajustar(puntos))
        XCTAssertEqual(circulo.x, 3, accuracy: 1e-6)
        XCTAssertEqual(circulo.y, -4, accuracy: 1e-6)
        XCTAssertEqual(circulo.radio, 20, accuracy: 1e-6)
        XCTAssertEqual(circulo.error, 0, accuracy: 1e-6)
        XCTAssertEqual(AjusteCirculo.giro(puntos, centro: PuntoPlano(x: circulo.x, y: circulo.y)), 120, accuracy: 1e-6)
        // Al revés, el giro cambia de signo
        XCTAssertEqual(AjusteCirculo.giro(puntos.reversed(), centro: PuntoPlano(x: 3, y: -4)), -120, accuracy: 1e-6)
    }

    func testAjusteConRuido() throws {
        // ±3 cm por turnos: el círculo apenas se mueve y el error queda por
        // debajo de los 7 cm de la regla
        let puntos = arco(centro: (3, -4), radio: 20, desde: 0, hasta: 120, paso: 10, ruido: 0.03)
        let circulo = try XCTUnwrap(AjusteCirculo.ajustar(puntos))
        XCTAssertEqual(circulo.x, 3, accuracy: 0.1)
        XCTAssertEqual(circulo.y, -4, accuracy: 0.1)
        XCTAssertEqual(circulo.radio, 20, accuracy: 0.1)
        XCTAssertLessThan(circulo.error, Anillo.maximoError)
        XCTAssertGreaterThan(circulo.error, 0.01)
    }

    func testAjusteSinCirculo() {
        // Menos de 3 puntos o en línea recta: no hay círculo
        XCTAssertNil(AjusteCirculo.ajustar([PuntoPlano(x: 0, y: 0), PuntoPlano(x: 1, y: 1)]))
        XCTAssertNil(AjusteCirculo.ajustar((0..<6).map { PuntoPlano(x: Double($0) * 10, y: Double($0) * 5) }))
        XCTAssertNil(AjusteCirculo.ajustar([]))
    }

    func testResolver3() throws {
        // x + y + z = 6, 2y + 5z = -4, 2x + 5y - z = 27: (5, 3, -2)
        let solucion = try XCTUnwrap(AjusteCirculo.resolver3([[1, 1, 1], [0, 2, 5], [2, 5, -1]], [6, -4, 27]))
        XCTAssertEqual(solucion[0], 5, accuracy: 1e-9)
        XCTAssertEqual(solucion[1], 3, accuracy: 1e-9)
        XCTAssertEqual(solucion[2], -2, accuracy: 1e-9)
        XCTAssertNil(AjusteCirculo.resolver3([[1, 2, 3], [2, 4, 6], [0, 0, 1]], [1, 2, 3]))
        XCTAssertNil(AjusteCirculo.resolver3([[1, 2]], [1]))
    }

    // MARK: Regla de aceptación

    func testAnilloAceptado() throws {
        // Un cuarto de rotonda de 20 m, en 10 puntos con 6 decimales (como
        // llegan en el trazado)
        let puntos = arcoEnGrados(radio: 20, desde: -90, hasta: 0, cuantos: 10)
            .map { PuntoRuta(latitud: ($0.latitud * 1e6).rounded() / 1e6, longitud: ($0.longitud * 1e6).rounded() / 1e6) }
        let anillo = try XCTUnwrap(Anillo.ajustar(arco: puntos, recorridoEntrada: 1_000, recorridoSalida: 1_031))
        XCTAssertEqual(Trazo.distancia(anillo.centro, punto(0, 0)), 0, accuracy: 0.15)
        XCTAssertEqual(anillo.radio, 20, accuracy: 0.15)
        XCTAssertEqual(anillo.recorridoEntrada, 1_000)
        XCTAssertEqual(anillo.recorridoSalida, 1_031)
    }

    func testAnilloRechazado() {
        // Pocos puntos (4)
        XCTAssertNil(Anillo.ajustar(arco: arcoEnGrados(radio: 20, desde: -90, hasta: 0, cuantos: 4),
                                    recorridoEntrada: 0, recorridoSalida: 31))
        // Poco giro (30°)
        XCTAssertNil(Anillo.ajustar(arco: arcoEnGrados(radio: 20, desde: 0, hasta: 30, cuantos: 8),
                                    recorridoEntrada: 0, recorridoSalida: 10))
        // Radio fuera de 5-80 m
        XCTAssertNil(Anillo.ajustar(arco: arcoEnGrados(radio: 100, desde: 0, hasta: 90, cuantos: 10),
                                    recorridoEntrada: 0, recorridoSalida: 157))
        XCTAssertNil(Anillo.ajustar(arco: arcoEnGrados(radio: 4, desde: 0, hasta: 180, cuantos: 10),
                                    recorridoEntrada: 0, recorridoSalida: 13))
        // Un óvalo de 25 por 15 m: el círculo se aleja más de 7 cm de los puntos
        let ovalo = stride(from: 0.0, through: 180, by: 10).map { grados in
            punto(25 * cos(grados * .pi / 180), 15 * sin(grados * .pi / 180))
        }
        XCTAssertNil(Anillo.ajustar(arco: ovalo, recorridoEntrada: 0, recorridoSalida: 64))
        // Un radio de 30 m sí vale
        XCTAssertNotNil(Anillo.ajustar(arco: arcoEnGrados(radio: 30, desde: 0, hasta: 90, cuantos: 10),
                                       recorridoEntrada: 0, recorridoSalida: 47))
    }

    // MARK: Calles de las rotondas con anillo

    /// Una rotonda de 20 m con el centro en la base, recorrida en sentido
    /// contrario a las agujas del reloj de sur a norte por el este:
    /// - la entrada, al sur, con el anillo que llega del oeste (277,5°, sin
    ///   entrada);
    /// - un brazo con isleta al este: su calzada de salida (80°, de entrar)
    ///   a -10° y la de llegada (100°, sin entrada) a 10°, que se cortan a
    ///   unos 20 m por fuera;
    /// - un brazo de una calzada a 60° (30°);
    /// - la salida, al norte, con el anillo que sigue hacia el oeste (262,5°);
    /// - y, pasada la rotonda, un cruce que no es suyo.
    private func crucesDeLaRotonda(entradaDelBrazo: Bool? = false) -> [Cruce] {
        func enAnillo(_ grados: Double) -> PuntoRuta {
            punto(20 * cos(grados * .pi / 180), 20 * sin(grados * .pi / 180))
        }
        return [
            Cruce(punto: enAnillo(-90), rumbos: [277.5], recorrido: 100, entradas: [false], anillo: 0),
            Cruce(punto: enAnillo(-10), rumbos: [80], recorrido: 110, entradas: [true], anillo: 0),
            Cruce(punto: enAnillo(10), rumbos: [100], recorrido: 120, entradas: [entradaDelBrazo], anillo: 0),
            Cruce(punto: enAnillo(60), rumbos: [30], recorrido: 130, entradas: [true], anillo: 0),
            Cruce(punto: enAnillo(90), rumbos: [262.5], recorrido: 140, entradas: [true], anillo: 0),
            Cruce(punto: punto(0, 60), rumbos: [90], recorrido: 180),
        ]
    }

    private let anillo = Anillo(centro: PuntoRuta(latitud: 40, longitud: -3), radio: 20,
                                recorridoEntrada: 100, recorridoSalida: 140)

    func testCallesDeLaRotondaConAnillo() throws {
        let cruces = crucesDeLaRotonda()
        let conAnillos = Cruces.conAnillos(cruces, anillos: [anillo])
        // Fuera el anillo de la entrada y el de la salida; el brazo con isleta
        // queda en una calle, en el anillo, a medio camino (al este) y hacia
        // el este, detrás del primer cruce del brazo; los demás, igual
        XCTAssertEqual(conAnillos.count, 3)
        let brazo = conAnillos[0]
        XCTAssertEqual(Trazo.distancia(brazo.punto, punto(20, 0)), 0, accuracy: 0.01)
        XCTAssertEqual(brazo.rumbos.count, 1)
        XCTAssertEqual(try XCTUnwrap(brazo.rumbos.first), 90, accuracy: 1e-6)
        XCTAssertEqual(brazo.entradas, [true])
        XCTAssertEqual(brazo.recorrido, 110)
        XCTAssertEqual(brazo.anillo, 0)
        XCTAssertEqual(conAnillos[1], cruces[3])
        XCTAssertEqual(conAnillos[2], cruces[5])
    }

    func testCallesDeLaRotondaSinIsleta() {
        // Si las dos calzadas son de entrar, no es un brazo con isleta: se
        // quedan las dos (solo se quita el anillo)
        let cruces = crucesDeLaRotonda(entradaDelBrazo: true)
        let conAnillos = Cruces.conAnillos(cruces, anillos: [anillo])
        XCTAssertEqual(conAnillos, [cruces[1], cruces[2], cruces[3], cruces[5]])
    }

    func testCallesDeLaRotondaSinAnillo() {
        // Sin anillos, o con un índice que no está, nada cambia
        let cruces = crucesDeLaRotonda()
        XCTAssertEqual(Cruces.conAnillos(cruces, anillos: []), cruces)
        let otroIndice = cruces.map { cruce -> Cruce in
            var copia = cruce
            copia.anillo = cruce.anillo.map { $0 + 1 }
            return copia
        }
        XCTAssertEqual(Cruces.conAnillos(otroIndice, anillos: [anillo]), otroIndice)
        // RutaConCruces los calcula al crearse
        let ruta = RutaConCruces(puntos: [punto(0, -100), punto(0, 100)], cruces: cruces, anillos: [anillo])
        XCTAssertEqual(ruta.cruces, cruces)
        XCTAssertEqual(ruta.crucesConAnillos, Cruces.conAnillos(cruces, anillos: [anillo]))
    }

    func testRumboMedio() {
        XCTAssertEqual(Cruces.rumboMedio(80, 100), 90, accuracy: 1e-9)
        XCTAssertEqual(Cruces.rumboMedio(350, 30), 10, accuracy: 1e-9)
        XCTAssertEqual(Cruces.rumbo(de: PuntoPlano(x: -1, y: 0)), 270, accuracy: 1e-9)
    }

    // MARK: Anillos del tramo

    func testAnillosDelTramo() {
        // Tramo hacia el norte desde la base, ventana de 500 a 800 m de la ruta
        let ruta = [punto(0, 0), punto(0, 300)]
        let anillos = [
            // Delante, a 200 m
            Anillo(centro: punto(30, 200), radio: 15, recorridoEntrada: 600, recorridoSalida: 650),
            // Recién pasado: su salida, a 15 m por detrás de la ventana
            Anillo(centro: punto(0, -20), radio: 10.4, recorridoEntrada: 450, recorridoSalida: 485),
            // Pasado hace más
            Anillo(centro: punto(0, -60), radio: 12, recorridoEntrada: 300, recorridoSalida: 470),
            // Más allá del tramo
            Anillo(centro: punto(0, 500), radio: 12, recorridoEntrada: 900, recorridoSalida: 950),
        ]
        let elegidos = Cruces.anillos(de: anillos, ruta: ruta, sentido: 0, ventana: 500...800)
        XCTAssertEqual(elegidos.count, 2)
        // En el orden de la ruta
        XCTAssertEqual(elegidos[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(elegidos[0].y, -20, accuracy: 0.01)
        XCTAssertEqual(elegidos[0].radio, 10.4)
        XCTAssertEqual(elegidos[1].x, 30, accuracy: 0.01)
        XCTAssertEqual(elegidos[1].y, 200, accuracy: 0.01)
        XCTAssertEqual(elegidos[1].radio, 15)
    }

    func testAnillosEnLosEjesDeLaMoto() {
        // Hacia el este: un anillo 200 m al este y 30 al sur queda delante y a
        // la derecha
        let elegidos = Cruces.anillos(
            de: [Anillo(centro: punto(200, -30), radio: 15, recorridoEntrada: 200, recorridoSalida: 250)],
            ruta: [punto(0, 0), punto(300, 0)], sentido: 90, ventana: 0...300)
        XCTAssertEqual(elegidos.count, 1)
        XCTAssertEqual(elegidos.first?.x ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(elegidos.first?.y ?? 0, 200, accuracy: 0.01)
    }

    func testAnillosComoMuchoCuatro() {
        // Seis en la ventana: los cuatro primeros por la ruta (el radio dice
        // cuál es cuál)
        let entradas: [Double] = [700, 600, 650, 520, 510, 790]
        let anillos = entradas.map {
            Anillo(centro: punto(0, $0 - 500), radio: $0 / 10, recorridoEntrada: $0, recorridoSalida: $0 + 30)
        }
        let ruta = [punto(0, 0), punto(0, 300)]
        XCTAssertEqual(Cruces.anillos(de: anillos, ruta: ruta, sentido: 0, ventana: 500...800).map(\.radio),
                       [51, 52, 60, 65])
        XCTAssertEqual(Cruces.anillos(de: anillos, ruta: ruta, sentido: 0, ventana: 500...800, maximo: 1).map(\.radio),
                       [51])
        XCTAssertEqual(Cruces.anillos(de: anillos, ruta: [], sentido: 0, ventana: 500...800), [])
        XCTAssertEqual(Cruces.anillos(de: [], ruta: ruta, sentido: 0, ventana: 500...800), [])
    }
}
