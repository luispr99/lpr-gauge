import Foundation

// MARK: - RUTAS (sección 7 quinquies, v0.14)

/// En qué está la orden de ruta del cuadro (byte 2 de RUTAS).
public enum EstadoOrdenRuta: UInt8, Equatable {
    /// Ninguna en curso, o ya atendida.
    case ninguna = 0
    /// Calculando la ruta o empezando a guiar.
    case calculando = 1
    /// La app no ha podido arrancar el GPS: hay que abrirla.
    case abreLaApp = 2
    /// Sin ruta, error o lista que ya no está.
    case noSePudo = 3
    /// La propuesta, lista para confirmar en el cuadro (v0.14).
    case propuesta = 4
}

/// Una ruta de la lista del cuadro: su destino y sus opciones (v0.14; en la
/// v0.13 iba lo que midió la última vez).
public struct RutaCuadro: Equatable {
    /// 0 la más rápida, 1 la de más curvas, 2 por tierra.
    public var tipo: UInt8
    /// Se admiten peajes / autovías (lo contrario de «evitar»).
    public var peajes: Bool
    public var autovias: Bool
    /// Margen de tiempo de la de más curvas, en por ciento (0-200).
    public var margen: Int
    public var nombre: String

    public init(tipo: UInt8, peajes: Bool, autovias: Bool, margen: Int, nombre: String) {
        self.tipo = tipo
        self.peajes = peajes
        self.autovias = autovias
        self.margen = margen
        self.nombre = nombre
    }

    /// El código de un tipo de la app («rapida», «divertida», «tierra»;
    /// otro, como la más rápida).
    public static func codigo(tipo: String) -> UInt8 {
        ["rapida": 0, "divertida": 1, "tierra": 2][tipo] ?? 0
    }

    /// La de una ruta guardada.
    public init(_ guardada: RutaGuardada) {
        self.init(tipo: Self.codigo(tipo: guardada.tipo), peajes: !guardada.evitarPeajes,
                  autovias: !guardada.evitarAutopistas, margen: Int((guardada.margen * 100).rounded()),
                  nombre: guardada.nombre)
    }
}

/// La ruta calculada para confirmar en el cuadro (estado 4).
public struct PropuestaRuta: Equatable {
    public var tipo: UInt8
    /// El tipo de la ruta tocada no ha salido: se propone la más rápida.
    public var otroTipo: Bool
    public var metros: Double?
    public var segundos: Double?
    public var curvas: Int?
    /// Lo que tarda de más que la más rápida.
    public var segundosDeMas: Double?
    public var metrosPeaje: Double?
    public var metrosAutopista: Double?

    public init(tipo: UInt8, otroTipo: Bool = false, metros: Double?, segundos: Double?, curvas: Int?,
                segundosDeMas: Double?, metrosPeaje: Double?, metrosAutopista: Double?) {
        self.tipo = tipo
        self.otroTipo = otroTipo
        self.metros = metros
        self.segundos = segundos
        self.curvas = curvas
        self.segundosDeMas = segundosDeMas
        self.metrosPeaje = metrosPeaje
        self.metrosAutopista = metrosAutopista
    }
}

/// Las rutas para empezar desde el cuadro, el estado de su orden y, con el
/// estado 4, la propuesta.
public struct MensajeRutas: Equatable {
    public static let cabecera = 5
    /// Bytes fijos de cada ruta, sin el nombre.
    public static let fijoPorRuta = 4
    public static let maximoRutas = 3
    public static let maximoNombre = 40
    public static let largoPropuesta = 14
    /// Como mucho: cabecera, tres rutas con nombres de 40 bytes y la propuesta
    /// (151).
    public static let longitudMaxima = cabecera + maximoRutas * (fijoPorRuta + maximoNombre) + largoPropuesta

    public var secuencia: UInt8
    public var estado: EstadoOrdenRuta
    /// Contador de la última orden atendida (0, ninguna).
    public var ecoOrden: UInt8
    public var rutas: [RutaCuadro]
    /// Solo va con el estado 4.
    public var propuesta: PropuestaRuta?

    public init(secuencia: UInt8, estado: EstadoOrdenRuta = .ninguna, ecoOrden: UInt8 = 0, rutas: [RutaCuadro],
                propuesta: PropuestaRuta? = nil) {
        self.secuencia = secuencia
        self.estado = estado
        self.ecoOrden = ecoOrden
        self.rutas = rutas
        self.propuesta = propuesta
    }

    /// Como mucho tres rutas y `maximo` bytes (lo que admite la conexión): la
    /// propuesta va entera; los nombres, como mucho de 40 bytes, se cortan sin
    /// partir un carácter, todos al mismo largo, lo justo para que quepa todo;
    /// si sin nombre tampoco caben, van menos rutas. Sin propuesta, el estado
    /// 4 no se manda (va como 3). El margen se satura entre 0 y 200.
    public func codificar(maximo: Int = longitudMaxima) -> [UInt8] {
        let conPropuesta = estado == .propuesta && propuesta != nil
        let extra = conPropuesta ? Self.largoPropuesta : 0
        var lista = Array(rutas.prefix(Self.maximoRutas))
        let tope = min(maximo, Self.longitudMaxima)
        while !lista.isEmpty && Self.cabecera + extra + lista.count * Self.fijoPorRuta > tope {
            lista.removeLast()
        }
        let nombres = lista.map { Self.cortar(Array($0.nombre.utf8), Self.maximoNombre) }
        var largo = Self.maximoNombre
        while largo > 0 && Self.cabecera + extra + nombres.reduce(0) { $0 + Self.fijoPorRuta + min($1.count, largo) } > tope {
            largo -= 1
        }
        let estadoMandado: EstadoOrdenRuta = (estado == .propuesta && !conPropuesta) ? .noSePudo : estado
        var bytes: [UInt8] = [Protocolo.version, secuencia, estadoMandado.rawValue, ecoOrden, UInt8(lista.count)]
        for (ruta, nombre) in zip(lista, nombres) {
            let corto = Self.cortar(nombre, largo)
            let opciones: UInt8 = (ruta.peajes ? 0x01 : 0) | (ruta.autovias ? 0x02 : 0)
            bytes += [ruta.tipo, opciones, UInt8(min(200, max(0, ruta.margen))), UInt8(corto.count)]
            bytes += corto
        }
        if conPropuesta, let p = propuesta {
            bytes += [p.tipo, p.otroTipo ? 0x01 : 0x00]
            bytes.anadirU16(u16Saturado(p.metros.map { $0 / 10 }))
            bytes.anadirU16(u16Saturado(p.segundos.map { $0 / 60 }))
            bytes.anadirU16(u16Saturado(p.curvas.map { Double($0) }))
            bytes.anadirU16(u16Saturado(p.segundosDeMas.map { $0 / 60 }))
            bytes.anadirU16(u16Saturado(p.metrosPeaje.map { $0 / 10 }))
            bytes.anadirU16(u16Saturado(p.metrosAutopista.map { $0 / 10 }))
        }
        return bytes
    }

    /// Descarta lo corto, otra versión, más de tres rutas, una ruta cortada, un
    /// nombre que no sea UTF-8 válido y el estado 4 sin su propuesta entera.
    public static func decodificar(_ bytes: [UInt8]) -> MensajeRutas? {
        guard bytes.count >= cabecera, bytes[0] == Protocolo.version, bytes[4] <= maximoRutas else { return nil }
        var rutas: [RutaCuadro] = []
        var i = cabecera
        for _ in 0..<Int(bytes[4]) {
            guard i + fijoPorRuta <= bytes.count else { return nil }
            let largo = Int(bytes[i + 3])
            guard largo <= maximoNombre, i + fijoPorRuta + largo <= bytes.count,
                  let nombre = String(bytes: bytes[(i + fijoPorRuta)..<(i + fijoPorRuta + largo)], encoding: .utf8)
            else { return nil }
            rutas.append(RutaCuadro(tipo: bytes[i], peajes: bytes[i + 1] & 0x01 != 0, autovias: bytes[i + 1] & 0x02 != 0,
                                    margen: Int(bytes[i + 2]), nombre: nombre))
            i += fijoPorRuta + largo
        }
        let estado = EstadoOrdenRuta(rawValue: bytes[2]) ?? .noSePudo
        var propuesta: PropuestaRuta?
        if estado == .propuesta {
            guard i + largoPropuesta <= bytes.count else { return nil }
            func valor(_ j: Int) -> Double? {
                let crudo = leerU16(bytes, j)
                return crudo == 0xFFFF ? nil : Double(crudo)
            }
            propuesta = PropuestaRuta(tipo: bytes[i], otroTipo: bytes[i + 1] & 0x01 != 0,
                                      metros: valor(i + 2).map { $0 * 10 }, segundos: valor(i + 4).map { $0 * 60 },
                                      curvas: valor(i + 6).map { Int($0) }, segundosDeMas: valor(i + 8).map { $0 * 60 },
                                      metrosPeaje: valor(i + 10).map { $0 * 10 },
                                      metrosAutopista: valor(i + 12).map { $0 * 10 })
        }
        return MensajeRutas(secuencia: bytes[1], estado: estado, ecoOrden: bytes[3], rutas: rutas, propuesta: propuesta)
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

/// La orden de ruta del cuadro (STATUS, bytes 8-11).
public struct OrdenRuta: Equatable {
    public enum Codigo: UInt8, Equatable {
        /// Calcular la ruta y mandar la propuesta (v0.14; en la v0.13,
        /// empezarla).
        case calcular = 1
        case cancelar = 2
        /// Empezar a guiar la propuesta (v0.14).
        case empezar = 3
        /// Terminar la ruta en curso, desde el mapa del cuadro (v0.14).
        case terminar = 4
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
