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
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 5, ecoTrazo: 0x99))
        // Desde la v0.6 el octavo byte es el eco de CRUCES (antes sobraba)
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x00, 0x00, 0x00, 0x07, 0x05, 0x03, 0x99]),
                       MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 5, ecoTrazo: 3,
                                     ecoCruces: 0x99))
        XCTAssertEqual(MensajeStatus.decodificar([0x01, 0x04, 0x00, 0x00, 0x07, 0x05, 0x03, 0x02, 0x99]),
                       MensajeStatus(ecoNav: 4, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 5, ecoTrazo: 3,
                                     ecoCruces: 2))
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
        let conTrazo = MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 6, ecoTrazo: 5)
        XCTAssertEqual(conTrazo.codificar(), [0x01, 0x00, 0x00, 0x00, 0x07, 0x06, 0x05])
        XCTAssertEqual(MensajeStatus.decodificar(conTrazo.codificar()), conTrazo)
        let conCruces = MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 6,
                                      ecoTrazo: 5, ecoCruces: 4)
        XCTAssertEqual(conCruces.codificar(), [0x01, 0x00, 0x00, 0x00, 0x07, 0x06, 0x05, 0x04])
        XCTAssertEqual(MensajeStatus.decodificar(conCruces.codificar()), conCruces)
        // Sin eco de TRAZO no puede haber eco de CRUCES
        XCTAssertNil(MensajeStatus(ecoNav: 0, ecoGPS: 0, pideReenvio: false, ecoMovil: 7, ecoNavText: 6,
                                   ecoCruces: 4).ecoCruces)
    }

    // MARK: NAV

    /// Tiempo de viaje y distancia recorrida desconocidos (v0.10).
    private let sinResumen: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    /// Sin maniobra luego (v0.11): código 0, modificador 0, ángulo y
    /// distancia desconocidos.
    private let sinLuego: [UInt8] = [0x00, 0x00, 0xFF, 0x7F, 0xFF, 0xFF]

    /// Los 17 bytes de la v0.6 con el resumen desconocido y sin maniobra
    /// luego (31 bytes).
    private func conResumen(_ bytes: [UInt8]) -> [UInt8] {
        bytes + sinResumen + sinLuego
    }

    func testNavSinRuta() {
        XCTAssertEqual(MensajeNav(secuencia: 0, banderas: []).codificar(), conResumen([
            0x01, 0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFF, 0xFF, 0x7F,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]))
    }

    func testNavCodificaUnGiro() {
        // A la derecha (90) a 350 m; quedan 12 340 m y 15 min; llegada a las
        // 18:45 (1125); paso de 800 m
        let mensaje = MensajeNav(secuencia: 0x10, banderas: [.rutaActiva], maniobra: .giro, distancia: 350,
                                 angulo: 90, distanciaRestante: 12_340, tiempoRestante: 900, horaLlegada: 1125,
                                 longitudPaso: 800)
        XCTAssertEqual(mensaje.codificar(), conResumen([
            0x01, 0x10, 0x01, 0x02, 0x00,
            0x5E, 0x01, 0x5A, 0x00,
            0xD2, 0x04, 0x0F, 0x00, 0x65, 0x04, 0x20, 0x03,
        ]))
        XCTAssertEqual(MensajeNav.decodificar(mensaje.codificar()), mensaje)
    }

    func testNavCodificaUnaRotondaRedondeando() {
        // Tercera salida, a la izquierda (-90), a 120,4 m; 5004 m van como 500
        // decenas y 389 s como 6 min; llegada a las 0:00; sin longitud del paso
        let mensaje = MensajeNav(secuencia: 0x11, banderas: [.rutaActiva], maniobra: .rotonda, modificador: 3,
                                 distancia: 120.4, angulo: -90, distanciaRestante: 5_004, tiempoRestante: 389,
                                 horaLlegada: 0, longitudPaso: nil)
        let bytes = mensaje.codificar()
        XCTAssertEqual(bytes, conResumen([
            0x01, 0x11, 0x01, 0x03, 0x03,
            0x78, 0x00, 0xA6, 0xFF,
            0xF4, 0x01, 0x06, 0x00, 0x00, 0x00, 0xFF, 0xFF,
        ]))
        XCTAssertEqual(MensajeNav.decodificar(bytes),
                       MensajeNav(secuencia: 0x11, banderas: [.rutaActiva], maniobra: .rotonda, modificador: 3,
                                  distancia: 120, angulo: -90, distanciaRestante: 5_000, tiempoRestante: 360,
                                  horaLlegada: 0, longitudPaso: nil))
    }

    func testNavBanderas() {
        let recalculando = MensajeNav(secuencia: 1, banderas: [.rutaActiva, .recalculando]).codificar()
        XCTAssertEqual(recalculando[2], 0x03)
        let fuera = MensajeNav(secuencia: 1, banderas: [.rutaActiva, .fueraDeRuta]).codificar()
        XCTAssertEqual(fuera[2], 0x05)
        // Al llegar: sin ruta activa y con el bit de llegada
        let llegada = MensajeNav(secuencia: 0x20, banderas: [.llegada], maniobra: .llegada).codificar()
        XCTAssertEqual(llegada, conResumen([
            0x01, 0x20, 0x08, 0x05, 0x00,
            0xFF, 0xFF, 0xFF, 0x7F,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]))
    }

    func testNavSatura() {
        // El tiempo de viaje se satura en 4 294 967 294 (0xFFFFFFFE); la
        // distancia negativa, en 0
        let saturado = MensajeNav(secuencia: 0, banderas: [.rutaActiva], maniobra: .recto, distancia: 70_000,
                                  angulo: 200, distanciaRestante: 1_000_000, tiempoRestante: 10_000_000,
                                  horaLlegada: 1440, longitudPaso: -5, tiempoViaje: 5_000_000_000,
                                  distanciaRecorrida: -5)
        XCTAssertEqual(saturado.codificar(), [
            0x01, 0x00, 0x01, 0x01, 0x00,
            0xFE, 0xFF, 0xB4, 0x00,
            0xFE, 0xFF, 0xFE, 0xFF, 0xFF, 0xFF, 0x00, 0x00,
            0xFE, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0xFF, 0x7F, 0xFF, 0xFF,
        ])
        // -400 se queda en -180 (0xFF4C); lo que no es finito, desconocido
        let otro = MensajeNav(secuencia: 0, banderas: [.rutaActiva], distancia: .infinity, angulo: -400,
                              distanciaRestante: .nan, tiempoViaje: .infinity, distanciaRecorrida: .nan).codificar()
        XCTAssertEqual(Array(otro[5...10]), [0xFF, 0xFF, 0x4C, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(otro[17...24]), sinResumen)
    }

    func testNavConResumenDelViaje() {
        // Al llegar (v0.10, docs/vectores/mensajes.md): ruta activa y llegada
        // (0x09), código 5, distancia 0; 1 h 23 min 45 s de viaje (5025 s,
        // 0x000013A1) y 123 456 m recorridos (0x0001E240). Media: 88,4 km/h
        let mensaje = MensajeNav(secuencia: 0x21, banderas: [.rutaActiva, .llegada], maniobra: .llegada,
                                 distancia: 0, tiempoViaje: 5_025.4, distanciaRecorrida: 123_456.2)
        let bytes = mensaje.codificar()
        XCTAssertEqual(bytes, [
            0x01, 0x21, 0x09, 0x05, 0x00,
            0x00, 0x00, 0xFF, 0x7F,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xA1, 0x13, 0x00, 0x00, 0x40, 0xE2, 0x01, 0x00,
            0x00, 0x00, 0xFF, 0x7F, 0xFF, 0xFF,
        ])
        let leido = MensajeNav.decodificar(bytes)
        XCTAssertEqual(leido?.tiempoViaje, 5_025)
        XCTAssertEqual(leido?.distanciaRecorrida, 123_456)
        XCTAssertEqual(leido?.banderas.rawValue, 0x09)
        XCTAssertEqual(leido?.maniobra, .llegada)
        XCTAssertEqual(leido?.maniobraLuego, .desconocida)
        // Si la conexión no admite 25 bytes, los 17 de la v0.6 (§2)
        XCTAssertEqual(mensaje.codificar(maximo: 20), Array(bytes.prefix(17)))
        XCTAssertEqual(mensaje.codificar(maximo: 25), Array(bytes.prefix(25)))
        // Con 17 a 24 bytes, el resumen es desconocido
        XCTAssertNil(MensajeNav.decodificar(Array(bytes.prefix(24)))?.tiempoViaje)
        XCTAssertNil(MensajeNav.decodificar(Array(bytes.prefix(17)))?.distanciaRecorrida)
        // Uno solo de los dos, el otro desconocido
        let soloTiempo = MensajeNav(secuencia: 0x21, banderas: [.rutaActiva], tiempoViaje: 60).codificar()
        XCTAssertEqual(Array(soloTiempo[17...24]), [0x3C, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertNil(MensajeNav.decodificar(soloTiempo)?.distanciaRecorrida)
        XCTAssertEqual(MensajeNav.decodificar(soloTiempo)?.tiempoViaje, 60)
    }

    func testNavConLuego() {
        // «Y luego» (v0.11, docs/vectores/mensajes.md): giro a la derecha (90)
        // a 80 m; quedan 2000 m (200 decenas) y 4 min; llegada a las 10:00
        // (600); paso de 300 m; 754 s de viaje (0x02F2) y 9000 m recorridos
        // (0x2328); y luego, rotonda, segunda salida, ángulo -45 (0xFFD3), a
        // 120 m de la siguiente
        let mensaje = MensajeNav(secuencia: 0x12, banderas: [.rutaActiva], maniobra: .giro, distancia: 80,
                                 angulo: 90, distanciaRestante: 2_000, tiempoRestante: 240, horaLlegada: 600,
                                 longitudPaso: 300, tiempoViaje: 754, distanciaRecorrida: 9_000,
                                 maniobraLuego: .rotonda, modificadorLuego: 2, anguloLuego: -45, distanciaLuego: 120)
        let bytes = mensaje.codificar()
        XCTAssertEqual(bytes, [
            0x01, 0x12, 0x01, 0x02, 0x00,
            0x50, 0x00, 0x5A, 0x00,
            0xC8, 0x00, 0x04, 0x00, 0x58, 0x02, 0x2C, 0x01,
            0xF2, 0x02, 0x00, 0x00, 0x28, 0x23, 0x00, 0x00,
            0x03, 0x02, 0xD3, 0xFF, 0x78, 0x00,
        ])
        XCTAssertEqual(MensajeNav.decodificar(bytes), mensaje)
        // Lo que admita la conexión (§2): 31 bytes, todo; con 32 o más, el
        // byte de carriles detrás (v0.12; aquí, sin carriles); de 25 a 30,
        // sin el «y luego»; menos de 25, los 17 de la v0.6
        XCTAssertEqual(mensaje.codificar(maximo: 31), bytes)
        XCTAssertEqual(mensaje.codificar(maximo: 182), bytes + [0x00])
        XCTAssertEqual(mensaje.codificar(maximo: 30), Array(bytes.prefix(25)))
        XCTAssertEqual(mensaje.codificar(maximo: 25), Array(bytes.prefix(25)))
        XCTAssertEqual(mensaje.codificar(maximo: 24), Array(bytes.prefix(17)))
        XCTAssertEqual(mensaje.codificar(maximo: 20), Array(bytes.prefix(17)))
        // Con 25 a 30 bytes no hay maniobra luego; el resto se lee igual
        let sinElLuego = MensajeNav.decodificar(Array(bytes.prefix(30)))
        XCTAssertEqual(sinElLuego?.maniobraLuego, .desconocida)
        XCTAssertEqual(sinElLuego?.modificadorLuego, 0)
        XCTAssertNil(sinElLuego?.anguloLuego)
        XCTAssertNil(sinElLuego?.distanciaLuego)
        XCTAssertEqual(sinElLuego?.tiempoViaje, 754)
        XCTAssertEqual(sinElLuego?.distanciaRecorrida, 9_000)
        // Con un byte de más, se ignora
        XCTAssertEqual(MensajeNav.decodificar(bytes + [0x99]), mensaje)
    }

    func testNavLuegoSatura() {
        // La distancia se satura en 65 534 y el ángulo en ±180, como los de la
        // siguiente maniobra; lo que no es finito, desconocido
        let saturado = MensajeNav(secuencia: 0, banderas: [.rutaActiva], maniobraLuego: .giro, anguloLuego: 200,
                                  distanciaLuego: 70_000).codificar()
        XCTAssertEqual(Array(saturado[25...30]), [0x02, 0x00, 0xB4, 0x00, 0xFE, 0xFF])
        let otro = MensajeNav(secuencia: 0, banderas: [.rutaActiva], maniobraLuego: .giro, anguloLuego: -400,
                              distanciaLuego: .nan).codificar()
        XCTAssertEqual(Array(otro[25...30]), [0x02, 0x00, 0x4C, 0xFF, 0xFF, 0xFF])
        // Un código de luego que no está en la tabla se lee como desconocido
        var raro = MensajeNav(secuencia: 0, banderas: [.rutaActiva]).codificar()
        raro[25] = 0x09
        XCTAssertEqual(MensajeNav.decodificar(raro)?.maniobraLuego, .desconocida)
    }

    func testNavSinResumenParaComparar() {
        // El enlace mira si NAV ha cambiado sin el resumen del viaje (el
        // tiempo cambia cada segundo), pero con el «y luego»
        let antes = MensajeNav(secuencia: 0, banderas: [.rutaActiva], maniobra: .giro, distancia: 80,
                               tiempoViaje: 10, distanciaRecorrida: 100)
        var despues = antes
        despues.tiempoViaje = 11
        despues.distanciaRecorrida = 120
        XCTAssertEqual(antes.codificarSinResumen(), despues.codificarSinResumen())
        XCTAssertEqual(antes.codificarSinResumen().count, MensajeNav.longitudConCarriles)
        XCTAssertEqual(Array(antes.codificarSinResumen()[17...24]), sinResumen)
        despues.maniobraLuego = .recto
        despues.anguloLuego = 0
        despues.distanciaLuego = 40
        XCTAssertNotEqual(antes.codificarSinResumen(), despues.codificarSinResumen())
    }

    func testNavConCarriles() {
        // Carriles (v0.12, docs/vectores/mensajes.md): el mensaje de
        // testNavConLuego con cuatro carriles: recto, recto, recto o ligera
        // a la derecha (vale la ligera) y ligera a la derecha (vale)
        let carriles = [
            Carril(direcciones: .recto),
            Carril(direcciones: .recto),
            Carril(direcciones: [.recto, .ligeraDerecha], validas: .ligeraDerecha),
            Carril(direcciones: .ligeraDerecha, validas: .ligeraDerecha),
        ]
        let mensaje = MensajeNav(secuencia: 0x12, banderas: [.rutaActiva], maniobra: .giro, distancia: 80,
                                 angulo: 90, distanciaRestante: 2_000, tiempoRestante: 240, horaLlegada: 600,
                                 longitudPaso: 300, tiempoViaje: 754, distanciaRecorrida: 9_000,
                                 maniobraLuego: .rotonda, modificadorLuego: 2, anguloLuego: -45, distanciaLuego: 120,
                                 carriles: carriles)
        let v011: [UInt8] = [
            0x01, 0x12, 0x01, 0x02, 0x00,
            0x50, 0x00, 0x5A, 0x00,
            0xC8, 0x00, 0x04, 0x00, 0x58, 0x02, 0x2C, 0x01,
            0xF2, 0x02, 0x00, 0x00, 0x28, 0x23, 0x00, 0x00,
            0x03, 0x02, 0xD3, 0xFF, 0x78, 0x00,
        ]
        let bytes = mensaje.codificar(maximo: 182)
        XCTAssertEqual(bytes, v011 + [0x04, 0x01, 0x01, 0x03, 0x02, 0x00, 0x00, 0x02, 0x02])
        XCTAssertEqual(MensajeNav.decodificar(bytes), mensaje)
        // Sin decir el máximo, los 31 de la v0.11 (la placa sin el bit 11)
        XCTAssertEqual(mensaje.codificar(), v011)
        // Justo lo que ocupan, todo; con menos (pero 32 o más), sin carriles
        XCTAssertEqual(mensaje.codificar(maximo: 40), bytes)
        XCTAssertEqual(mensaje.codificar(maximo: 39), v011 + [0x00])
        XCTAssertEqual(mensaje.codificar(maximo: 32), v011 + [0x00])
        // Sin carriles, 32 bytes
        var sin = mensaje
        sin.carriles = []
        XCTAssertEqual(sin.codificar(maximo: 182), v011 + [0x00])
        XCTAssertEqual(MensajeNav.decodificar(v011 + [0x00]), sin)
        // Más de 8: no se mandan
        var muchos = mensaje
        muchos.carriles = Array(repeating: Carril(direcciones: .recto), count: 9)
        XCTAssertEqual(muchos.codificar(maximo: 182), v011 + [0x00])
        // Cortado a medias o con un número imposible: sin carriles; el resto
        // se lee igual
        XCTAssertEqual(MensajeNav.decodificar(Array(bytes.prefix(39)))?.carriles, [])
        XCTAssertEqual(MensajeNav.decodificar(Array(bytes.prefix(39)))?.distanciaLuego, 120)
        XCTAssertEqual(MensajeNav.decodificar(v011 + [0x09] + Array(repeating: 0x01, count: 18))?.carriles, [])
        // Los carriles cuentan como cambio
        XCTAssertNotEqual(mensaje.codificarSinResumen(), sin.codificarSinResumen())
    }

    func testCarrilDesdeOSRM() {
        // Como los da Valhalla (comprobado el 2026-10-10 con una salida de
        // autovía): el carril que vale, con su dirección activa
        XCTAssertEqual(Carril(osrmActivo: true, direcciones: ["straight", "right"], activa: "right"),
                       Carril(direcciones: [.recto, .derecha], validas: .derecha))
        // El que no vale, sin nada resaltado
        XCTAssertEqual(Carril(osrmActivo: false, direcciones: ["straight"], activa: nil),
                       Carril(direcciones: .recto))
        // Vale sin dirección activa, o con una que no es suya: todas las suyas
        XCTAssertEqual(Carril(osrmActivo: true, direcciones: ["left"], activa: nil),
                       Carril(direcciones: .izquierda, validas: .izquierda))
        XCTAssertEqual(Carril(osrmActivo: true, direcciones: ["left", "uturn"], activa: "right"),
                       Carril(direcciones: [.izquierda, .cambioDeSentido], validas: [.izquierda, .cambioDeSentido]))
        // «none» y lo desconocido, sin flechas
        XCTAssertEqual(Carril(osrmActivo: false, direcciones: ["none", "merge to left"], activa: nil),
                       Carril(direcciones: []))
        XCTAssertEqual(DireccionesCarril(osrm: "sharp left"), .fuerteIzquierda)
        XCTAssertEqual(DireccionesCarril(osrm: "slight left").rawValue, 0x20)
    }

    func testNavDecodificaElFormatoCorto() {
        // 9 bytes (antes de la v0.6): recto a 100 m; lo de la v0.6, desconocido
        XCTAssertEqual(MensajeNav.decodificar([0x01, 0x05, 0x01, 0x01, 0x00, 0x64, 0x00, 0x00, 0x00]),
                       MensajeNav(secuencia: 5, banderas: [.rutaActiva], maniobra: .recto, distancia: 100, angulo: 0))
        // 16 bytes: tampoco están los campos de la v0.6
        let giro: [UInt8] = [0x01, 0x10, 0x01, 0x02, 0x00, 0x5E, 0x01, 0x5A, 0x00,
                             0xD2, 0x04, 0x0F, 0x00, 0x65, 0x04, 0x20, 0x03]
        let corto = MensajeNav.decodificar(Array(giro.prefix(16)))
        XCTAssertEqual(corto?.distancia, 350)
        XCTAssertNil(corto?.distanciaRestante)
        XCTAssertNil(corto?.horaLlegada)
        // Con un byte de más, se ignora
        XCTAssertEqual(MensajeNav.decodificar(giro + [0x99])?.longitudPaso, 800)
    }

    func testNavDecodificaDesconocidos() {
        let sinRuta = MensajeNav.decodificar([0x01, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x7F,
                                              0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(sinRuta, MensajeNav(secuencia: 0, banderas: []))
        // Un código que no está en la tabla se lee como desconocido
        XCTAssertEqual(MensajeNav.decodificar([0x01, 0x05, 0x01, 0x09, 0x00, 0x64, 0x00, 0x00, 0x00])?.maniobra,
                       .desconocida)
    }

    func testNavDescartaLoInvalido() {
        XCTAssertNil(MensajeNav.decodificar([0x01, 0x05, 0x01, 0x01, 0x00, 0x64, 0x00, 0x00]))
        XCTAssertNil(MensajeNav.decodificar([0x02, 0x05, 0x01, 0x01, 0x00, 0x64, 0x00, 0x00, 0x00]))
    }

    func testAnguloDeRotonda() {
        // Por la derecha: 180 menos los grados recorridos
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 90), 90)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 180), 0)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 270), -90)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 360), -180)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 0), 180)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 450), 90)
        // Por la izquierda (rotondas en el sentido de las agujas del reloj)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 90, porLaDerecha: false), -90)
        XCTAssertEqual(CodigoManiobra.anguloRotonda(grados: 270, porLaDerecha: false), 90)
    }

    // MARK: GPS

    func testGPSCodifica() {
        let mensaje = MensajeGPS(secuencia: 3, edad: 0.4, altitud: 712, precisionVertical: 6.2,
                                 velocidad: 13.89, rumbo: 271.5, precisionHorizontal: 4.7)
        XCTAssertEqual(mensaje.codificar(), [0x01, 0x03, 0x0F, 0x04, 0xC8, 0x02, 0x06, 0x6D, 0x05, 0x0E, 0x6A, 0x05])
        // Sin posición, en segundo plano
        XCTAssertEqual(MensajeGPS(secuencia: 0, enSegundoPlano: true).codificar(),
                       [0x01, 0x00, 0x10, 0xFF, 0x00, 0x80, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    func testGPSSaturaYDecodifica() {
        // Edad de más de 25,4 s y precisión de más de 254 m: saturan; altitud negativa
        let bytes = MensajeGPS(secuencia: 9, edad: 60, altitud: -12, precisionHorizontal: 900).codificar()
        XCTAssertEqual(bytes[3], 254)
        XCTAssertEqual(bytes[11], 254)
        XCTAssertEqual(Array(bytes[4...5]), [0xF4, 0xFF])
        let leido = MensajeGPS.decodificar(bytes)
        XCTAssertEqual(leido?.edad, 25.4)
        XCTAssertEqual(leido?.altitud, -12)
        XCTAssertEqual(leido?.precisionHorizontal, 254)
        XCTAssertNil(leido?.velocidad)
        XCTAssertEqual(leido?.enSegundoPlano, false)
        XCTAssertNil(MensajeGPS.decodificar(Array(bytes.prefix(11))))
    }

    // MARK: TRAZO

    func testTrazoSinTramo() {
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: [], giro: nil).codificar(), [0x01, 0x05, 0x00, 0xFF])
        // Un solo punto no es un tramo
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: [PuntoPlano(x: 0, y: 0)], giro: 0).codificar(),
                       [0x01, 0x05, 0x00, 0xFF])
    }

    func testTrazoCodifica() {
        let mensaje = MensajeTrazo(
            secuencia: 2,
            puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 100), PuntoPlano(x: -30, y: 150.4)],
            giro: 1
        )
        XCTAssertEqual(mensaje.codificar(), [
            0x01, 0x02, 0x01, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x64, 0x00,
            0xE2, 0xFF, 0x96, 0x00,
        ])
    }

    func testTrazoSaturaYRecorta() {
        let lejos = MensajeTrazo(secuencia: 0, puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 40_000, y: -40_000)], giro: nil)
        XCTAssertEqual(Array(lejos.codificar().suffix(4)), [0xFF, 0x7F, 0x01, 0x80])
        let muchos = (0..<60).map { PuntoPlano(x: 0, y: Double($0) * 10) }
        XCTAssertEqual(MensajeTrazo(secuencia: 0, puntos: muchos, giro: 50).codificar().count, 180)
        // Con el MTU mínimo (20 bytes), 4 puntos; el giro fuera de ellos no se manda
        let corto = MensajeTrazo(secuencia: 0, puntos: muchos, giro: 10).codificar(maximo: 20)
        XCTAssertEqual(corto.count, 20)
        XCTAssertEqual(corto[3], 0xFF)
    }

    func testTrazoDecodifica() {
        let original = MensajeTrazo(secuencia: 7, puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: -30, y: 150)], giro: 1)
        XCTAssertEqual(MensajeTrazo.decodificar(original.codificar()), original)
        XCTAssertEqual(MensajeTrazo.decodificar([0x01, 0x05, 0x00, 0xFF]), MensajeTrazo(secuencia: 5, puntos: [], giro: nil))
        XCTAssertNil(MensajeTrazo.decodificar([0x01, 0x05, 0x00]))
        XCTAssertNil(MensajeTrazo.decodificar([0x02, 0x05, 0x00, 0xFF]))
    }

    func testTrazoConEscala() {
        // Bits 1-2 de los flags (v0.6): 3 = 1000 m da 0x07; 1 = 250 m, 0x03
        let puntos = [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 100), PuntoPlano(x: -30, y: 150.4)]
        XCTAssertEqual(MensajeTrazo(secuencia: 2, puntos: puntos, giro: 1, escala: 3).codificar(), [
            0x01, 0x02, 0x07, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x64, 0x00,
            0xE2, 0xFF, 0x96, 0x00,
        ])
        XCTAssertEqual(MensajeTrazo(secuencia: 2, puntos: puntos, giro: 1, escala: 1).codificar()[2], 0x03)
        XCTAssertEqual(MensajeTrazo(secuencia: 2, puntos: puntos, giro: 1, escala: 2).codificar()[2], 0x05)
        // Más de 3 va como 3; sin tramo, los flags a cero
        XCTAssertEqual(MensajeTrazo(secuencia: 2, puntos: puntos, giro: 1, escala: 9).codificar()[2], 0x07)
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: [], giro: nil, escala: 2).codificar(), [0x01, 0x05, 0x00, 0xFF])
    }

    func testTrazoDecodificaLaEscala() {
        let bytes: [UInt8] = [0x01, 0x02, 0x05, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00]
        XCTAssertEqual(MensajeTrazo.decodificar(bytes),
                       MensajeTrazo(secuencia: 2, puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 100)],
                                    giro: 1, escala: 2))
        // Sin tramo no hay escala
        XCTAssertEqual(MensajeTrazo.decodificar([0x01, 0x05, 0x04, 0xFF])?.escala, 0)
        let original = MensajeTrazo(secuencia: 9, puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 12, y: 900)],
                                    giro: nil, escala: 3)
        XCTAssertEqual(MensajeTrazo.decodificar(original.codificar()), original)
    }

    // MARK: TRAZO con movimiento (v0.9)

    /// Dos por detrás, la moto y dos por delante; el giro, en el primero de
    /// delante tras la moto (índice 3 de la lista entera).
    private let conMovimiento = MensajeTrazo(
        secuencia: 3,
        puntos: [PuntoPlano(x: 0, y: -120), PuntoPlano(x: -5, y: -60), PuntoPlano(x: 0, y: 0),
                 PuntoPlano(x: 0, y: 100), PuntoPlano(x: -30, y: 150)],
        giro: 3, escala: 2, movimiento: true, recorrido: 1_234.5, atras: 2
    )

    func testTrazoConMovimientoCodifica() {
        // Flags 0x0D: tramo, escala 2 y bit 3; recorrido 12 345 dm; 2 detrás
        XCTAssertEqual(conMovimiento.codificar(), [
            0x01, 0x03, 0x0D, 0x03,
            0x39, 0x30, 0x00, 0x00,
            0x02,
            0x00, 0x00, 0x88, 0xFF,
            0xFB, 0xFF, 0xC4, 0xFF,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x64, 0x00,
            0xE2, 0xFF, 0x96, 0x00,
        ])
        // Al principio de la ruta: nada detrás, recorrido 0, escala 3
        let alSalir = MensajeTrazo(secuencia: 0, puntos: [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 250)],
                                   giro: 1, escala: 3, movimiento: true, recorrido: 0, atras: 0)
        XCTAssertEqual(alSalir.codificar(), [
            0x01, 0x00, 0x0F, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFA, 0x00,
        ])
        // 123 456,7 m son 1 234 567 dm (0x0012D687); sin giro, escala 1
        let lejos = MensajeTrazo(secuencia: 16,
                                 puntos: [PuntoPlano(x: 3, y: -40), PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 312)],
                                 giro: nil, escala: 1, movimiento: true, recorrido: 123_456.7, atras: 1)
        XCTAssertEqual(lejos.codificar(), [
            0x01, 0x10, 0x0B, 0xFF, 0x87, 0xD6, 0x12, 0x00, 0x01,
            0x03, 0x00, 0xD8, 0xFF,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x38, 0x01,
        ])
    }

    func testTrazoConMovimientoSaturaElRecorrido() {
        func recorrido(_ metros: Double) -> [UInt8] {
            var mensaje = conMovimiento
            mensaje.recorrido = metros
            return Array(mensaje.codificar()[4...7])
        }
        XCTAssertEqual(recorrido(1e12), [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(recorrido(429_496_729.5), [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(recorrido(-5), [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(recorrido(.nan), [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(recorrido(0.04), [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(recorrido(0.05), [0x01, 0x00, 0x00, 0x00])
    }

    func testTrazoConMovimientoRecortaDejandoLosDeDelante() {
        // Con 20 bytes caben 2 puntos (9 de cabecera): la moto y el primero de
        // delante; ninguno de detrás. El giro pasa del 3 al 1
        XCTAssertEqual(MensajeTrazo.puntosQueCaben(20, movimiento: true), 2)
        XCTAssertEqual(conMovimiento.codificar(maximo: 20), [
            0x01, 0x03, 0x0D, 0x01, 0x39, 0x30, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x64, 0x00,
        ])
        // Con 25, 4 puntos: los 3 de delante y el de detrás más cercano
        let cuatro = conMovimiento.codificar(maximo: 25)
        XCTAssertEqual(cuatro.count, 25)
        XCTAssertEqual(cuatro[3], 2)
        XCTAssertEqual(cuatro[8], 1)
        XCTAssertEqual(Array(cuatro[9...12]), [0xFB, 0xFF, 0xC4, 0xFF])
        // Como mucho 42 puntos (177 bytes); si no caben los de delante, no va
        // ninguno de detrás, y un giro que queda fuera va como 255
        XCTAssertEqual(MensajeTrazo.puntosQueCaben(177, movimiento: true), 42)
        XCTAssertEqual(MensajeTrazo.puntosQueCaben(512, movimiento: true), 42)
        XCTAssertEqual(MensajeTrazo.puntosQueCaben(8, movimiento: true), 0)
        let muchos = (0..<60).map { PuntoPlano(x: 0, y: Double($0 - 5) * 10) }
        let largo = MensajeTrazo(secuencia: 0, puntos: muchos, giro: 50, movimiento: true, recorrido: 10, atras: 5)
            .codificar()
        XCTAssertEqual(largo.count, 177)
        XCTAssertEqual(largo[8], 0)
        XCTAssertEqual(largo[3], 0xFF)
        // La moto, primera de la lista
        XCTAssertEqual(Array(largo[9...12]), [0x00, 0x00, 0x00, 0x00])
        // Más de 10 detrás: se quitan los más lejanos
        let detras = (0..<12).map { PuntoPlano(x: 0, y: Double($0 - 12) * 10) }
        let delante = [PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 100), PuntoPlano(x: 0, y: 200),
                       PuntoPlano(x: 0, y: 300)]
        let doce = MensajeTrazo(secuencia: 0, puntos: detras + delante, giro: 14, movimiento: true, recorrido: 10,
                                atras: 12).codificar()
        XCTAssertEqual(doce.count, 9 + 14 * 4)
        XCTAssertEqual(doce[8], 10)
        XCTAssertEqual(doce[3], 12)
        // El primero, el de -100 m
        XCTAssertEqual(Array(doce[9...12]), [0x00, 0x00, 0x9C, 0xFF])
    }

    func testTrazoConMovimientoSinTramo() {
        // Sin tramo, el mensaje de siempre, de 4 bytes
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: [], giro: nil, movimiento: true, recorrido: 50).codificar(),
                       [0x01, 0x05, 0x00, 0xFF])
        // La moto fuera de la lista, o sin nada más que ella
        let fuera = [PuntoPlano(x: 0, y: -50), PuntoPlano(x: 0, y: 0)]
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: fuera, giro: nil, movimiento: true, atras: 2).codificar(),
                       [0x01, 0x05, 0x00, 0xFF])
        XCTAssertEqual(MensajeTrazo(secuencia: 5, puntos: [PuntoPlano(x: 0, y: 0)], giro: nil, movimiento: true)
                        .codificar(), [0x01, 0x05, 0x00, 0xFF])
    }

    func testTrazoConMovimientoDecodifica() {
        XCTAssertEqual(MensajeTrazo.decodificar(conMovimiento.codificar()), conMovimiento)
        let lejos = MensajeTrazo(secuencia: 16,
                                 puntos: [PuntoPlano(x: 3, y: -40), PuntoPlano(x: 0, y: 0), PuntoPlano(x: 0, y: 312)],
                                 giro: nil, escala: 1, movimiento: true, recorrido: 123_456.7, atras: 1)
        XCTAssertEqual(MensajeTrazo.decodificar(lejos.codificar()), lejos)
        // Con el bit 3 y menos de 9 bytes: se descarta
        XCTAssertNil(MensajeTrazo.decodificar([0x01, 0x03, 0x0D, 0x03, 0x39, 0x30, 0x00, 0x00]))
        // Sin el bit 0: sin tramo, pero con el recorrido (1 m)
        XCTAssertEqual(MensajeTrazo.decodificar([0x01, 0x05, 0x08, 0xFF, 0x0A, 0x00, 0x00, 0x00, 0x00]),
                       MensajeTrazo(secuencia: 5, puntos: [], giro: nil, movimiento: true, recorrido: 1))
        // Un `atrás` que deja la moto fuera de los puntos: sin tramo
        XCTAssertEqual(MensajeTrazo.decodificar([0x01, 0x00, 0x09, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x02,
                                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00]),
                       MensajeTrazo(secuencia: 0, puntos: [], giro: nil, movimiento: true))
        // El formato de siempre se lee sin movimiento
        let antiguo = MensajeTrazo.decodificar([0x01, 0x02, 0x05, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00])
        XCTAssertEqual(antiguo?.movimiento, false)
        XCTAssertEqual(antiguo?.atras, 0)
        XCTAssertEqual(antiguo?.puntos.count, 2)
    }

    func testTrazoSinMovimientoNoCambia() {
        // Con movimiento a false, el recorrido y los de detrás no viajan: el
        // formato de siempre, con la lista tal cual
        var mensaje = conMovimiento
        mensaje.movimiento = false
        let bytes = mensaje.codificar()
        XCTAssertEqual(bytes.count, 4 + 5 * 4)
        XCTAssertEqual(Array(bytes[0...3]), [0x01, 0x03, 0x05, 0x03])
    }

    // MARK: CRUCES

    func testCrucesSinCalles() {
        XCTAssertEqual(MensajeCruces(secuencia: 0, trazo: 0, calles: []).codificar(), [0x01, 0x00, 0x00, 0x00])
    }

    func testCrucesCodifica() {
        // Un cruce a 120 m con una calle a cada lado y otro a (-15,4; 300,6)
        // con una calle hacia atrás a la izquierda (200/256 de vuelta)
        let mensaje = MensajeCruces(secuencia: 3, trazo: 7, calles: [
            CalleCruce(x: 0, y: 120, direccion: 64),
            CalleCruce(x: 0, y: 120, direccion: 192),
            CalleCruce(x: -15.4, y: 300.6, direccion: 200),
        ])
        XCTAssertEqual(mensaje.codificar(), [
            0x01, 0x03, 0x07, 0x03,
            0x00, 0x00, 0x78, 0x00, 0x40,
            0x00, 0x00, 0x78, 0x00, 0xC0,
            0xF1, 0xFF, 0x2D, 0x01, 0xC8,
        ])
    }

    func testCrucesSaturaYRecorta() {
        let lejos = MensajeCruces(secuencia: 0, trazo: 0, calles: [CalleCruce(x: 40_000, y: -40_000, direccion: 0)])
        XCTAssertEqual(Array(lejos.codificar().suffix(5)), [0xFF, 0x7F, 0x01, 0x80, 0x00])
        // Como mucho 35 calles (179 bytes)
        let muchas = (0..<40).map { CalleCruce(x: 0, y: Double($0), direccion: 0) }
        let todas = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas).codificar()
        XCTAssertEqual(todas.count, 179)
        XCTAssertEqual(todas[3], 35)
        // Con el MTU mínimo (20 bytes), 3 calles: las primeras (las más cercanas)
        let corto = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas).codificar(maximo: 20)
        XCTAssertEqual(corto.count, 19)
        XCTAssertEqual(corto[3], 3)
        XCTAssertEqual(Array(corto.suffix(5)), [0x00, 0x00, 0x02, 0x00, 0x00])
        XCTAssertEqual(MensajeCruces.callesQueCaben(512), 35)
        XCTAssertEqual(MensajeCruces.callesQueCaben(3), 0)
    }

    func testCrucesDecodifica() {
        let original = MensajeCruces(secuencia: 3, trazo: 7, calles: [
            CalleCruce(x: 0, y: 120, direccion: 64),
            CalleCruce(x: -15, y: 301, direccion: 200),
        ])
        XCTAssertEqual(MensajeCruces.decodificar(original.codificar()), original)
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x03, 0x07, 0x00]), MensajeCruces(secuencia: 3, trazo: 7, calles: []))
        // Dice 2 calles pero llega una entera: se lee esa
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x02, 0x00, 0x00, 0x0A, 0x00, 0x40, 0x01])?.calles,
                       [CalleCruce(x: 0, y: 10, direccion: 64)])
        // Lo que sobra tras las n calles, si no es un bloque de anillos entero
        // (v0.8), se ignora
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x0A, 0x00, 0x40, 0x99, 0x99,
                                                  0x99, 0x99, 0x99])?.calles,
                       [CalleCruce(x: 0, y: 10, direccion: 64)])
        XCTAssertNil(MensajeCruces.decodificar([0x01, 0x03, 0x07]))
        XCTAssertNil(MensajeCruces.decodificar([0x02, 0x03, 0x07, 0x00]))
    }

    // MARK: CRUCES con anillos (v0.8)

    func testCrucesConAnillosCodifica() {
        // Una calle en (0, 120) a la derecha y un anillo de 15,6 m (16) con el
        // centro en (-20, 150)
        let mensaje = MensajeCruces(secuencia: 3, trazo: 7, calles: [CalleCruce(x: 0, y: 120, direccion: 64)],
                                    anillos: [AnilloCruce(x: -20, y: 150, radio: 15.6)])
        XCTAssertEqual(mensaje.codificar(), [
            0x01, 0x03, 0x07, 0x01,
            0x00, 0x00, 0x78, 0x00, 0x40,
            0x01,
            0xEC, 0xFF, 0x96, 0x00, 0x10,
        ])
        // Sin anillos, como antes de la v0.8: acaba tras las calles
        XCTAssertEqual(MensajeCruces(secuencia: 3, trazo: 7, calles: [CalleCruce(x: 0, y: 120, direccion: 64)]).codificar(),
                       [0x01, 0x03, 0x07, 0x01, 0x00, 0x00, 0x78, 0x00, 0x40])
        // Solo anillos
        XCTAssertEqual(MensajeCruces(secuencia: 0, trazo: 2, calles: [],
                                     anillos: [AnilloCruce(x: 0, y: 40, radio: 8)]).codificar(),
                       [0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x28, 0x00, 0x08])
    }

    func testCrucesConAnillosRadio() {
        // El radio se redondea y se satura entre 1 y 255 m
        func radio(_ metros: Double) -> UInt8? {
            MensajeCruces(secuencia: 0, trazo: 0, calles: [], anillos: [AnilloCruce(x: 0, y: 0, radio: metros)])
                .codificar().last
        }
        XCTAssertEqual(radio(300), 0xFF)
        XCTAssertEqual(radio(254.6), 0xFF)
        XCTAssertEqual(radio(0.2), 0x01)
        XCTAssertEqual(radio(-5), 0x01)
        XCTAssertEqual(radio(.nan), 0x01)
        XCTAssertEqual(radio(12.4), 0x0C)
    }

    func testCrucesConAnillosNoPasaDe179() {
        let muchas = (0..<40).map { CalleCruce(x: 0, y: Double($0), direccion: 0) }
        let anillos = (0..<5).map { AnilloCruce(x: Double($0), y: 100, radio: 10) }
        // Con 4 anillos (como mucho), 30 calles: 4 + 150 + 1 + 20 = 175 bytes
        let cuatro = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas, anillos: anillos).codificar(maximo: 512)
        XCTAssertEqual(cuatro.count, 175)
        XCTAssertEqual(cuatro[3], 30)
        XCTAssertEqual(cuatro[154], 4)
        XCTAssertEqual(Array(cuatro.suffix(5)), [0x03, 0x00, 0x64, 0x00, 0x0A])
        // Con uno, 33 calles: 4 + 165 + 1 + 5 = 175
        let uno = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas, anillos: [anillos[0]]).codificar()
        XCTAssertEqual(uno.count, 175)
        XCTAssertEqual(uno[3], 33)
        XCTAssertEqual(uno[169], 1)
        // Con el MTU mínimo (20 bytes) y un anillo, 2 calles: las más cercanas
        let corto = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas, anillos: [anillos[0]]).codificar(maximo: 20)
        XCTAssertEqual(corto.count, 20)
        XCTAssertEqual(corto[3], 2)
        XCTAssertEqual(corto[14], 1)
        // Si no cabe ni un anillo, el mensaje acaba tras las calles
        let sinSitio = MensajeCruces(secuencia: 0, trazo: 0, calles: muchas, anillos: [anillos[0]]).codificar(maximo: 9)
        XCTAssertEqual(sinSitio.count, 9)
        XCTAssertEqual(sinSitio[3], 1)
        XCTAssertEqual(MensajeCruces.callesQueCaben(179, anillos: 4), 30)
        XCTAssertEqual(MensajeCruces.callesQueCaben(512, anillos: 9), 30)
        XCTAssertEqual(MensajeCruces.callesQueCaben(179, anillos: 1), 33)
        XCTAssertEqual(MensajeCruces.callesQueCaben(179), 35)
        XCTAssertEqual(MensajeCruces.callesQueCaben(20, anillos: 1), 2)
        XCTAssertEqual(MensajeCruces.anillosQueCaben(512), 4)
        XCTAssertEqual(MensajeCruces.anillosQueCaben(20), 3)
        XCTAssertEqual(MensajeCruces.anillosQueCaben(9), 0)
    }

    func testCrucesConAnillosDecodifica() {
        let original = MensajeCruces(secuencia: 3, trazo: 7, calles: [CalleCruce(x: 0, y: 120, direccion: 64)],
                                     anillos: [AnilloCruce(x: -20, y: 150, radio: 16), AnilloCruce(x: 5, y: 300, radio: 40)])
        XCTAssertEqual(MensajeCruces.decodificar(original.codificar()), original)
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x0A, 0x00, 0x40,
                                                  0x01, 0xEC, 0xFF, 0x96, 0x00, 0x10]),
                       MensajeCruces(secuencia: 0, trazo: 5, calles: [CalleCruce(x: 0, y: 10, direccion: 64)],
                                     anillos: [AnilloCruce(x: -20, y: 150, radio: 16)]))
        // Dice 9 anillos: se leen como mucho 4
        let nueve: [UInt8] = [0x01, 0x00, 0x05, 0x00, 0x09] + (0..<5).flatMap { _ in [0x00, 0x00, 0x0A, 0x00, 0x05] as [UInt8] }
        XCTAssertEqual(MensajeCruces.decodificar(nueve)?.anillos.count, 4)
        // Un anillo a medias no se lee
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x00, 0x01, 0xEC, 0xFF, 0x96, 0x00])?.anillos, [])
        // Si faltan calles, lo que sigue no se lee como anillos
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x02, 0x00, 0x00, 0x0A, 0x00, 0x40, 0x01])?.anillos,
                       [])
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

    func testDeviceInfoDelCuadroConTrazo() {
        let info = DeviceInfo.decodificar([0x01, 0x01, 0xEC, 0x00, 0x00, 0x00, 0x02, 0x00])
        XCTAssertEqual(info?.capacidades, [.status, .navText, .movil, .trazo, .movilAlCambiar])
        XCTAssertEqual(info?.firmware, [0, 2, 0])
    }

    func testDeviceInfoDelCuadroConNavYCruces() {
        // 0x01ED: NAV, STATUS, NAV_TEXT, MOVIL, TRAZO, MOVIL al cambiar y CRUCES
        let info = DeviceInfo.decodificar([0x01, 0x01, 0xED, 0x01, 0x00, 0x00, 0x03, 0x00])
        XCTAssertEqual(info?.capacidades, [.nav, .status, .navText, .movil, .trazo, .movilAlCambiar, .cruces])
        XCTAssertEqual(info?.capacidades.contains(.gps), false)
        // 0x01EF: el cuadro 0.3.0, también con GPS (v0.7)
        let conGPS = DeviceInfo.decodificar([0x01, 0x01, 0xEF, 0x01, 0x00, 0x00, 0x03, 0x00])
        XCTAssertEqual(conGPS?.capacidades, [.nav, .gps, .status, .navText, .movil, .trazo, .movilAlCambiar, .cruces])
    }

    func testDeviceInfoDelCuadroConAnillos() {
        // 0x03EF: el cuadro 0.4.0, también con los anillos (v0.8)
        let info = DeviceInfo.decodificar([0x01, 0x01, 0xEF, 0x03, 0x00, 0x00, 0x04, 0x00])
        XCTAssertEqual(info?.capacidades, [.nav, .gps, .status, .navText, .movil, .trazo, .movilAlCambiar, .cruces,
                                           .anillos])
        XCTAssertEqual(info?.firmware, [0, 4, 0])
        XCTAssertEqual(Capacidades.anillos.rawValue, 0x0200)
        XCTAssertEqual(info?.capacidades.contains(.movimiento), false)
    }

    func testDeviceInfoDelCuadroConMovimiento() {
        // 0x07EF: el cuadro 0.5.0, también con el movimiento (v0.9)
        let info = DeviceInfo.decodificar([0x01, 0x01, 0xEF, 0x07, 0x00, 0x00, 0x05, 0x00])
        XCTAssertEqual(info?.capacidades, [.nav, .gps, .status, .navText, .movil, .trazo, .movilAlCambiar, .cruces,
                                           .anillos, .movimiento])
        XCTAssertEqual(info?.firmware, [0, 5, 0])
        XCTAssertEqual(Capacidades.movimiento.rawValue, 0x0400)
    }

    func testDeviceInfoDescartaLoCorto() {
        XCTAssertNil(DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01]))
    }
}
