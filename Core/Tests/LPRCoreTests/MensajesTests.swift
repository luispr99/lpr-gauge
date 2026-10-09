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

    func testNavSinRuta() {
        XCTAssertEqual(MensajeNav(secuencia: 0, banderas: []).codificar(), [
            0x01, 0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFF, 0xFF, 0x7F,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ])
    }

    func testNavCodificaUnGiro() {
        // A la derecha (90) a 350 m; quedan 12 340 m y 15 min; llegada a las
        // 18:45 (1125); paso de 800 m
        let mensaje = MensajeNav(secuencia: 0x10, banderas: [.rutaActiva], maniobra: .giro, distancia: 350,
                                 angulo: 90, distanciaRestante: 12_340, tiempoRestante: 900, horaLlegada: 1125,
                                 longitudPaso: 800)
        XCTAssertEqual(mensaje.codificar(), [
            0x01, 0x10, 0x01, 0x02, 0x00,
            0x5E, 0x01, 0x5A, 0x00,
            0xD2, 0x04, 0x0F, 0x00, 0x65, 0x04, 0x20, 0x03,
        ])
        XCTAssertEqual(MensajeNav.decodificar(mensaje.codificar()), mensaje)
    }

    func testNavCodificaUnaRotondaRedondeando() {
        // Tercera salida, a la izquierda (-90), a 120,4 m; 5004 m van como 500
        // decenas y 389 s como 6 min; llegada a las 0:00; sin longitud del paso
        let mensaje = MensajeNav(secuencia: 0x11, banderas: [.rutaActiva], maniobra: .rotonda, modificador: 3,
                                 distancia: 120.4, angulo: -90, distanciaRestante: 5_004, tiempoRestante: 389,
                                 horaLlegada: 0, longitudPaso: nil)
        let bytes = mensaje.codificar()
        XCTAssertEqual(bytes, [
            0x01, 0x11, 0x01, 0x03, 0x03,
            0x78, 0x00, 0xA6, 0xFF,
            0xF4, 0x01, 0x06, 0x00, 0x00, 0x00, 0xFF, 0xFF,
        ])
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
        XCTAssertEqual(MensajeNav(secuencia: 0x20, banderas: [.llegada], maniobra: .llegada).codificar(), [
            0x01, 0x20, 0x08, 0x05, 0x00,
            0xFF, 0xFF, 0xFF, 0x7F,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ])
    }

    func testNavSatura() {
        let saturado = MensajeNav(secuencia: 0, banderas: [.rutaActiva], maniobra: .recto, distancia: 70_000,
                                  angulo: 200, distanciaRestante: 1_000_000, tiempoRestante: 10_000_000,
                                  horaLlegada: 1440, longitudPaso: -5)
        XCTAssertEqual(saturado.codificar(), [
            0x01, 0x00, 0x01, 0x01, 0x00,
            0xFE, 0xFF, 0xB4, 0x00,
            0xFE, 0xFF, 0xFE, 0xFF, 0xFF, 0xFF, 0x00, 0x00,
        ])
        // -400 se queda en -180 (0xFF4C); lo que no es finito, desconocido
        let otro = MensajeNav(secuencia: 0, banderas: [.rutaActiva], distancia: .infinity, angulo: -400,
                              distanciaRestante: .nan).codificar()
        XCTAssertEqual(Array(otro[5...10]), [0xFF, 0xFF, 0x4C, 0xFF, 0xFF, 0xFF])
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
        // Lo que sobra tras las n calles se ignora
        XCTAssertEqual(MensajeCruces.decodificar([0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x0A, 0x00, 0x40, 0x99, 0x99,
                                                  0x99, 0x99, 0x99])?.calles,
                       [CalleCruce(x: 0, y: 10, direccion: 64)])
        XCTAssertNil(MensajeCruces.decodificar([0x01, 0x03, 0x07]))
        XCTAssertNil(MensajeCruces.decodificar([0x02, 0x03, 0x07, 0x00]))
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
    }

    func testDeviceInfoDescartaLoCorto() {
        XCTAssertNil(DeviceInfo.decodificar([0x01, 0x02, 0x24, 0x00, 0x00, 0x00, 0x01]))
    }
}
