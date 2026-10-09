import XCTest
@testable import LPRCore

final class ProtocoloTests: XCTestCase {
    func testVersionEsLaDelDocumento() {
        XCTAssertEqual(Protocolo.version, 1)
    }

    func testUUIDsCompartenBaseYSonDistintos() {
        let todos = [
            Protocolo.UUIDs.servicio,
            Protocolo.UUIDs.deviceInfo,
            Protocolo.UUIDs.nav,
            Protocolo.UUIDs.gps,
            Protocolo.UUIDs.status,
            Protocolo.UUIDs.navText,
            Protocolo.UUIDs.movil,
            Protocolo.UUIDs.trazo,
            Protocolo.UUIDs.cruces,
        ]
        for uuid in todos {
            XCTAssertEqual(uuid.count, 36, uuid)
            XCTAssertTrue(uuid.hasPrefix("f464"), uuid)
            XCTAssertTrue(uuid.hasSuffix("-813a-45b8-8ca8-f5f9e18c21d1"), uuid)
        }
        XCTAssertEqual(Set(todos).count, todos.count)
    }

    func testMantenimientoMasFrecuenteQueCaducidad() {
        XCTAssertLessThan(Protocolo.mantenimientoSegundos, Protocolo.caducidadSegundos)
    }
}
