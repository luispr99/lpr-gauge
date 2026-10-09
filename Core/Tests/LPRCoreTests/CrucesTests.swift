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
