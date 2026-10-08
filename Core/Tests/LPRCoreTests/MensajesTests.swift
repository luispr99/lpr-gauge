import XCTest
@testable import LPRCore

// Los bytes de estas pruebas son los de docs/vectores/mensajes.md.
final class MensajesTests: XCTestCase {

    // MARK: Secuencia

    func testSecuenciaEmpiezaEnCeroYDaLaVuelta() {
        var s = Secuencia()
        XCTAssertEqual(s.siguiente(), 0)
        XCTAssertEqual(s.siguiente(), 1)
        for _ in 2...255 { _ = s.siguiente() }
        XCTAssertEqual(s.siguiente(), 0)
    }

    // MARK: MOVIL

    func testMovilCodifica() {
        XCTAssertEqual(MensajeMovil(secuencia: 7, estado: .cargando, nivel: 85).codificar(),
                       [0x01, 0x07, 0x02, 0x55])
        XCTAssertEqual(MensajeMovil(secuencia: 0, estado: .sinCargar, nivel: 100).codificar(),
                       [0x01, 0x00, 0x01, 0x64])
        XCTAssertEqual(MensajeMovil(secuencia: 42, estado: .cargada, nivel: 100).codificar(),
                       [0x01, 0x2A, 0x03, 0x64])
        XCTAssertEqual(MensajeMovil(secuencia: 255, estado: .desconocido, nivel: nil).codificar(),
                       [0x01, 0xFF, 0x00, 0xFF])
    }

    func testMovilSaturaElNivelEn100() {
        XCTAssertEqual(MensajeMovil(secuencia: 1, estado: .cargando, nivel: 140).codificar(),
                       [0x01, 0x01, 0x02, 0x64])
    }

    func testMovilDecodifica() {
        XCTAssertEqual(MensajeMovil.decodificar([0x01, 0x07, 0x02, 0x55]),
                       MensajeMovil(secuencia: 7, estado: .cargando, nivel: 85))
        XCTAssertEqual(MensajeMovil.decodificar([0x01, 0xFF, 0x00, 0xFF]),
                       MensajeMovil(secuencia: 255, estado: .desconocido, nivel: nil))
        XCTAssertEqual(MensajeMovil.decodificar([0x01, 0x07, 0x02, 0xC8])?.nivel, 100)
    }

    func testMovilDescartaLoInvalido() {
        XCTAssertNil(MensajeMovil.decodificar([0x01, 0x07, 0x02]))
        XCTAssertNil(MensajeMovil.decodificar([0x02, 0x07, 0x02, 0x55]))
        XCTAssertNil(MensajeMovil.decodificar([0x01, 0x07, 0x04, 0x55]))
    }

    // MARK: STATUS

    func testStatusDecodifica() {
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x00, 0x00, 0x01, 0x00]),
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: true, ecoMovil: 0))
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x00, 0x00, 0x00, 0x07]),
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7))
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x03, 0x04, 0x00]),
                       MensajeStatus(ecoNav: 3, ecoGPS: 4, pideReenvio: false, ecoMovil: nil))
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x00, 0x00, 0x00, 0x07, 0x99]),
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7))
    }

    func testStatusDescartaLoInvalido() {
        XCTAssertNil(MensajeStatus.decodificar([0x01, 0x00, 0x00]))
        XCTAssertNil(MensajeStatus.decodificar([0x02, 0x00, 0x00, 0x00, 0x07]))
    }

    func testStatusIdaYVuelta() {
        let s = MensajeStatus(ecoNav: 9, ecoGPS: 8, pideReenvio: true, ecoMovil: 7)
        XCTAssertEqual(MensajeStatus.decodificar(s.codificar()), s)
    }

    // MARK: DEVICE_INFO

    func testDeviceInfoDelFirmwareDeReferencia() {
        let info = DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(info, DeviceInfo(version: 1, tipo: 2, capacidades: [.status, .movil],
                                        frecuenciaMaxima: 0, firmware: [0, 1, 0]))
        XCTAssertEqual(info?.capacidades.contains(.movil), true)
        XCTAssertEqual(info?.capacidades.contains(.nav), false)
    }

    func testDeviceInfoDescartaLoCorto() {
        XCTAssertNil(DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01]))
    }
}
