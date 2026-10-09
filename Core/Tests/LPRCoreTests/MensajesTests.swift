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
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 0x99))
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x00, 0x00, 0x00, 0x07, 0x05, 0x99]),
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 5))
    }

    func testStatusDescartaLoInvalido() {
        XCTAssertNil(MensajeStatus.decodificar([0x01, 0x00, 0x00]))
        XCTAssertNil(MensajeStatus.decodificar([0x02, 0x00, 0x00, 0x00, 0x07]))
    }

    func testStatusIdaYVuelta() {
        let s = MensajeStatus(ecoNav: 9, ecoGPS: 8, pideReenvio: true, ecoMovil: 7)
        XCTAssertEqual(MensajeStatus.decodificar(s.codificar()), s)
        let conTexto = MensajeStatus(ecoNav: 9, ecoGPS: 8, pideReenvio: false, ecoMovil: 7, ecoNavText: 6)
        XCTAssertEqual(conTexto.codificar(), [0x01, 0x09, 0x08, 0x00, 0x07, 0x06])
        XCTAssertEqual(MensajeStatus.decodificar(conTexto.codificar()), conTexto)
    }

    // MARK: NAV_TEXT

    func testNavTextCodifica() {
        XCTAssertEqual(MensajeNavText(secuencia: 3, texto: "Hola").codificar(),
                       [0x01, 0x03, 0x48, 0x6F, 0x6C, 0x61])
        XCTAssertEqual(MensajeNavText(secuencia: 0, texto: "").codificar(), [0x01, 0x00])
        XCTAssertEqual(MensajeNavText(secuencia: 1, texto: "350 m\nGira").codificar(),
                       [0x01, 0x01, 0x33, 0x35, 0x30, 0x20, 0x6D, 0x0A, 0x47, 0x69, 0x72, 0x61])
        XCTAssertEqual(MensajeNavText(secuencia: 9, texto: "Calle Peñón").codificar(),
                       [0x01, 0x09, 0x43, 0x61, 0x6C, 0x6C, 0x65, 0x20, 0x50, 0x65, 0xC3, 0xB1, 0xC3, 0xB3, 0x6E])
    }

    func testNavTextCortaSinPartirCaracteres() {
        // "aññ" son 5 bytes; con 6 de máximo caben 4 de texto: se queda "añ"
        XCTAssertEqual(MensajeNavText(secuencia: 0, texto: "aññ").codificar(maximo: 6),
                       [0x01, 0x00, 0x61, 0xC3, 0xB1])
        // Con el MTU mínimo (20 bytes por escritura), 18 de texto
        let largo = String(repeating: "x", count: 300)
        XCTAssertEqual(MensajeNavText(secuencia: 0, texto: largo).codificar(maximo: 20).count, 20)
        // Nunca más de 182, aunque la conexión admita más
        XCTAssertEqual(MensajeNavText(secuencia: 0, texto: largo).codificar(maximo: 512).count, 182)
        XCTAssertEqual(MensajeNavText(secuencia: 0, texto: largo).codificar().count, 182)
    }

    func testNavTextDecodifica() {
        XCTAssertEqual(MensajeNavText.decodificar([0x01, 0x03, 0x48, 0x6F, 0x6C, 0x61]),
                       MensajeNavText(secuencia: 3, texto: "Hola"))
        XCTAssertEqual(MensajeNavText.decodificar([0x01, 0x00]), MensajeNavText(secuencia: 0, texto: ""))
        XCTAssertNil(MensajeNavText.decodificar([0x01]))
        XCTAssertNil(MensajeNavText.decodificar([0x02, 0x00, 0x41]))
        XCTAssertNil(MensajeNavText.decodificar([0x01, 0x00, 0xC3]))
    }

    // MARK: DEVICE_INFO

    func testDeviceInfoDelFirmwareDeReferencia() {
        let info = DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(info, DeviceInfo(version: 1, tipo: 2, capacidades: [.status, .movil],
                                        frecuenciaMaxima: 0, firmware: [0, 1, 0]))
        XCTAssertEqual(info?.capacidades.contains(.movil), true)
        XCTAssertEqual(info?.capacidades.contains(.nav), false)
    }

    func testDeviceInfoDelCuadro() {
        let info = DeviceInfo.decodificar([0x01, 0x01, 0x2C, 0x00, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(info, DeviceInfo(version: 1, tipo: 1, capacidades: [.status, .navText, .movil],
                                        frecuenciaMaxima: 0, firmware: [0, 1, 0]))
    }

    func testDeviceInfoDescartaLoCorto() {
        XCTAssertNil(DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01]))
    }
}
