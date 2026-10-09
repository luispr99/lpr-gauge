// Codificación y decodificación de los mensajes (docs/PROTOCOLO.md, v0.5).
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

    public init(ecoNav: UInt8, ecoGPS: UInt8, pideReenvio: Bool, ecoMovil: UInt8?,
                ecoNavText: UInt8? = nil, ecoTrazo: UInt8? = nil) {
        self.ecoNav = ecoNav
        self.ecoGPS = ecoGPS
        self.pideReenvio = pideReenvio
        self.ecoMovil = ecoMovil
        self.ecoNavText = ecoMovil == nil ? nil : ecoNavText
        self.ecoTrazo = self.ecoNavText == nil ? nil : ecoTrazo
    }

    public func codificar() -> [UInt8] {
        var bytes: [UInt8] = [Protocolo.version, ecoNav, ecoGPS, pideReenvio ? 0x01 : 0x00]
        if let ecoMovil {
            bytes.append(ecoMovil)
            if let ecoNavText {
                bytes.append(ecoNavText)
                if let ecoTrazo { bytes.append(ecoTrazo) }
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
            ecoTrazo: bytes.count >= 7 ? bytes[6] : nil
        )
    }
}

// MARK: - TRAZO (sección 7 ter)

public struct MensajeTrazo: Equatable {
    public static let longitudMinima = 4
    /// Como mucho: 4 bytes de cabecera y 44 puntos de 4 bytes (180 bytes).
    public static let maximoPuntos = 44

    public var secuencia: UInt8
    /// Metros en los ejes de la moto (Trazo); con menos de dos, no hay tramo.
    public var puntos: [PuntoPlano]
    /// Índice del próximo giro en `puntos`, o nil.
    public var giro: Int?

    public init(secuencia: UInt8, puntos: [PuntoPlano], giro: Int?) {
        self.secuencia = secuencia
        self.puntos = puntos
        self.giro = giro
    }

    /// Cuántos puntos caben en `maximo` bytes (lo que admite la conexión), sin
    /// pasar de 44.
    public static func puntosQueCaben(_ maximo: Int) -> Int {
        max(0, min(maximoPuntos, (maximo - longitudMinima) / 4))
    }

    /// Bytes del mensaje, sin pasar de `maximo`: si no caben todos los puntos,
    /// se mandan los primeros (el tramo se acorta). Las coordenadas se
    /// redondean al metro y se saturan en ±32 767.
    public func codificar(maximo: Int = longitudMinima + 4 * maximoPuntos) -> [UInt8] {
        let caben = Self.puntosQueCaben(maximo)
        let lista = Array(puntos.prefix(caben))
        let hay = lista.count >= 2
        let indiceGiro: UInt8
        if hay, let giro, giro >= 0, giro < lista.count {
            indiceGiro = UInt8(giro)
        } else {
            indiceGiro = 255
        }
        var bytes: [UInt8] = [Protocolo.version, secuencia, hay ? 0x01 : 0x00, indiceGiro]
        guard hay else { return bytes }
        for punto in lista {
            for valor in [punto.x, punto.y] {
                let metros = valor.isFinite ? min(32_767, max(-32_767, valor.rounded())) : 0
                let entero = Int16(metros)
                let sinSigno = UInt16(bitPattern: entero)
                bytes.append(UInt8(sinSigno & 0xFF))
                bytes.append(UInt8(sinSigno >> 8))
            }
        }
        return bytes
    }

    /// Descarta lo corto y otra versión. Sin el bit 0, o con menos de dos
    /// puntos, sin tramo (puntos vacíos).
    public static func decodificar(_ bytes: [UInt8]) -> MensajeTrazo? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        var puntos: [PuntoPlano] = []
        if bytes[2] & 0x01 != 0 {
            var i = longitudMinima
            while i + 3 < bytes.count {
                let x = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)
                let y = Int16(bitPattern: UInt16(bytes[i + 2]) | UInt16(bytes[i + 3]) << 8)
                puntos.append(PuntoPlano(x: Double(x), y: Double(y)))
                i += 4
            }
        }
        if puntos.count < 2 { puntos = [] }
        let giro: Int? = (bytes[3] == 255 || Int(bytes[3]) >= puntos.count) ? nil : Int(bytes[3])
        return MensajeTrazo(secuencia: bytes[1], puntos: puntos, giro: giro)
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
