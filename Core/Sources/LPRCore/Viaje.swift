import Foundation

/// Tiempo, distancia y velocidad media de un viaje (NAV, v0.10: el resumen
/// al llegar).
public struct ResumenViaje: Equatable {
    public var segundos: Double
    public var metros: Double

    public init(segundos: Double, metros: Double) {
        self.segundos = segundos
        self.metros = metros
    }

    /// Metros por segundo: la distancia entre el tiempo; nil sin tiempo.
    public var velocidadMedia: Double? {
        guard segundos > 0, segundos.isFinite, metros.isFinite else { return nil }
        return metros / segundos
    }
}

/// Cuentakilómetros del viaje (NAV, docs/PROTOCOLO.md §5, v0.10): el tiempo
/// desde que se inicia la ruta, paradas incluidas, y la distancia sumando las
/// posiciones del GPS, así que cuenta los desvíos. Los recálculos no lo
/// reinician: es del viaje, no de la ruta. Al llegar se para.
///
/// La distancia suma la que hay entre posiciones consecutivas que cuentan:
/// - las de precisión horizontal de más de `precisionMaxima` metros (o sin
///   precisión, negativa en Core Location) no cuentan;
/// - un salto imposible, a más de `velocidadMaxima` m/s desde la anterior que
///   contó (o una posición que no es posterior a ella y está en otro sitio),
///   tampoco: la posición se descarta y la siguiente se mide desde la
///   anterior buena.
public struct Cuentakilometros: Equatable {
    /// Metros de precisión horizontal como mucho (valor del encargo de la
    /// 0.14.0, 2026-10-09; supuesto, sin probar en la moto).
    public static let precisionMaxima = 50.0
    /// Metros por segundo entre dos posiciones a partir de los que el salto es
    /// imposible: 252 km/h (valor del encargo de la 0.14.0, 2026-10-09;
    /// supuesto).
    public static let velocidadMaxima = 70.0

    public let inicio: Date
    /// Al llegar; nil mientras sigue.
    public private(set) var fin: Date?
    public private(set) var metros = 0.0
    /// La última posición que contó y cuándo se tomó.
    private var ultimoPunto: PuntoRuta?
    private var ultimoInstante: Date?

    public init(inicio: Date) {
        self.inicio = inicio
    }

    /// Una posición del GPS, tomada en `instante`, con su precisión
    /// horizontal en metros. Devuelve si ha contado (también la primera, que
    /// no suma nada). Después de `parar`, ninguna cuenta.
    @discardableResult
    public mutating func anadir(_ punto: PuntoRuta, precision: Double, instante: Date) -> Bool {
        guard fin == nil, precision.isFinite, precision >= 0, precision <= Self.precisionMaxima,
              punto.latitud.isFinite, punto.longitud.isFinite
        else { return false }
        guard let anterior = ultimoPunto, let antes = ultimoInstante else {
            ultimoPunto = punto
            ultimoInstante = instante
            return true
        }
        let distancia = Trazo.distancia(anterior, punto)
        guard distancia.isFinite else { return false }
        let segundos = instante.timeIntervalSince(antes)
        if distancia > 0 && (segundos <= 0 || distancia / segundos > Self.velocidadMaxima) {
            return false
        }
        metros += distancia
        ultimoPunto = punto
        ultimoInstante = max(antes, instante)
        return true
    }

    /// Al llegar: el tiempo y la distancia se quedan como están.
    public mutating func parar(_ instante: Date) {
        guard fin == nil else { return }
        fin = max(inicio, instante)
    }

    /// El resumen hasta `ahora` (o hasta la llegada, si ya ha parado).
    public func resumen(ahora: Date) -> ResumenViaje {
        ResumenViaje(segundos: max(0, (fin ?? ahora).timeIntervalSince(inicio)), metros: metros)
    }
}
