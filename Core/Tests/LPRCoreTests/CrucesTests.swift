import Foundation
import XCTest
@testable import LPRCore

// Cruces con coordenadas inventadas (base 40,0 N 3,0 O), en metros respecto a
// esa base: x hacia el este, y hacia el norte.
final class CrucesTests: XCTestCase {
    private func punto(_ x: Double, _ y: Double) -> PuntoRuta {
        PuntoRuta(
            latitud: 40.0 + y / 111_320,
            longitud: -3.0 + x / (111_320 * cos(40.0 * .pi / 180))
        )
    }

    // MARK: Respuesta OSRM

    // Escrita a mano con la forma de la de Valhalla en formato OSRM. La primera
    // ruta va hacia el norte por (40,0; -3,0), (40,0009; -3,0) y (40,0018; -3,0)
    // (polyline6 «__lhkA~jbvD», «gw@?» y «gw@?»), con un cruce en medio; la
    // segunda, de un solo punto, no trae cruces.
    private let respuesta = Data(#"""
    {
      "code": "Ok",
      "routes": [
        {
          "geometry": "__lhkA~jbvDgw@?gw@?",
          "distance": 200.4,
          "duration": 20.0,
          "legs": [
            {
              "steps": [
                {
                  "intersections": [
                    { "location": [-3.0, 40.0], "bearings": [0], "entry": [true], "out": 0 },
                    { "location": [-3.0, 40.0009], "bearings": [0, 90, 180, 270],
                      "entry": [true, true, false, true], "in": 2, "out": 0, "geometry_index": 1 }
                  ]
                },
                {
                  "name": "Calle Mayor",
                  "ref": "M-510",
                  "intersections": [
                    { "location": [-3.0, 40.0018], "bearings": [180], "entry": [true], "in": 0 }
                  ]
                }
              ]
            }
          ]
        },
        {
          "geometry": "__lhkA~jbvD",
          "legs": [{ "steps": [{}] }]
        }
      ],
      "waypoints": []
    }
    """#.utf8)

    func testRespuestaOSRM() throws {
        let rutas = try RespuestaOSRM.rutas(de: respuesta)
        XCTAssertEqual(rutas.count, 2)
        // El trazado, decodificado con 6 decimales
        XCTAssertEqual(rutas[0].puntos.count, 3)
        XCTAssertEqual(rutas[0].puntos[0].latitud, 40.0, accuracy: 1e-9)
        XCTAssertEqual(rutas[0].puntos[0].longitud, -3.0, accuracy: 1e-9)
        XCTAssertEqual(rutas[0].puntos[1].latitud, 40.0009, accuracy: 1e-9)
        XCTAssertEqual(rutas[0].puntos[2].latitud, 40.0018, accuracy: 1e-9)
        XCTAssertEqual(rutas[0].puntos[2].longitud, -3.0, accuracy: 1e-9)
        // Solo el cruce de en medio tiene calles laterales: las de 90 y 270
        // (la de llegada, índice 2, y la de salida, índice 0, no cuentan)
        XCTAssertEqual(rutas[0].cruces.count, 1)
        let cruce = try XCTUnwrap(rutas[0].cruces.first)
        XCTAssertEqual(cruce.punto.latitud, 40.0009, accuracy: 1e-9)
        XCTAssertEqual(cruce.punto.longitud, -3.0, accuracy: 1e-9)
        XCTAssertEqual(cruce.rumbos, [90, 270])
        // Por la ruta, a 0,0009° de latitud del principio (100,2 m), de su
        // geometry_index; la ruta entera, el doble
        XCTAssertEqual(try XCTUnwrap(cruce.recorrido), 100.19, accuracy: 0.05)
        XCTAssertEqual(rutas[0].longitud, 200.38, accuracy: 0.05)
        XCTAssertEqual(rutas[1].puntos.count, 1)
        XCTAssertEqual(rutas[1].cruces, [])
        // Las vías de los pasos (sin name ni ref en esta respuesta: vacías)
        XCTAssertEqual(rutas[0].vias, ["", "M-510, Calle Mayor"])
        XCTAssertEqual(rutas[1].vias, [""])
    }

    func testVia() {
        // Número y nombre, el que haya, o nada (revisión de la 0.10.0: las
        // carreteras con solo número se quedaban sin texto)
        XCTAssertEqual(RespuestaOSRM.via(nombre: "Autovía del Noroeste", numero: "A-6"), "A-6, Autovía del Noroeste")
        XCTAssertEqual(RespuestaOSRM.via(nombre: "", numero: "M-510"), "M-510")
        XCTAssertEqual(RespuestaOSRM.via(nombre: "Calle Mayor", numero: nil), "Calle Mayor")
        XCTAssertEqual(RespuestaOSRM.via(nombre: "  ", numero: nil), "")
    }

    // MARK: entry y regla 1 (0.12.0)

    /// Un cruce de la respuesta OSRM, como lo da Valhalla.
    private func interseccion(_ p: PuntoRuta, _ rumbos: [Int], entry: [Bool]? = nil, entrada: Int? = nil,
                              salida: Int? = nil, indice: Int) -> [String: Any] {
        var cruce: [String: Any] = ["location": [p.longitud, p.latitud], "bearings": rumbos, "geometry_index": indice]
        if let entry { cruce["entry"] = entry }
        if let entrada { cruce["in"] = entrada }
        if let salida { cruce["out"] = salida }
        return cruce
    }

    /// Una respuesta OSRM de una sola ruta con estos pasos.
    private func respuestaOSRM(_ puntos: [PuntoRuta], pasos: [[String: Any]]) throws -> Data {
        let ruta: [String: Any] = ["geometry": Polilinea.codificar(puntos, precision: 6), "legs": [["steps": pasos]]]
        let respuesta: [String: Any] = ["code": "Ok", "routes": [ruta]]
        return try JSONSerialization.data(withJSONObject: respuesta)
    }

    func testEntryDeCadaCalle() throws {
        // Hacia el norte, un cruce cada 100 m: con entry, con todas las
        // laterales sin entrada (regla 1), con una sola sin entrada, sin entry
        // y con un entry de otra longitud que bearings
        let puntos = (0...6).map { punto(0, Double($0) * 100) }
        let datos = try respuestaOSRM(puntos, pasos: [
            ["intersections": [
                interseccion(puntos[0], [0], entry: [true], salida: 0, indice: 0),
                interseccion(puntos[1], [0, 90, 180, 270], entry: [true, false, false, true], entrada: 2, salida: 0,
                             indice: 1),
                interseccion(puntos[2], [0, 90, 180, 270], entry: [true, false, false, false], entrada: 2, salida: 0,
                             indice: 2),
                interseccion(puntos[3], [0, 90, 180], entry: [true, false, false], entrada: 2, salida: 0, indice: 3),
            ]],
            ["maneuver": ["type": "turn"], "intersections": [
                interseccion(puntos[4], [0, 90, 180, 270], entrada: 2, salida: 0, indice: 4),
                interseccion(puntos[5], [0, 90, 180, 270], entry: [true, true], entrada: 2, salida: 0, indice: 5),
                interseccion(puntos[6], [180], entry: [true], entrada: 0, indice: 6),
            ]],
        ])
        let ruta = try XCTUnwrap(RespuestaOSRM.rutas(de: datos).first)
        // El de 200 m no está: sus dos laterales son de no entrar (aceras)
        let esperados = [puntos[1], puntos[3], puntos[4], puntos[5]]
        XCTAssertEqual(ruta.cruces.count, esperados.count)
        for (cruce, esperado) in zip(ruta.cruces, esperados) {
            XCTAssertEqual(Trazo.distancia(cruce.punto, esperado), 0, accuracy: 0.01)
        }
        XCTAssertEqual(ruta.cruces[0].rumbos, [90, 270])
        XCTAssertEqual(ruta.cruces[0].entradas, [false, true])
        // Una sola sin entrada (una calle de un sentido que llega) se queda
        XCTAssertEqual(ruta.cruces[1].rumbos, [90])
        XCTAssertEqual(ruta.cruces[1].entradas, [false])
        // Sin entry, o con otra longitud: desconocidas
        XCTAssertEqual(ruta.cruces[2].entradas, [nil, nil])
        XCTAssertEqual(ruta.cruces[3].rumbos, [90, 270])
        XCTAssertEqual(ruta.cruces[3].entradas, [nil, nil])
        XCTAssertTrue(ruta.anillos.isEmpty)
        XCTAssertEqual(ruta.crucesConAnillos, ruta.cruces)
    }

    func testEntradasDeUnCruce() {
        let cruce = Cruce(punto: punto(0, 0), rumbos: [90, 270], entradas: [true, false])
        XCTAssertEqual(cruce.entrada(0), true)
        XCTAssertEqual(cruce.entrada(1), false)
        XCTAssertNil(cruce.entrada(2))
        XCTAssertNil(cruce.entrada(-1))
        // Con otra longitud que los rumbos, o sin dar: desconocidas
        XCTAssertEqual(Cruce(punto: punto(0, 0), rumbos: [90, 270], entradas: [true]).entradas, [nil, nil])
        XCTAssertEqual(Cruce(punto: punto(0, 0), rumbos: [90]).entradas, [nil])
    }

    // MARK: Rotonda en la respuesta (0.12.0)

    func testRotondaDeLaRespuesta() throws {
        // Hacia el norte, una rotonda de 20 m de radio con el centro en
        // (0, 100): se entra por el sur, en (0, 80), se recorre por el este
        // (13 puntos, cada 15°) y se sale por el norte, en (0, 120)
        let centro = (x: 0.0, y: 100.0)
        func enAnillo(_ grados: Double) -> PuntoRuta {
            punto(centro.x + 20 * cos(grados * .pi / 180), centro.y + 20 * sin(grados * .pi / 180))
        }
        let arco = stride(from: -90.0, through: 90.0, by: 15).map { enAnillo($0) }
        let puntos = [punto(0, 0), punto(0, 40)] + arco + [punto(0, 160), punto(0, 200)]
        XCTAssertEqual(puntos.count, 17)
        let datos = try respuestaOSRM(puntos, pasos: [
            ["maneuver": ["type": "depart"], "intersections": [
                interseccion(puntos[0], [0], entry: [true], salida: 0, indice: 0),
            ]],
            ["maneuver": ["type": "roundabout", "exit": 2] as [String: Any], "intersections": [
                // La entrada: el anillo que llega del oeste (278) es de no entrar
                interseccion(puntos[2], [83, 180, 278], entry: [true, false, false], entrada: 1, salida: 0, indice: 2),
                // Un brazo al este, en (20, 100)
                interseccion(puntos[8], [90, 188, 353], entry: [true, false, true], entrada: 1, salida: 2, indice: 8),
            ]],
            ["maneuver": ["type": "exit roundabout"], "intersections": [
                // La salida: el anillo sigue hacia el oeste (263)
                interseccion(puntos[14], [0, 98, 263], entry: [true, false, true], entrada: 1, salida: 0, indice: 14),
                interseccion(puntos[15], [0, 90, 180, 270], entry: [true, true, false, true], entrada: 2, salida: 0,
                             indice: 15),
            ]],
            ["maneuver": ["type": "arrive"], "intersections": [
                interseccion(puntos[16], [180], entry: [true], entrada: 0, indice: 16),
            ]],
        ])
        let ruta = try XCTUnwrap(RespuestaOSRM.rutas(de: datos).first)
        let anillo = try XCTUnwrap(ruta.anillos.first)
        XCTAssertEqual(ruta.anillos.count, 1)
        XCTAssertEqual(Trazo.distancia(anillo.centro, punto(centro.x, centro.y)), 0, accuracy: 0.2)
        XCTAssertEqual(anillo.radio, 20, accuracy: 0.15)
        XCTAssertEqual(anillo.recorridoEntrada, 80, accuracy: 0.5)
        // 12 cuerdas de 2·20·sen(7,5°) = 5,22 m
        XCTAssertEqual(anillo.recorridoSalida, 80 + 12 * 40 * sin(7.5 * .pi / 180), accuracy: 0.5)
        // Son de la rotonda los cruces de su paso y el primero del siguiente
        XCTAssertEqual(ruta.cruces.map(\.rumbos), [[278], [90], [263], [90, 270]])
        XCTAssertEqual(ruta.cruces.map(\.anillo), [0, 0, 0, nil])
        // Para un cuadro con anillos, sin las calles que son el anillo
        XCTAssertEqual(ruta.crucesConAnillos.map(\.rumbos), [[90], [90, 270]])
    }

    func testRotondaSinAnilloSiNoEsUnCirculo() throws {
        // La misma forma de respuesta, pero el «arco» es una recta: sin anillo
        // y sin tocar los cruces
        let puntos = (0...8).map { punto(0, Double($0) * 10) }
        let datos = try respuestaOSRM(puntos, pasos: [
            ["maneuver": ["type": "rotary"], "intersections": [
                interseccion(puntos[1], [0, 180, 270], entry: [true, false, false], entrada: 1, salida: 0, indice: 1),
            ]],
            ["maneuver": ["type": "exit rotary"], "intersections": [
                interseccion(puntos[7], [0, 90, 180], entry: [true, true, false], entrada: 2, salida: 0, indice: 7),
            ]],
        ])
        let ruta = try XCTUnwrap(RespuestaOSRM.rutas(de: datos).first)
        XCTAssertTrue(ruta.anillos.isEmpty)
        XCTAssertEqual(ruta.cruces.map(\.anillo), [nil, nil])
        XCTAssertEqual(ruta.crucesConAnillos, ruta.cruces)
    }

    func testNoEsUnaRespuestaOSRM() {
        // El formato propio de Valhalla (el de las rutas propuestas) no vale
        XCTAssertThrowsError(try RespuestaOSRM.rutas(de: Data(#"{"trip":{"legs":[]}}"#.utf8)))
        XCTAssertThrowsError(try RespuestaOSRM.rutas(de: Data("no es JSON".utf8)))
    }

    // MARK: Ruta del guiado

    func testBuscarLaRutaDelGuiado() {
        let corta = RutaConCruces(puntos: [punto(0, 0), punto(0, 100), punto(0, 200)], cruces: [])
        let larga = RutaConCruces(puntos: [punto(0, 0), punto(0, 100), punto(0, 200), punto(100, 200)],
                                  cruces: [Cruce(punto: punto(0, 100), rumbos: [90])])
        // La del guiado, con los extremos a 0,5 m: la larga
        let guiado = [punto(0.5, 0), punto(0, 100), punto(0, 200), punto(100, 200.5)]
        XCTAssertEqual(Cruces.buscar(guiado, en: [corta, larga]), larga)
        // A 5 m ya no coincide; con otro número de puntos, tampoco
        let lejos = [punto(5, 0), punto(0, 100), punto(0, 200), punto(100, 200)]
        XCTAssertNil(Cruces.buscar(lejos, en: [corta, larga]))
        XCTAssertNil(Cruces.buscar([punto(0, 0), punto(100, 200)], en: [corta, larga]))
        XCTAssertNil(Cruces.buscar([], en: [corta, larga]))
    }

    // MARK: Calles del tramo

    /// Tramo hacia el norte de 300 m desde la moto, en (0, 0).
    private var rutaNorte: [PuntoRuta] {
        [punto(0, 0), punto(0, 100), punto(0, 200), punto(0, 300)]
    }

    /// Desordenados: a 250 m, uno a 50 m del tramo, otro a 100 m con dos
    /// calles, otro pasado el final y uno a 2 m del tramo a 30 m de la moto.
    private var crucesNorte: [Cruce] {
        [
            Cruce(punto: punto(0, 250), rumbos: [45]),
            Cruce(punto: punto(50, 150), rumbos: [90]),
            Cruce(punto: punto(0, 100), rumbos: [90, 270]),
            Cruce(punto: punto(0, 400), rumbos: [90]),
            Cruce(punto: punto(2, 30), rumbos: [300]),
        ]
    }

    private func comprobar(_ calles: [CalleCruce], _ esperadas: [(x: Double, y: Double, direccion: UInt8)],
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(calles.count, esperadas.count, file: file, line: line)
        for (calle, esperada) in zip(calles, esperadas) {
            XCTAssertEqual(calle.x, esperada.x, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(calle.y, esperada.y, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(calle.direccion, esperada.direccion, file: file, line: line)
        }
    }

    func testCallesDelTramoEnOrden() {
        // Los dos lejanos fuera; los demás por lo que se recorre hasta ellos.
        // 300° es 213/256 de vuelta (213,3); 90°, 64; 270°, 192; 45°, 32
        let calles = Cruces.calles(de: crucesNorte, ruta: rutaNorte, sentido: 0)
        comprobar(calles, [(2, 30, 213), (0, 100, 64), (0, 100, 192), (0, 250, 32)])
    }

    func testCallesHastaElMaximo() {
        let calles = Cruces.calles(de: crucesNorte, ruta: rutaNorte, sentido: 0, maximo: 2)
        comprobar(calles, [(2, 30, 213), (0, 100, 64)])
        XCTAssertEqual(Cruces.calles(de: crucesNorte, ruta: rutaNorte, sentido: 0, maximo: 0), [])
    }

    func testCallesEnLosEjesDeLaMoto() {
        // Hacia el este: el cruce a 100 m queda delante; la calle del norte, a
        // la izquierda (192), y la del sur, a la derecha (64)
        let este = [punto(0, 0), punto(100, 0), punto(200, 0)]
        let cruces = [Cruce(punto: punto(100, 0), rumbos: [0, 180])]
        let calles = Cruces.calles(de: cruces, ruta: este, sentido: 90)
        comprobar(calles, [(0, 100, 192), (0, 100, 64)])
    }

    func testCallesSoloDeLaVentana() {
        // El mismo sitio, a 100 m de la moto por el tramo: uno de otra pasada de
        // la ruta (a 1100 m de su principio) y otro de esta (a 600 m), con la
        // moto a 500 m del principio y la ventana de 500 a 800 (revisión de la
        // 0.10.0). Y uno ya pasado, 3 m detrás de la moto y junto a la ruta
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 1_100),
            Cruce(punto: punto(0, 100), rumbos: [270], recorrido: 600),
            Cruce(punto: punto(0, -3), rumbos: [90], recorrido: 497),
        ]
        comprobar(Cruces.calles(de: cruces, ruta: rutaNorte, sentido: 0, ventana: 500...800), [(0, 100, 192)])
        // Sin ventana, también el de la otra pasada; el de detrás, nunca
        comprobar(Cruces.calles(de: cruces, ruta: rutaNorte, sentido: 0), [(0, 100, 64), (0, 100, 192)])
    }

    // MARK: Regla 2: rayas dobles (0.12.0; una vez por ruta desde la 0.12.1)

    /// Los cruces de una ruta hacia el norte (`rutaNorte`, que empieza en la
    /// moto) ya con la regla 2, como los da RutaConCruces.
    private func conRegla2(_ cruces: [Cruce]) -> [Cruce] {
        RutaConCruces(puntos: rutaNorte, cruces: cruces).cruces
    }

    func testRayasDoblesSeQuedaLaDeEntrar() {
        // A 100 y 110 m, dos calles a la derecha casi paralelas (90° y 95°):
        // se queda la de 110, por la que se puede entrar. La de 120, a la
        // izquierda, no es doble. La de 150 (92°) está a 50 m de la primera y a
        // 40 de la de 110: tampoco. 95° es 68/256 de vuelta (67,6); 92°, 65
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100, entradas: [false]),
            Cruce(punto: punto(0, 110), rumbos: [95], recorrido: 110, entradas: [true]),
            Cruce(punto: punto(0, 120), rumbos: [270], recorrido: 120, entradas: [true]),
            Cruce(punto: punto(0, 150), rumbos: [92], recorrido: 150, entradas: [false]),
        ]
        let juntos = conRegla2(cruces)
        // El de 100 se queda sin calles: fuera
        XCTAssertEqual(juntos, [cruces[1], cruces[2], cruces[3]])
        comprobar(Cruces.calles(de: juntos, ruta: rutaNorte, sentido: 0),
                  [(0, 110, 68), (0, 120, 192), (0, 150, 65)])
    }

    func testRayasDoblesSinEntradaSeQuedaLaPrimera() {
        // Sin ninguna por la que se pueda entrar (false o sin saber), la primera
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100, entradas: [false]),
            Cruce(punto: punto(0, 105), rumbos: [100], recorrido: 105),
        ]
        XCTAssertEqual(conRegla2(cruces), [cruces[0]])
    }

    func testRayasDoblesEnElMismoCruce() {
        // Dos calles del mismo cruce a 20°: una (la de entrar, 110°). A 35°,
        // las dos
        let juntas = conRegla2([Cruce(punto: punto(0, 100), rumbos: [90, 110], recorrido: 100,
                                      entradas: [nil, true])])
        XCTAssertEqual(juntas.map(\.rumbos), [[110]])
        XCTAssertEqual(juntas.map(\.entradas), [[true]])
        let separadas = [Cruce(punto: punto(0, 100), rumbos: [90, 125], recorrido: 100)]
        XCTAssertEqual(conRegla2(separadas), separadas)
    }

    func testRayasDoblesAncladasEnLaPrimera() {
        // 90° a 100 m, 115° a 120 m y 140° a 140 m: la segunda va con la
        // primera (25°, 20 m), pero la tercera no (está a 40 m de la primera,
        // aunque a 20 de la segunda): no se encadenan
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100),
            Cruce(punto: punto(0, 120), rumbos: [115], recorrido: 120),
            Cruce(punto: punto(0, 140), rumbos: [140], recorrido: 140),
        ]
        XCTAssertEqual(conRegla2(cruces), [cruces[0], cruces[2]])
    }

    func testRayasDoblesAntesDelMaximo() {
        // Con 2 como máximo: la doble no gasta sitio (la regla 2 va antes, en
        // la ruta). 92° es 65/256 de vuelta (65,4)
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100, entradas: [false]),
            Cruce(punto: punto(0, 105), rumbos: [92], recorrido: 105, entradas: [true]),
            Cruce(punto: punto(0, 200), rumbos: [270], recorrido: 200),
        ]
        comprobar(Cruces.calles(de: conRegla2(cruces), ruta: rutaNorte, sentido: 0, maximo: 2),
                  [(0, 105, 65), (0, 200, 192)])
    }

    func testRayasDoblesPorElRecorridoYSinElSeQuedan() {
        // Por el recorrido de la ruta, no por el orden de la lista; los cruces
        // sin recorrido no se tocan, y Cruces.calles ya no junta nada
        let cruces = [
            Cruce(punto: punto(0, 110), rumbos: [95], recorrido: 110, entradas: [true]),
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100, entradas: [false]),
            Cruce(punto: punto(0, 50), rumbos: [90]),
            Cruce(punto: punto(0, 55), rumbos: [92]),
        ]
        XCTAssertEqual(Cruces.juntarDobles(en: cruces), [cruces[0], cruces[2], cruces[3]])
        comprobar(Cruces.calles(de: [cruces[2], cruces[3]], ruta: rutaNorte, sentido: 0),
                  [(0, 50, 64), (0, 55, 65)])
    }

    func testRayasDoblesNoCambianAlAvanzar() {
        // 90° a 100 m (de entrar), 115° a 120 m y 140° a 140 m (sin entrada):
        // con la regla 2 de la ruta entera se quedan la de 100 y la de 140 (la
        // de 120 va con la de 100; la de 140, a 40 m de ella, no). Tramo a
        // tramo (0.12.0), al pasar la moto la de 100 el grupo se rehacía con
        // ancla en la de 120: aparecía la de 120 y desaparecía la de 140, que
        // seguía por delante (revisión de la 0.12.0). Ahora la moto avanza de
        // 5 en 5 m y las calles que quedan por delante son siempre las mismas.
        // 140° es 100/256 de vuelta (99,6)
        let cruces = [
            Cruce(punto: punto(0, 100), rumbos: [90], recorrido: 100, entradas: [true]),
            Cruce(punto: punto(0, 120), rumbos: [115], recorrido: 120, entradas: [false]),
            Cruce(punto: punto(0, 140), rumbos: [140], recorrido: 140, entradas: [false]),
        ]
        let ruta = RutaConCruces(puntos: [punto(0, 0), punto(0, 500)], cruces: cruces)
        XCTAssertEqual(ruta.cruces, [cruces[0], cruces[2]])
        let delante: [(recorrido: Double, direccion: UInt8)] = [(100, 64), (140, 100)]
        for moto in stride(from: 0.0, through: 135, by: 5) {
            let tramo = [punto(0, moto), punto(0, moto + 300)]
            let calles = Cruces.calles(de: ruta.cruces, ruta: tramo, sentido: 0,
                                       ventana: max(0, moto - 50)...(moto + 300))
            // Las de delante: a 1 m o más de la moto
            let esperadas = delante
                .filter { $0.recorrido - moto >= 1 }
                .map { calle -> (x: Double, y: Double, direccion: UInt8) in
                    (x: 0, y: calle.recorrido - moto, direccion: calle.direccion)
                }
            comprobar(calles, esperadas)
        }
    }

    func testDiferenciaAngular() {
        XCTAssertEqual(Cruces.diferenciaAngular(10, 350), 20, accuracy: 1e-9)
        XCTAssertEqual(Cruces.diferenciaAngular(350, 10), -20, accuracy: 1e-9)
        XCTAssertEqual(Cruces.diferenciaAngular(180, 0), 180, accuracy: 1e-9)
        XCTAssertEqual(Cruces.diferenciaAngular(0, 180), 180, accuracy: 1e-9)
        XCTAssertEqual(Cruces.diferenciaAngular(720, 5), -5, accuracy: 1e-9)
        XCTAssertTrue(Cruces.diferenciaAngular(.nan, 0).isNaN)
    }

    func testSinTramoNiCruces() {
        XCTAssertEqual(Cruces.calles(de: crucesNorte, ruta: [punto(0, 0)], sentido: 0), [])
        XCTAssertEqual(Cruces.calles(de: [], ruta: rutaNorte, sentido: 0), [])
    }

    func testDireccion() {
        XCTAssertEqual(Cruces.direccion(rumbo: 0, sentido: 0), 0)
        XCTAssertEqual(Cruces.direccion(rumbo: 90, sentido: 0), 64)
        XCTAssertEqual(Cruces.direccion(rumbo: 180, sentido: 0), 128)
        XCTAssertEqual(Cruces.direccion(rumbo: 0, sentido: 90), 192)
        // 10° respecto a 350°: 20°, 14/256 (14,2)
        XCTAssertEqual(Cruces.direccion(rumbo: 10, sentido: 350), 14)
        // 359,9° redondea a 256, que es otra vez 0
        XCTAssertEqual(Cruces.direccion(rumbo: 359.9, sentido: 0), 0)
    }
}
