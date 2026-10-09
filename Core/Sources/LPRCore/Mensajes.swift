// Codificación y decodificación de los mensajes (docs/PROTOCOLO.md, v0.9).
// Reglas comunes (sección 3): little-endian, primer byte = versión, campos
// nuevos al final; el receptor ignora los bytes que sobran y descarta los
// mensajes cortos o con una versión que no conoce.

import Foundation

/// Número de secuencia por característica: empieza en 0 y da la vuelta de 255 a 0.
public struct Secuencia {
    public private(set) var proxima: UInt8 = 0

    public init() {}

    /// Devuelve la secuencia que toca y deja preparada la siguiente.
    public mutating func siguiente() -> UInt8 {
        let actual = proxima
        proxima = proxima &+ 1
        return actual
    }
}

// MARK: - Enteros de 16 bits (sección 3)

extension Array where Element == UInt8 {
    /// Añade un u16 (o un i16 con su patrón de bits) en little-endian.
    mutating func anadirU16(_ valor: UInt16) {
        append(UInt8(valor & 0xFF))
        append(UInt8(valor >> 8))
    }
}

/// El u16 en little-endian que empieza en `i`.
func leerU16(_ bytes: [UInt8], _ i: Int) -> UInt16 {
    UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
}

extension Array where Element == UInt8 {
    /// Añade un u32 en little-endian (TRAZO con movimiento, v0.9).
    mutating func anadirU32(_ valor: UInt32) {
        append(UInt8(valor & 0xFF))
        append(UInt8((valor >> 8) & 0xFF))
        append(UInt8((valor >> 16) & 0xFF))
        append(UInt8(valor >> 24))
    }
}

/// El u32 en little-endian que empieza en `i`.
func leerU32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
    let bajo = UInt32(leerU16(bytes, i))
    let alto = UInt32(leerU16(bytes, i + 2))
    return bajo | alto << 16
}

/// Un valor sin signo en u32 (el recorrido de TRAZO, v0.9): redondeado y
/// saturado entre 0 y 4 294 967 295; lo que no es finito, 0. El campo no tiene
/// valor de desconocido (§7 ter).
func u32Saturado(_ valor: Double) -> UInt32 {
    guard valor.isFinite else { return 0 }
    return UInt32(min(4_294_967_295, max(0, valor.rounded())))
}

/// Metros como i16 (TRAZO y CRUCES): redondeados al metro y saturados en
/// ±32 767; lo que no es finito, 0.
func metrosI16(_ valor: Double) -> UInt16 {
    let metros = valor.isFinite ? min(32_767, max(-32_767, valor.rounded())) : 0
    return UInt16(bitPattern: Int16(metros))
}

/// Un valor sin signo en u16 (NAV): redondeado y saturado entre 0 y 65 534;
/// sin dato o no finito, `0xFFFF` (desconocido).
func u16Saturado(_ valor: Double?) -> UInt16 {
    guard let valor, valor.isFinite else { return 0xFFFF }
    return UInt16(min(65_534, max(0, valor.rounded())))
}

// MARK: - NAV (sección 5) y códigos de maniobra (sección 8)

/// Código de maniobra del cuadro (§8, v0.6). La forma de la flecha la da el
/// ángulo de NAV.
public enum CodigoManiobra: UInt8 {
    /// Sin flecha.
    case desconocida = 0
    case recto = 1
    /// El ángulo dice a qué lado y cuánto.
    case giro = 2
    /// El modificador de NAV es el número de salida; el ángulo, la dirección
    /// de la salida.
    case rotonda = 3
    /// El signo del ángulo es el lado.
    case cambioDeSentido = 4
    case llegada = 5
    /// Inicio de la ruta.
    case salida = 6

    /// Dirección de la salida de una rotonda respecto a la de entrada (§5), de
    /// -180 a 180, positivo a la derecha, a partir de los grados que se
    /// recorren dentro (180: seguir recto). Circulando por la derecha la
    /// rotonda se recorre en sentido contrario a las agujas del reloj: 180
    /// menos los grados (90 recorridos: +90, a la derecha; 270: -90). Por la
    /// izquierda, al revés: los grados menos 180.
    public static func anguloRotonda(grados: Int, porLaDerecha: Bool = true) -> Int {
        var angulo = (porLaDerecha ? 180 - grados : grados - 180) % 360
        if angulo > 180 { angulo -= 360 }
        if angulo < -180 { angulo += 360 }
        return angulo
    }
}

/// Flags de NAV (byte 2).
public struct BanderasNav: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let rutaActiva   = BanderasNav(rawValue: 1 << 0)
    public static let recalculando = BanderasNav(rawValue: 1 << 1)
    public static let fueraDeRuta  = BanderasNav(rawValue: 1 << 2)
    public static let llegada      = BanderasNav(rawValue: 1 << 3)
}

/// La siguiente maniobra (§5). Los campos sin dato son nil y viajan como
/// «desconocido».
public struct MensajeNav: Equatable {
    public static let longitudMinima = 9
    /// Con los campos de la v0.6: si el mensaje es más corto, son desconocidos.
    public static let longitud = 17

    public var secuencia: UInt8
    public var banderas: BanderasNav
    public var maniobra: CodigoManiobra
    /// En rotondas, número de salida (1-n); si no, 0.
    public var modificador: UInt8
    /// Metros hasta la maniobra.
    public var distancia: Double?
    /// Grados, de -180 a 180, positivo a la derecha.
    public var angulo: Int?
    /// Metros hasta el destino; viajan en decenas de metros.
    public var distanciaRestante: Double?
    /// Segundos hasta el destino; viajan en minutos, redondeados.
    public var tiempoRestante: Double?
    /// Hora de llegada prevista, en minutos desde la medianoche (0-1439).
    public var horaLlegada: Int?
    /// Metros del paso actual entero, de la maniobra anterior a la siguiente.
    public var longitudPaso: Double?

    public init(
        secuencia: UInt8,
        banderas: BanderasNav,
        maniobra: CodigoManiobra = .desconocida,
        modificador: UInt8 = 0,
        distancia: Double? = nil,
        angulo: Int? = nil,
        distanciaRestante: Double? = nil,
        tiempoRestante: Double? = nil,
        horaLlegada: Int? = nil,
        longitudPaso: Double? = nil
    ) {
        self.secuencia = secuencia
        self.banderas = banderas
        self.maniobra = maniobra
        self.modificador = modificador
        self.distancia = distancia
        self.angulo = angulo
        self.distanciaRestante = distanciaRestante
        self.tiempoRestante = tiempoRestante
        self.horaLlegada = horaLlegada
        self.longitudPaso = longitudPaso
    }

    /// Siempre los 17 bytes de la v0.6. Las distancias y el tiempo se redondean
    /// y se saturan en 65 534; el ángulo, en ±180; una hora de llegada fuera
    /// de 0-1439 va como desconocida.
    public func codificar() -> [UInt8] {
        var bytes: [UInt8] = [Protocolo.version, secuencia, banderas.rawValue, maniobra.rawValue, modificador]
        bytes.anadirU16(u16Saturado(distancia))
        bytes.anadirU16(angulo.map { UInt16(bitPattern: Int16(min(180, max(-180, $0)))) } ?? 0x7FFF)
        bytes.anadirU16(u16Saturado(distanciaRestante.map { $0 / 10 }))
        bytes.anadirU16(u16Saturado(tiempoRestante.map { $0 / 60 }))
        bytes.anadirU16(horaLlegada.flatMap { hora -> UInt16? in
            (0...1439).contains(hora) ? UInt16(hora) : nil
        } ?? 0xFFFF)
        bytes.anadirU16(u16Saturado(longitudPaso))
        return bytes
    }

    /// Descarta lo corto y otra versión. Un código de maniobra que no conoce
    /// se lee como desconocido (supuesto: así una tabla más larga no hace
    /// descartar el mensaje entero).
    public static func decodificar(_ bytes: [UInt8]) -> MensajeNav? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        func valor(_ i: Int) -> Double? {
            let crudo = leerU16(bytes, i)
            return crudo == 0xFFFF ? nil : Double(crudo)
        }
        let angulo = Int16(bitPattern: leerU16(bytes, 7))
        var mensaje = MensajeNav(
            secuencia: bytes[1],
            banderas: BanderasNav(rawValue: bytes[2]),
            maniobra: CodigoManiobra(rawValue: bytes[3]) ?? .desconocida,
            modificador: bytes[4],
            distancia: valor(5),
            angulo: angulo == 0x7FFF ? nil : Int(angulo)
        )
        if bytes.count >= longitud {
            mensaje.distanciaRestante = valor(9).map { $0 * 10 }
            mensaje.tiempoRestante = valor(11).map { $0 * 60 }
            let hora = leerU16(bytes, 13)
            mensaje.horaLlegada = hora <= 1439 ? Int(hora) : nil
            mensaje.longitudPaso = valor(15)
        }
        return mensaje
    }
}

// MARK: - GPS (sección 6)

/// Un valor sin signo en u8 (GPS): redondeado y saturado entre 0 y 254; sin
/// dato o no finito, 255 (desconocido).
func u8Saturado(_ valor: Double?) -> UInt8 {
    guard let valor, valor.isFinite else { return 255 }
    return UInt8(min(254, max(0, valor.rounded())))
}

/// Estado del GPS del móvil (§6). Definido desde la v0.1 e implementado en la
/// v0.7 (2026-10-09), para el indicador de calidad del cuadro (a petición del
/// autor). iOS no da los satélites ni la señal: la calidad es la precisión
/// horizontal que estima.
public struct MensajeGPS: Equatable {
    public static let longitudMinima = 12

    public var secuencia: UInt8
    /// Segundos desde que se tomó la posición; nil sin posición.
    public var edad: Double?
    /// Metros sobre el nivel del mar.
    public var altitud: Double?
    public var precisionVertical: Double?
    /// Metros por segundo.
    public var velocidad: Double?
    /// Grados desde el norte verdadero, en sentido horario.
    public var rumbo: Double?
    /// Metros: el radio en el que iOS cree que está la posición.
    public var precisionHorizontal: Double?
    public var enSegundoPlano: Bool

    public init(secuencia: UInt8, edad: Double? = nil, altitud: Double? = nil, precisionVertical: Double? = nil,
                velocidad: Double? = nil, rumbo: Double? = nil, precisionHorizontal: Double? = nil,
                enSegundoPlano: Bool = false) {
        self.secuencia = secuencia
        self.edad = edad
        self.altitud = altitud
        self.precisionVertical = precisionVertical
        self.velocidad = velocidad
        self.rumbo = rumbo
        self.precisionHorizontal = precisionHorizontal
        self.enSegundoPlano = enSegundoPlano
    }

    /// Los 12 bytes. El fix es válido (bit 0) con edad y precisión
    /// horizontal; cada dato que falta va con su valor de desconocido.
    public func codificar() -> [UInt8] {
        var flags: UInt8 = 0
        if edad != nil && precisionHorizontal != nil { flags |= 0x01 }
        if altitud != nil { flags |= 0x02 }
        if velocidad != nil { flags |= 0x04 }
        if rumbo != nil { flags |= 0x08 }
        if enSegundoPlano { flags |= 0x10 }
        var bytes: [UInt8] = [Protocolo.version, secuencia, flags, u8Saturado(edad.map { $0 * 10 })]
        bytes.anadirU16(altitud.flatMap { metros -> UInt16? in
            guard metros.isFinite else { return nil }
            return UInt16(bitPattern: Int16(min(32_767, max(-32_767, metros.rounded()))))
        } ?? 0x8000)
        bytes.append(u8Saturado(precisionVertical))
        bytes.anadirU16(u16Saturado(velocidad.map { $0 * 100 }))
        bytes.anadirU16(u16Saturado(rumbo.map { grados -> Double in
            let normal = grados.truncatingRemainder(dividingBy: 360)
            return (normal < 0 ? normal + 360 : normal) * 100
        }))
        bytes.append(u8Saturado(precisionHorizontal))
        return bytes
    }

    public static func decodificar(_ bytes: [UInt8]) -> MensajeGPS? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        let altitud = leerU16(bytes, 4)
        let velocidad = leerU16(bytes, 7)
        let rumbo = leerU16(bytes, 9)
        return MensajeGPS(
            secuencia: bytes[1],
            edad: bytes[3] == 255 ? nil : Double(bytes[3]) / 10,
            altitud: altitud == 0x8000 ? nil : Double(Int16(bitPattern: altitud)),
            precisionVertical: bytes[6] == 255 ? nil : Double(bytes[6]),
            velocidad: velocidad == 0xFFFF ? nil : Double(velocidad) / 100,
            rumbo: rumbo == 0xFFFF ? nil : Double(rumbo) / 100,
            precisionHorizontal: bytes[11] == 255 ? nil : Double(bytes[11]),
            enSegundoPlano: bytes[2] & 0x10 != 0
        )
    }
}

// MARK: - MOVIL (sección 7)

public enum EstadoBateria: UInt8 {
    case desconocido = 0
    case sinCargar = 1
    case cargando = 2
    case cargada = 3
}

public struct MensajeMovil: Equatable {
    public static let longitudMinima = 4

    public var secuencia: UInt8
    public var estado: EstadoBateria
    /// Porcentaje de 0 a 100, o nil si no se conoce.
    public var nivel: UInt8?

    public init(secuencia: UInt8, estado: EstadoBateria, nivel: UInt8?) {
        self.secuencia = secuencia
        self.estado = estado
        self.nivel = nivel.map { min($0, 100) }
    }

    public func codificar() -> [UInt8] {
        [Protocolo.version, secuencia, estado.rawValue, nivel.map { min($0, 100) } ?? 255]
    }

    public static func decodificar(_ bytes: [UInt8]) -> MensajeMovil? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version,
              let estado = EstadoBateria(rawValue: bytes[2]) else { return nil }
        let nivel: UInt8? = bytes[3] == 255 ? nil : min(bytes[3], 100)
        return MensajeMovil(secuencia: bytes[1], estado: estado, nivel: nivel)
    }
}

// MARK: - NAV_TEXT (sección 7 bis)

public struct MensajeNavText: Equatable {
    public static let longitudMinima = 2
    /// Como mucho: 2 bytes de cabecera y 180 de texto.
    public static let longitudMaxima = 182

    public var secuencia: UInt8
    /// UTF-8; vacío: no hay texto que mostrar.
    public var texto: String

    public init(secuencia: UInt8, texto: String) {
        self.secuencia = secuencia
        self.texto = texto
    }

    /// Bytes del mensaje, sin pasar de `maximo` (lo que admite la conexión) ni de
    /// `longitudMaxima`. Si el texto no cabe, se corta sin partir un carácter
    /// UTF-8.
    public func codificar(maximo: Int = longitudMaxima) -> [UInt8] {
        let caben = max(Self.longitudMinima, min(maximo, Self.longitudMaxima)) - Self.longitudMinima
        var utf8 = Array(texto.utf8)
        if utf8.count > caben {
            var corte = caben
            // El primer byte que se queda fuera no puede ser la continuación de
            // un carácter (10xxxxxx): se retrocede hasta el principio de ese carácter
            while corte > 0 && utf8[corte] & 0xC0 == 0x80 {
                corte -= 1
            }
            utf8 = Array(utf8[0..<corte])
        }
        return [Protocolo.version, secuencia] + utf8
    }

    /// Descarta lo corto, otra versión y un texto que no sea UTF-8 válido.
    public static func decodificar(_ bytes: [UInt8]) -> MensajeNavText? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version,
              let texto = String(bytes: bytes[2...], encoding: .utf8) else { return nil }
        return MensajeNavText(secuencia: bytes[1], texto: texto)
    }
}

// MARK: - STATUS (sección 9)

public struct MensajeStatus: Equatable {
    public static let longitudMinima = 4

    public var ecoNav: UInt8
    public var ecoGPS: UInt8
    public var pideReenvio: Bool
    /// nil si el dispositivo es anterior a la v0.2 (STATUS de 4 bytes).
    public var ecoMovil: UInt8?
    /// nil si el dispositivo es anterior a la v0.3 (STATUS de menos de 6 bytes).
    public var ecoNavText: UInt8?
    /// nil si el dispositivo es anterior a la v0.4 (STATUS de menos de 7 bytes).
    public var ecoTrazo: UInt8?
    /// nil si el dispositivo es anterior a la v0.6 (STATUS de menos de 8 bytes).
    public var ecoCruces: UInt8?

    public init(ecoNav: UInt8, ecoGPS: UInt8, pideReenvio: Bool, ecoMovil: UInt8?,
                ecoNavText: UInt8? = nil, ecoTrazo: UInt8? = nil, ecoCruces: UInt8? = nil) {
        self.ecoNav = ecoNav
        self.ecoGPS = ecoGPS
        self.pideReenvio = pideReenvio
        self.ecoMovil = ecoMovil
        self.ecoNavText = ecoMovil == nil ? nil : ecoNavText
        self.ecoTrazo = self.ecoNavText == nil ? nil : ecoTrazo
        self.ecoCruces = self.ecoTrazo == nil ? nil : ecoCruces
    }

    public func codificar() -> [UInt8] {
        var bytes: [UInt8] = [Protocolo.version, ecoNav, ecoGPS, pideReenvio ? 0x01 : 0x00]
        if let ecoMovil {
            bytes.append(ecoMovil)
            if let ecoNavText {
                bytes.append(ecoNavText)
                if let ecoTrazo {
                    bytes.append(ecoTrazo)
                    if let ecoCruces { bytes.append(ecoCruces) }
                }
            }
        }
        return bytes
    }

    public static func decodificar(_ bytes: [UInt8]) -> MensajeStatus? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        return MensajeStatus(
            ecoNav: bytes[1],
            ecoGPS: bytes[2],
            pideReenvio: bytes[3] & 0x01 != 0,
            ecoMovil: bytes.count >= 5 ? bytes[4] : nil,
            ecoNavText: bytes.count >= 6 ? bytes[5] : nil,
            ecoTrazo: bytes.count >= 7 ? bytes[6] : nil,
            ecoCruces: bytes.count >= 8 ? bytes[7] : nil
        )
    }
}

// MARK: - TRAZO (sección 7 ter)

public struct MensajeTrazo: Equatable {
    public static let longitudMinima = 4
    /// Como mucho: 4 bytes de cabecera y 44 puntos de 4 bytes (180 bytes).
    public static let maximoPuntos = 44
    /// Con movimiento (v0.9): 9 bytes de cabecera (versión, secuencia, flags,
    /// giro, recorrido en u32 y cuántos puntos van detrás)…
    public static let longitudMinimaMovimiento = 9
    /// …y como mucho 42 puntos (177 bytes)…
    public static let maximoPuntosMovimiento = 42
    /// …de los que como mucho 10 van por detrás de la moto.
    public static let maximoAtras = 10
    /// Bit 3 de los flags: formato con movimiento (v0.9).
    static let banderaMovimiento: UInt8 = 0x08

    public var secuencia: UInt8
    /// Metros en los ejes de la moto (Trazo); con menos de dos, no hay tramo.
    /// Con movimiento, primero los `atras` de detrás (del más lejano al más
    /// cercano), después la moto, (0, 0), y después los de delante.
    public var puntos: [PuntoPlano]
    /// Índice del próximo giro en `puntos` (con movimiento, contando los de
    /// detrás), o nil.
    public var giro: Int?
    /// Escala (v0.6, bits 1-2 de los flags): 0 la ajusta el dispositivo al
    /// tramo; 1 = 250 m, 2 = 500 m y 3 = 1000 m desde la moto hasta el borde de
    /// arriba del dibujo (Trazo.nivel).
    public var escala: UInt8
    /// Formato con movimiento (v0.9, bit 3 de los flags): solo para un
    /// dispositivo que anuncie el bit 10 de capacidades.
    public var movimiento: Bool
    /// Con movimiento: metros de ruta desde su inicio hasta la moto; viajan en
    /// decímetros. Sin movimiento no viaja (0).
    public var recorrido: Double
    /// Con movimiento: cuántos puntos de `puntos` van por detrás de la moto (la
    /// moto está en ese índice). Sin movimiento, 0.
    public var atras: Int

    public init(secuencia: UInt8, puntos: [PuntoPlano], giro: Int?, escala: UInt8 = 0,
                movimiento: Bool = false, recorrido: Double = 0, atras: Int = 0) {
        self.secuencia = secuencia
        self.puntos = puntos
        self.giro = giro
        self.escala = escala
        self.movimiento = movimiento
        self.recorrido = recorrido
        self.atras = atras
    }

    /// Cuántos puntos caben en `maximo` bytes (lo que admite la conexión), sin
    /// pasar de 44; con movimiento (v0.9), con 9 bytes de cabecera y sin pasar
    /// de 42.
    public static func puntosQueCaben(_ maximo: Int, movimiento: Bool = false) -> Int {
        if movimiento {
            return max(0, min(maximoPuntosMovimiento, (maximo - longitudMinimaMovimiento) / 4))
        }
        return max(0, min(maximoPuntos, (maximo - longitudMinima) / 4))
    }

    /// Bytes del mensaje, sin pasar de `maximo`: si no caben todos los puntos,
    /// se mandan los primeros (el tramo se acorta). Las coordenadas se
    /// redondean al metro y se saturan en ±32 767. Una escala mayor que 3 va
    /// como 3; sin tramo, los flags van a cero, sin escala (supuesto).
    /// Con movimiento (v0.9), ver `codificarConMovimiento`.
    public func codificar(maximo: Int = longitudMinima + 4 * maximoPuntos) -> [UInt8] {
        if movimiento {
            return codificarConMovimiento(maximo: maximo)
        }
        let caben = Self.puntosQueCaben(maximo)
        let lista = Array(puntos.prefix(caben))
        let hay = lista.count >= 2
        let indiceGiro: UInt8
        if hay, let giro, giro >= 0, giro < lista.count {
            indiceGiro = UInt8(giro)
        } else {
            indiceGiro = 255
        }
        let flags: UInt8 = hay ? 0x01 | min(escala, 3) << 1 : 0x00
        var bytes: [UInt8] = [Protocolo.version, secuencia, flags, indiceGiro]
        guard hay else { return bytes }
        for punto in lista {
            bytes.anadirU16(metrosI16(punto.x))
            bytes.anadirU16(metrosI16(punto.y))
        }
        return bytes
    }

    /// Con movimiento (v0.9): flags con el bit 3, giro sobre la lista entera,
    /// recorrido en decímetros (u32, redondeado y saturado; lo que no es
    /// finito, 0), cuántos van detrás y los puntos. Sin pasar de `maximo` ni de
    /// 42 puntos; si no caben todos, se dejan primero los de delante (la moto
    /// incluida): se quitan los de detrás más lejanos y, si aún no caben, los
    /// últimos de delante. Más de 10 por detrás: se quitan los más lejanos. Un
    /// giro que quede fuera va como 255. Sin tramo (menos de dos puntos, o
    /// `atras` fuera de la lista), el mensaje sin tramo de siempre, de 4 bytes
    /// (supuesto: así lo entiende cualquier dispositivo).
    func codificarConMovimiento(maximo: Int) -> [UInt8] {
        let caben = Self.puntosQueCaben(maximo, movimiento: true)
        let detras = max(0, atras)
        guard detras < puntos.count else {
            return [Protocolo.version, secuencia, 0x00, 255]
        }
        // La moto y los de delante, y los de detrás que quepan, los más cercanos
        let delante = puntos.count - detras
        let quedanDelante = min(delante, caben)
        let quedanDetras = min(detras, Self.maximoAtras, caben - quedanDelante)
        let primero = detras - quedanDetras
        let lista = Array(puntos[primero..<(detras + quedanDelante)])
        guard lista.count >= 2 else {
            return [Protocolo.version, secuencia, 0x00, 255]
        }
        let indiceGiro: UInt8
        if let giro, giro - primero >= 0, giro - primero < lista.count {
            indiceGiro = UInt8(giro - primero)
        } else {
            indiceGiro = 255
        }
        let flags: UInt8 = 0x01 | min(escala, 3) << 1 | Self.banderaMovimiento
        var bytes: [UInt8] = [Protocolo.version, secuencia, flags, indiceGiro]
        bytes.anadirU32(u32Saturado(recorrido * 10))
        bytes.append(UInt8(quedanDetras))
        for punto in lista {
            bytes.anadirU16(metrosI16(punto.x))
            bytes.anadirU16(metrosI16(punto.y))
        }
        return bytes
    }

    /// Descarta lo corto y otra versión. Sin el bit 0, o con menos de dos
    /// puntos, sin tramo (puntos vacíos y escala 0). Con el bit 3 (v0.9), el
    /// formato con movimiento: se descarta si tiene menos de 9 bytes; un
    /// `atrás` de más de 10 o que deja la moto fuera de los puntos que han
    /// llegado se lee como sin tramo (supuesto).
    public static func decodificar(_ bytes: [UInt8]) -> MensajeTrazo? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        let conMovimiento = bytes[2] & banderaMovimiento != 0
        if conMovimiento && bytes.count < longitudMinimaMovimiento { return nil }
        var puntos: [PuntoPlano] = []
        if bytes[2] & 0x01 != 0 {
            var i = conMovimiento ? longitudMinimaMovimiento : longitudMinima
            while i + 3 < bytes.count {
                let x = Int16(bitPattern: leerU16(bytes, i))
                let y = Int16(bitPattern: leerU16(bytes, i + 2))
                puntos.append(PuntoPlano(x: Double(x), y: Double(y)))
                i += 4
            }
        }
        var atras = 0
        var recorrido = 0.0
        if conMovimiento {
            recorrido = Double(leerU32(bytes, 4)) / 10
            atras = Int(bytes[8])
            if atras > maximoAtras || atras >= puntos.count { puntos = [] }
        }
        if puntos.count < 2 { puntos = [] }
        if puntos.isEmpty { atras = 0 }
        let giro: Int? = (bytes[3] == 255 || Int(bytes[3]) >= puntos.count) ? nil : Int(bytes[3])
        let escala: UInt8 = puntos.isEmpty ? 0 : (bytes[2] >> 1) & 0x03
        return MensajeTrazo(secuencia: bytes[1], puntos: puntos, giro: giro, escala: escala,
                            movimiento: conMovimiento, recorrido: recorrido, atras: atras)
    }
}

// MARK: - CRUCES (sección 7 quater)

/// Una calle que sale de un cruce del tramo de TRAZO.
public struct CalleCruce: Equatable {
    /// El cruce, en metros en los ejes de la moto (los de TRAZO).
    public var x: Double
    public var y: Double
    /// Dirección de la calle desde el cruce, en 1/256 de vuelta y en sentido
    /// horario desde «hacia delante»: 0 delante, 64 derecha, 128 atrás, 192
    /// izquierda.
    public var direccion: UInt8

    public init(x: Double, y: Double, direccion: UInt8) {
        self.x = x
        self.y = y
        self.direccion = direccion
    }
}

/// El anillo de una rotonda del tramo de TRAZO (v0.8): el centro, en metros
/// en los ejes de la moto (los de TRAZO), y el radio, en metros.
public struct AnilloCruce: Equatable {
    public var x: Double
    public var y: Double
    public var radio: Double

    public init(x: Double, y: Double, radio: Double) {
        self.x = x
        self.y = y
        self.radio = radio
    }
}

/// El radio de un anillo en u8 (CRUCES, v0.8): redondeado y saturado entre 1
/// y 255 m; lo que no es finito, 1.
func radioU8(_ valor: Double) -> UInt8 {
    guard valor.isFinite else { return 1 }
    return UInt8(min(255, max(1, valor.rounded())))
}

public struct MensajeCruces: Equatable {
    public static let longitudMinima = 4
    /// Como mucho: 4 bytes de cabecera y 35 calles de 5 bytes (179 bytes).
    public static let maximoCalles = 35
    /// Como mucho 4 anillos (v0.8), tras las calles: 1 byte con cuántos y 5
    /// por anillo.
    public static let maximoAnillos = 4
    /// El mensaje entero, con los anillos, no pasa de 179 bytes: el
    /// dispositivo recorta ahí.
    public static let longitudMaxima = 179

    public var secuencia: UInt8
    /// Secuencia del TRAZO al que acompaña: el dispositivo solo dibuja las
    /// calles con ese tramo.
    public var trazo: UInt8
    /// Los cruces más cercanos a la moto primero (Cruces.calles).
    public var calles: [CalleCruce]
    /// Los anillos de las rotondas del tramo (v0.8), los más cercanos
    /// primero (Cruces.anillos). Vacío: el mensaje acaba tras las calles, como
    /// antes de la v0.8. Solo para un dispositivo que anuncie el bit 9 de
    /// capacidades.
    public var anillos: [AnilloCruce]

    public init(secuencia: UInt8, trazo: UInt8, calles: [CalleCruce], anillos: [AnilloCruce] = []) {
        self.secuencia = secuencia
        self.trazo = trazo
        self.calles = calles
        self.anillos = anillos
    }

    /// Cuántas calles caben en `maximo` bytes (lo que admite la conexión), sin
    /// pasar de 35 ni de 179 bytes en total, con `anillos` anillos detrás
    /// (como mucho 4; con 0 no hay bloque de anillos).
    public static func callesQueCaben(_ maximo: Int, anillos: Int = 0) -> Int {
        let limite = min(maximo, longitudMaxima)
        let cuantos = min(max(0, anillos), anillosQueCaben(maximo))
        let bloque = cuantos > 0 ? 1 + 5 * cuantos : 0
        return max(0, min(maximoCalles, (limite - longitudMinima - bloque) / 5))
    }

    /// Cuántos anillos caben en `maximo` bytes, sin calles (como mucho 4).
    public static func anillosQueCaben(_ maximo: Int) -> Int {
        max(0, min(maximoAnillos, (min(maximo, longitudMaxima) - longitudMinima - 1) / 5))
    }

    /// Bytes del mensaje, sin pasar de `maximo` ni de 179. Los anillos van
    /// primero: si no caben todas las calles, se recorta por el final (se
    /// quedan las de los cruces más cercanos). Las coordenadas, como en TRAZO;
    /// el radio, redondeado entre 1 y 255 m. Sin anillos (o si no cabe
    /// ninguno), el mensaje acaba tras las calles.
    public func codificar(maximo: Int = longitudMaxima) -> [UInt8] {
        let listaAnillos = anillos.prefix(Self.anillosQueCaben(maximo))
        let lista = calles.prefix(Self.callesQueCaben(maximo, anillos: listaAnillos.count))
        var bytes: [UInt8] = [Protocolo.version, secuencia, trazo, UInt8(lista.count)]
        for calle in lista {
            bytes.anadirU16(metrosI16(calle.x))
            bytes.anadirU16(metrosI16(calle.y))
            bytes.append(calle.direccion)
        }
        if !listaAnillos.isEmpty {
            bytes.append(UInt8(listaAnillos.count))
            for anillo in listaAnillos {
                bytes.anadirU16(metrosI16(anillo.x))
                bytes.anadirU16(metrosI16(anillo.y))
                bytes.append(radioU8(anillo.radio))
            }
        }
        return bytes
    }

    /// Descarta lo corto y otra versión. Lee como mucho `n` calles, y solo las
    /// que lleguen enteras (supuesto). Si llegan las `n` y el mensaje sigue, el
    /// byte siguiente es el número de anillos (v0.8): lee como mucho 4, y solo
    /// los que lleguen enteros (supuesto, como las calles).
    public static func decodificar(_ bytes: [UInt8]) -> MensajeCruces? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        let n = Int(bytes[3])
        var calles: [CalleCruce] = []
        var i = longitudMinima
        while calles.count < n, i + 4 < bytes.count {
            let x = Int16(bitPattern: leerU16(bytes, i))
            let y = Int16(bitPattern: leerU16(bytes, i + 2))
            calles.append(CalleCruce(x: Double(x), y: Double(y), direccion: bytes[i + 4]))
            i += 5
        }
        var anillos: [AnilloCruce] = []
        if calles.count == n, i < bytes.count {
            let m = min(Int(bytes[i]), maximoAnillos)
            var j = i + 1
            while anillos.count < m, j + 4 < bytes.count {
                let x = Int16(bitPattern: leerU16(bytes, j))
                let y = Int16(bitPattern: leerU16(bytes, j + 2))
                anillos.append(AnilloCruce(x: Double(x), y: Double(y), radio: Double(bytes[j + 4])))
                j += 5
            }
        }
        return MensajeCruces(secuencia: bytes[1], trazo: bytes[2], calles: calles, anillos: anillos)
    }
}

// MARK: - DEVICE_INFO (sección 4)

public struct Capacidades: OptionSet, Equatable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let nav     = Capacidades(rawValue: 1 << 0)
    public static let gps     = Capacidades(rawValue: 1 << 1)
    public static let status  = Capacidades(rawValue: 1 << 2)
    public static let navText = Capacidades(rawValue: 1 << 3)
    public static let config  = Capacidades(rawValue: 1 << 4)
    public static let movil   = Capacidades(rawValue: 1 << 5)
    public static let trazo   = Capacidades(rawValue: 1 << 6)
    /// El dispositivo da MOVIL por bueno mientras dure la conexión: la app lo
    /// manda solo al cambiar (v0.5, §7).
    public static let movilAlCambiar = Capacidades(rawValue: 1 << 7)
    /// Calles de los cruces del tramo (v0.6, §7 quater).
    public static let cruces  = Capacidades(rawValue: 1 << 8)
    /// El dispositivo dibuja los anillos de las rotondas que van tras las
    /// calles de CRUCES (v0.8, §7 quater).
    public static let anillos = Capacidades(rawValue: 1 << 9)
    /// El dispositivo acepta TRAZO con movimiento (el recorrido de la moto y
    /// los puntos de detrás) y mueve el dibujo él solo entre mensajes (v0.9,
    /// §7 ter).
    public static let movimiento = Capacidades(rawValue: 1 << 10)
}

public struct DeviceInfo: Equatable {
    public static let longitudMinima = 8

    public var version: UInt8
    /// 1 = cuadro de moto; 2 = firmware de referencia.
    public var tipo: UInt8
    public var capacidades: Capacidades
    /// Mensajes por segundo y característica (0 = sin límite).
    public var frecuenciaMaxima: UInt8
    /// Mayor, menor y parche.
    public var firmware: [UInt8]

    public init(version: UInt8, tipo: UInt8, capacidades: Capacidades,
                frecuenciaMaxima: UInt8, firmware: [UInt8]) {
        self.version = version
        self.tipo = tipo
        self.capacidades = capacidades
        self.frecuenciaMaxima = frecuenciaMaxima
        self.firmware = firmware
    }

    public static func decodificar(_ bytes: [UInt8]) -> DeviceInfo? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        let capacidades = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
        return DeviceInfo(
            version: bytes[0],
            tipo: bytes[1],
            capacidades: Capacidades(rawValue: capacidades),
            frecuenciaMaxima: bytes[4],
            firmware: Array(bytes[5...7])
        )
    }
}
