import Foundation
import XCTest
@testable import LPRCore

final class RutasGuardadasTests: XCTestCase {
    /// Un destino de prueba (coordenadas inventadas, no de un viaje real).
    private func ruta(_ nombre: String, lat: Double = 40.0, lon: Double = -3.0, tipo: String = "rapida",
                      margen: Double = 0.25, dia: Double = 0) -> RutaGuardada {
        RutaGuardada(nombre: nombre, latitud: lat, longitud: lon, tipo: tipo, evitarPeajes: true,
                     evitarAutopistas: false, margen: margen, metros: 12_000, segundos: 900, curvas: 14,
                     fecha: Date(timeIntervalSince1970: 1_000_000 + dia * 86_400))
    }

    func testLaNuevaVaPrimero() {
        let a = ruta("A")
        let b = ruta("B", lat: 41.0)
        let lista = RutasGuardadas.anadir(b, a: [a])
        XCTAssertEqual(lista.map(\.nombre), ["B", "A"])
    }

    func testLaMismaRutaSeSustituyeYCuenta() {
        let a = ruta("A")
        let b = ruta("B", lat: 41.0)
        // El mismo destino a unos 50 m (0,00045° de latitud), otro día
        var otraVez = ruta("A otra vez", lat: 40.00045, dia: 3)
        otraVez.id = UUID()
        let lista = RutasGuardadas.anadir(otraVez, a: [b, a])
        XCTAssertEqual(lista.count, 2)
        XCTAssertEqual(lista[0].nombre, "A otra vez")
        XCTAssertEqual(lista[0].id, a.id)
        XCTAssertEqual(lista[0].veces, 2)
        XCTAssertEqual(lista[1].nombre, "B")
    }

    func testOtroTipoOMargenEsOtraRuta() {
        let a = ruta("A")
        XCTAssertEqual(RutasGuardadas.anadir(ruta("A", tipo: "divertida"), a: [a]).count, 2)
        XCTAssertEqual(RutasGuardadas.anadir(ruta("A", margen: 0.5), a: [a]).count, 2)
        // Destino a unos 200 m: otro sitio
        XCTAssertEqual(RutasGuardadas.anadir(ruta("A", lat: 40.0018), a: [a]).count, 2)
        var sinPeajes = ruta("A")
        sinPeajes.evitarPeajes = false
        XCTAssertFalse(sinPeajes.esLaMisma(que: a))
    }

    func testLaCargadaDeLaListaSubeAunqueCambieElTipo() {
        // Cargada desde la pestaña «Rutas» (mismo id) e iniciada con otro tipo
        // de ruta: sube arriba, no se duplica
        let a = ruta("A")
        let b = ruta("B", lat: 41.0)
        var otraVez = ruta("A", tipo: "divertida", dia: 2)
        otraVez.id = a.id
        let lista = RutasGuardadas.anadir(otraVez, a: [b, a])
        XCTAssertEqual(lista.map(\.nombre), ["A", "B"])
        XCTAssertEqual(lista[0].tipo, "divertida")
        XCTAssertEqual(lista[0].veces, 2)
    }

    func testComoMuchoElMaximo() {
        var lista: [RutaGuardada] = []
        for i in 0..<5 {
            lista = RutasGuardadas.anadir(ruta("R\(i)", lat: 40.0 + Double(i)), a: lista, maximo: 3)
        }
        XCTAssertEqual(lista.map(\.nombre), ["R4", "R3", "R2"])
    }

    func testLosAccesosDirectosNoSeQuitanPorViejos() {
        var lista: [RutaGuardada] = []
        for i in 0..<3 {
            lista = RutasGuardadas.anadir(ruta("R(i)", lat: 40.0 + Double(i)), a: lista, maximo: 3)
        }
        // R0 es la más antigua, pero es acceso directo: sale R1
        let fijada: Set = [lista[2].id]
        lista = RutasGuardadas.anadir(ruta("R3", lat: 43.0), a: lista, maximo: 3, conservar: fijada)
        XCTAssertEqual(lista.map(.nombre), ["R3", "R2", "R0"])
    }

    func testParaElCuadro() {
        let lista = (0..<5).map { ruta("R($0)", lat: 40.0 + Double($0)) }   // R0, la más reciente
        // Sin accesos directos, las tres más recientes
        XCTAssertEqual(RutasGuardadas.paraElCuadro(lista, accesos: [nil, nil, nil]).map(.nombre), ["R0", "R1", "R2"])
        // Uno (R4) en el segundo hueco: primero él y luego las dos más recientes
        XCTAssertEqual(RutasGuardadas.paraElCuadro(lista, accesos: [nil, lista[4].id, nil]).map(.nombre),
                       ["R4", "R0", "R1"])
        // Dos, uno de ellos reciente: no se repite
        XCTAssertEqual(RutasGuardadas.paraElCuadro(lista, accesos: [lista[3].id, lista[0].id, nil]).map(.nombre),
                       ["R3", "R0", "R1"])
        // Uno que ya no está, como vacío; y con menos de tres rutas, las que haya
        XCTAssertEqual(RutasGuardadas.paraElCuadro(lista, accesos: [UUID(), nil, nil]).map(.nombre), ["R0", "R1", "R2"])
        XCTAssertEqual(RutasGuardadas.paraElCuadro(Array(lista.prefix(1)), accesos: []).map(.nombre), ["R0"])
    }

    func testSeGuardaYSeLee() throws {
        let lista = [ruta("A"), ruta("B", lat: 41.0, tipo: "divertida")]
        let datos = try RutasGuardadas.codificar(lista)
        XCTAssertEqual(RutasGuardadas.decodificar(datos), lista)
        XCTAssertEqual(RutasGuardadas.decodificar(Data("no es json".utf8)), [])
    }
}
