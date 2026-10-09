import Foundation

// MARK: - RUTAS (sección 7 quinquies, v0.13)

/// En qué está la orden de ruta del cuadro (byte 2 de RUTAS).
public enum EstadoOrdenRuta: UInt8, Equatable {
    /// Ninguna en curso, o ya atendida.
    case ninguna = 0
    case calculando = 1
    /// La app no está en primer plano: iOS no le deja empezar a guiar.
    case abreLaApp = 2
    /// Sin ruta, error o lista que ya no está.
    case noSePudo = 3
}

/// Una ruta de la lista del cuadro: lo que se enseña de ella.
public struct RutaCuadro: Equatable {
    /// 0 la más rápida, 1 la de más curvas, 2 por tierra.
    public var tipo: UInt8
    public var metros: Double?
    public var segundos: Double?
    public var curvas: Int?
    /// Metros de peaje y de autopista (0, ninguno; nil, no se sabe).
    public var metrosPeaje: Double?
    public var metrosAutopista: Double?
    public var nombre: String

    public init(tipo: UInt8, metros: Double?, segundos: Double?, curvas: Int?, metrosPeaje: Double? = nil,
                metrosAutopista: Double? = nil, nombre: String) {
        self.tipo = tipo
        self.metros = metros
        self.segundos = segundos
        self.curvas = curvas
        self.metrosPeaje = metrosPeaje
        self.metrosAutopista = metrosAutopista
        self.nombre = nombre
    }

    /// La de una ruta guardada (tipos de la app: «rapida», «divertida» y
    /// «tierra»; otro, como la más rápida).
    public init(_ guardada: RutaGuardada) {
        let tipos: [String: UInt8] = ["rapida": 0, "divertida": 1, "tierra": 2]
        self.init(tipo: tipos[guardada.tipo] ?? 0, metros: guardada.metros, segundos: guardada.segundos,
                  curvas: guardada.curvas, metrosPeaje: guardada.metrosPeaje,
                  metrosAutopista: guardada.metrosAutopista, nombre: guardada.nombre)
    }
}

/// Las últimas rutas para empezar desde el cuadro y el estado de su orden.
public struct MensajeRutas: Equatable {
    public static let cabecera = 5
    /// Bytes fijos de cada ruta, sin el nombre.
    public static let fijoPorRuta = 12
    public static let maximoRutas = 3
    public static let maximoNombre = 40
    /// Como mucho: cabecera y tres rutas con nombres de 40 bytes (161).
    public static let longitudMaxima = cabecera + maximoRutas * (fijoPorRuta + maximoNombre)

    public var secuencia: UInt8
    public var estado: EstadoOrdenRuta
    /// Contador de la última orden atendida (0, ninguna).
    public var ecoOrden: UInt8
    public var rutas: [RutaCuadro]

    public init(secuencia: UInt8, estado: EstadoOrdenRuta = .ninguna, ecoOrden: UInt8 = 0, rutas: [RutaCuadro]) {
        self.secuencia = secuencia
        self.estado = estado
        self.ecoOrden = ecoOrden
        self.rutas = rutas
    }

    /// Como mucho tres rutas y `maximo` bytes (lo que admite la conexión): los
    /// nombres, como mucho de 40 bytes, se cortan sin partir un carácter, todos
    /// al mismo largo, lo justo para que quepan; si sin nombre tampoco caben,
    /// van menos rutas. Las distancias (la ruta, el peaje y la autopista) en
    /// decenas de metros y los tiempos en minutos, redondeados y saturados en
    /// 65 534; sin dato, `0xFFFF`.
    public func codificar(maximo: Int = longitudMaxima) -> [UInt8] {
        var lista = Array(rutas.prefix(Self.maximoRutas))
        let tope = min(maximo, Self.longitudMaxima)
        while !lista.isEmpty && Self.cabecera + lista.count * Self.fijoPorRuta > tope {
            lista.removeLast()
        }
        let nombres = lista.map { Self.cortar(Array($0.nombre.utf8), Self.maximoNombre) }
        // El largo común más alto que deja caber todo
        var largo = Self.maximoNombre
        while largo > 0 && Self.cabecera + nombres.reduce(0) { $0 + Self.fijoPorRuta + min($1.count, largo) } > tope {
            largo -= 1
        }
        var bytes: [UInt8] = [Protocolo.version, secuencia, estado.rawValue, ecoOrden, UInt8(lista.count)]
        for (ruta, nombre) in zip(lista, nombres) {
            let corto = Self.cortar(nombre, largo)
            bytes.append(ruta.tipo)
            bytes.anadirU16(u16Saturado(ruta.metros.map { $0 / 10 }))
            bytes.anadirU16(u16Saturado(ruta.segundos.map { $0 / 60 }))
            bytes.anadirU16(u16Saturado(ruta.curvas.map { Double($0) }))
            bytes.anadirU16(u16Saturado(ruta.metrosPeaje.map { $0 / 10 }))
            bytes.anadirU16(u16Saturado(ruta.metrosAutopista.map { $0 / 10 }))
            bytes.append(UInt8(corto.count))
            bytes += corto
        }
        return bytes
    }

    /// Descarta lo corto, otra versión, más de tres rutas, una ruta cortada y
    /// un nombre que no sea UTF-8 válido.
    public static func decodificar(_ bytes: [UInt8]) -> MensajeRutas? {
        guard bytes.count >= cabecera, bytes[0] == Protocolo.version, bytes[4] <= maximoRutas else { return nil }
        func valor(_ i: Int) -> Double? {
            let crudo = leerU16(bytes, i)
            return crudo == 0xFFFF ? nil : Double(crudo)
        }
        var rutas: [RutaCuadro] = []
        var i = cabecera
        for _ in 0..<Int(bytes[4]) {
            guard i + fijoPorRuta <= bytes.count else { return nil }
            let largo = Int(bytes[i + 11])
            guard largo <= maximoNombre, i + fijoPorRuta + largo <= bytes.count,
                  let nombre = String(bytes: bytes[(i + fijoPorRuta)..<(i + fijoPorRuta + largo)], encoding: .utf8)
            else { return nil }
            rutas.append(RutaCuadro(tipo: bytes[i], metros: valor(i + 1).map { $0 * 10 },
                                    segundos: valor(i + 3).map { $0 * 60 }, curvas: valor(i + 5).map { Int($0) },
                                    metrosPeaje: valor(i + 7).map { $0 * 10 },
                                    metrosAutopista: valor(i + 9).map { $0 * 10 }, nombre: nombre))
            i += fijoPorRuta + largo
        }
        return MensajeRutas(secuencia: bytes[1], estado: EstadoOrdenRuta(rawValue: bytes[2]) ?? .noSePudo,
                            ecoOrden: bytes[3], rutas: rutas)
    }

    /// Los primeros `largo` bytes de un texto UTF-8 como mucho, sin partir un
    /// carácter (como NAV_TEXT).
    static func cortar(_ utf8: [UInt8], _ largo: Int) -> [UInt8] {
        guard utf8.count > largo else { return utf8 }
        var corte = largo
        while corte > 0 && utf8[corte] & 0xC0 == 0x80 {
            corte -= 1
        }
        return Array(utf8[0..<corte])
    }
}

/// La orden de ruta del cuadro (STATUS, bytes 8-11, v0.13).
public struct OrdenRuta: Equatable {
    public enum Codigo: UInt8, Equatable {
        case empezar = 1
        case cancelar = 2
    }

    /// Sube con cada orden; 0, ninguna desde la conexión.
    public var contador: UInt8
    /// nil si el código no se conoce.
    public var codigo: Codigo?
    /// Secuencia del RUTAS que enseñaba el cuadro.
    public var lista: UInt8
    /// Posición de la ruta en esa lista.
    public var ruta: UInt8

    public init(contador: UInt8, codigo: Codigo?, lista: UInt8, ruta: UInt8) {
        self.contador = contador
        self.codigo = codigo
        self.lista = lista
        self.ruta = ruta
    }
}
