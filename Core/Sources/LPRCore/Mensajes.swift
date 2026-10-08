// Codificación y decodificación de los mensajes (docs/PROTOCOLO.md, v0.2).
// Reglas comunes (sección 3): little-endian, primer byte = versión, campos
// nuevos al final; el receptor ignora los bytes que sobran y descarta los
// mensajes cortos o con una versión que no conoce.

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

// MARK: - STATUS (sección 9)

public struct MensajeStatus: Equatable {
    public static let longitudMinima = 4

    public var ecoNav: UInt8
    public var ecoGPS: UInt8
    public var pideReenvio: Bool
    /// nil si el dispositivo es anterior a la v0.2 (STATUS de 4 bytes).
    public var ecoMovil: UInt8?

    public init(ecoNav: UInt8, ecoGPS: UInt8, pideReenvio: Bool, ecoMovil: UInt8?) {
        self.ecoNav = ecoNav
        self.ecoGPS = ecoGPS
        self.pideReenvio = pideReenvio
        self.ecoMovil = ecoMovil
    }

    public func codificar() -> [UInt8] {
        var bytes: [UInt8] = [Protocolo.version, ecoNav, ecoGPS, pideReenvio ? 0x01 : 0x00]
        if let ecoMovil { bytes.append(ecoMovil) }
        return bytes
    }

    public static func decodificar(_ bytes: [UInt8]) -> MensajeStatus? {
        guard bytes.count >= longitudMinima, bytes[0] == Protocolo.version else { return nil }
        return MensajeStatus(
            ecoNav: bytes[1],
            ecoGPS: bytes[2],
            pideReenvio: bytes[3] & 0x01 != 0,
            ecoMovil: bytes.count >= 5 ? bytes[4] : nil
        )
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
