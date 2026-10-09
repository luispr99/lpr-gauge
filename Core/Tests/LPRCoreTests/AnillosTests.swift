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
        // RutaConCruces los calcula al crearse, con la regla 2 después: en
        // `cruces`, la calzada de llegada del brazo (100°, sin entrada, a 10 m
        // y 20° de la de salida) va con la de salida (80°, de entrar)
        let ruta = RutaConCruces(puntos: [punto(0, -100), punto(0, 100)], cruces: cruces, anillos: [anillo])
        XCTAssertEqual(ruta.cruces, [cruces[0], cruces[1], cruces[3], cruces[4], cruces[5]])
        XCTAssertEqual(ruta.cruces, Cruces.juntarDobles(en: cruces))
        XCTAssertEqual(ruta.crucesConAnillos, Cruces.juntarDobles(en: Cruces.conAnillos(cruces, anillos: [anillo])))
        XCTAssertEqual(ruta.crucesConAnillos.count, 3)
    }

    // MARK: Paso b: calles de un mismo cruce de la rotonda (0.12.1)

    func testCallesDeUnMismoCruceDeLaRotondaEnUna() throws {
        // Como en Cuatro Caminos: un cruce al suroeste del anillo (la radial
        // hacia fuera, a 240°) con dos calles a 229° y 251°: una, a 240°. Por
        // la que se puede entrar si se puede por alguna
        let angulo = 210.0 * Double.pi / 180
        let suroeste = punto(20 * cos(angulo), 20 * sin(angulo))
        let casos: [(entradas: [Bool?], esperada: Bool)] = [
            ([true, true], true), ([false, true], true), ([false, false], false),
        ]
        for caso in casos {
            let cruces = [Cruce(punto: suroeste, rumbos: [229, 251], recorrido: 100, entradas: caso.entradas,
                                anillo: 0)]
            let conAnillos = Cruces.conAnillos(cruces, anillos: [anillo])
            XCTAssertEqual(conAnillos.count, 1)
            let cruce = try XCTUnwrap(conAnillos.first)
            XCTAssertEqual(cruce.rumbos.count, 1)
            XCTAssertEqual(try XCTUnwrap(cruce.rumbos.first), 240, accuracy: 1e-6)
            XCTAssertEqual(cruce.entradas, [caso.esperada])
            XCTAssertEqual(cruce.recorrido, 100)
        }
        // A 30° o más, las dos
        let separadas = [Cruce(punto: suroeste, rumbos: [225, 255], recorrido: 100, entradas: [true, true], anillo: 0)]
        XCTAssertEqual(Cruces.conAnillos(separadas, anillos: [anillo]), separadas)
    }

    func testCallesDeUnMismoCruceAntesDeLosBrazos() throws {
        // Al este, un cruce con dos calles de salida (80° y 95°) y, 20° más
        // allá, la calzada de llegada del brazo (100°, sin entrada). Juntas
        // las dos primeras (87,5°), con la de llegada son un brazo con
        // isleta: una sola calle, en el anillo a medio camino (al este) y con
        // el rumbo medio (93,75°). Sin el paso b, la de 80° se quedaba sola
        func enAnillo(_ grados: Double) -> PuntoRuta {
            punto(20 * cos(grados * .pi / 180), 20 * sin(grados * .pi / 180))
        }
        let cruces = [
            Cruce(punto: enAnillo(-10), rumbos: [80, 95], recorrido: 110, entradas: [true, true], anillo: 0),
            Cruce(punto: enAnillo(10), rumbos: [100], recorrido: 120, entradas: [false], anillo: 0),
        ]
        let conAnillos = Cruces.conAnillos(cruces, anillos: [anillo])
        XCTAssertEqual(conAnillos.count, 1)
        let brazo = try XCTUnwrap(conAnillos.first)
        XCTAssertEqual(Trazo.distancia(brazo.punto, punto(20, 0)), 0, accuracy: 0.01)
        XCTAssertEqual(brazo.rumbos.count, 1)
        XCTAssertEqual(try XCTUnwrap(brazo.rumbos.first), 93.75, accuracy: 1e-6)
        XCTAssertEqual(brazo.entradas, [true])
        XCTAssertEqual(brazo.recorrido, 110)
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
        // Y cuáles son, en el mismo orden
        let elegidos = Cruces.anillosConIndices(de: anillos, ruta: ruta, sentido: 0, ventana: 500...800)
        XCTAssertEqual(elegidos.indices, [4, 3, 1, 2])
        XCTAssertEqual(elegidos.anillos.map(\.radio), [51, 52, 60, 65])
        XCTAssertEqual(Cruces.anillosConIndices(de: anillos, ruta: [], sentido: 0, ventana: 500...800).indices, [])
    }

    func testSinAnilloLasRotondasQueNoCaben() {
        // Cinco rotondas de 20 m hacia el norte, cada 100 m, todas en la
        // ventana. En cada una, un cruce al este con un brazo (90°) y el
        // anillo (190°, a 100° de la radial). Van 4 anillos en el mensaje: en
        // esas 4 rotondas, sin la calle del anillo; en la quinta, que se
        // dibuja sin anillo, con ella (revisión de la 0.12.0)
        let anillos = (0..<5).map { k -> Anillo in
            let y = 100 + 100 * Double(k)
            return Anillo(centro: punto(0, y), radio: 20, recorridoEntrada: y - 20, recorridoSalida: y + 20)
        }
        let cruces = (0..<5).map { k -> Cruce in
            let y = 100 + 100 * Double(k)
            return Cruce(punto: punto(20, y), rumbos: [90, 190], recorrido: y, entradas: [true, true], anillo: k)
        }
        // El tramo, hacia el norte por los cruces
        let tramo = [punto(20, 0), punto(20, 600)]
        let ruta = RutaConCruces(puntos: tramo, cruces: cruces, anillos: anillos)
        let elegidos = Cruces.anillosConIndices(de: ruta.anillos, ruta: tramo, sentido: 0, ventana: 0...600)
        XCTAssertEqual(elegidos.anillos.count, 4)
        XCTAssertEqual(elegidos.indices, [0, 1, 2, 3])
        XCTAssertEqual(ruta.crucesConAnillosSoloEn(elegidos.indices).map(\.rumbos),
                       [[90], [90], [90], [90], [90, 190]])
        // En el cuadro: 4 calles del brazo y, de la quinta, el brazo y el
        // anillo (190° respecto al norte: 135/256 de vuelta, 135,1)
        let calles = Cruces.calles(de: ruta.crucesConAnillosSoloEn(elegidos.indices), ruta: tramo, sentido: 0)
        XCTAssertEqual(calles.map(\.direccion), [64, 64, 64, 64, 64, 135])
        // Con todas, como crucesConAnillos; sin ninguna (o con índices que no
        // están), como cruces
        XCTAssertEqual(ruta.crucesConAnillos.map(\.rumbos), [[90], [90], [90], [90], [90]])
        XCTAssertEqual(ruta.crucesConAnillosSoloEn([4, 3, 2, 1, 0]), ruta.crucesConAnillos)
        XCTAssertEqual(ruta.cruces, cruces)
        XCTAssertEqual(ruta.crucesConAnillosSoloEn([]), ruta.cruces)
        XCTAssertEqual(ruta.crucesConAnillosSoloEn([7]), ruta.cruces)
        // Con otras, las suyas
        XCTAssertEqual(ruta.crucesConAnillosSoloEn([1, 4]).map(\.rumbos),
                       [[90, 190], [90], [90, 190], [90, 190], [90]])
    }
}
