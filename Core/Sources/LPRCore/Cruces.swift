import Foundation

/// Un cruce de la ruta: dónde está y los rumbos de las calles que salen de él,
/// sin la de llegada ni la de salida de la ruta (CRUCES, docs/PROTOCOLO.md
/// §7 quater).
public struct Cruce: Equatable {
    public var punto: PuntoRuta
    /// Grados desde el norte, en sentido horario, desde el cruce hacia fuera.
    public var rumbos: [Double]
    /// Metros desde el principio de la ruta hasta el cruce, por la ruta (de su
    /// índice en el trazado, `geometry_index`); nil si no se conoce. Sirve para
    /// no tomar los cruces de otra pasada por el mismo sitio ni los ya pasados.
    public var recorrido: Double?

    public init(punto: PuntoRuta, rumbos: [Double], recorrido: Double? = nil) {
        self.punto = punto
        self.rumbos = rumbos
        self.recorrido = recorrido
    }
}

/// Una ruta de una respuesta en formato OSRM: su trazado y sus cruces.
public struct RutaConCruces: Equatable {
    public var puntos: [PuntoRuta]
    public var cruces: [Cruce]
    /// Metros del trazado entero (los de `recorrido` de los cruces llegan
    /// hasta aquí).
    public var longitud: Double
    /// La vía de cada paso, en orden (los de todos los tramos seguidos), como
    /// se escribe junto a la flecha (RespuestaOSRM.via); vacío si no tiene
    /// nombre ni número. Ferrostar 0.57.0 lee el `ref` de cada paso pero no lo
    /// da en sus RouteStep, y sin él las carreteras que solo tienen número
    /// (M-510, N-6) se quedaban sin texto (lo vio la revisión de la 0.10.0).
    public var vias: [String]

    public init(puntos: [PuntoRuta], cruces: [Cruce], vias: [String] = []) {
        self.puntos = puntos
        self.cruces = cruces
        self.longitud = RespuestaOSRM.recorridos(puntos).last ?? 0
        self.vias = vias
    }
}

/// Respuesta de /route de Valhalla en formato OSRM, la que pide Ferrostar para
/// guiar. Solo lo que hace falta para los cruces: el trazado de cada ruta
/// (`geometry`, polyline6) y, de cada paso, sus cruces (`intersections`), con
/// la posición (`location`, longitud y latitud), los rumbos de todas las calles
/// (`bearings`) y cuáles son la de llegada (`in`) y la de salida (`out`).
/// Comprobado con valhalla1.openstreetmap.de el 2026-10-09, también con las
/// opciones que pone Ferrostar 0.57.0 en su petición (docs/DECISIONES.md).
public enum RespuestaOSRM {
    /// Las rutas, en el orden de la respuesta. Los cruces sin calles laterales
    /// (la salida, la llegada, una curva sin cruce) no se guardan. Lanza un
    /// error si no es una respuesta OSRM (por ejemplo, la del formato propio de
    /// Valhalla).
    public static func rutas(de datos: Data) throws -> [RutaConCruces] {
        let respuesta = try JSONDecoder().decode(Respuesta.self, from: datos)
        return respuesta.routes.map { ruta -> RutaConCruces in
            let puntos = Polilinea.decodificar(ruta.geometry, precision: 6)
            let hastaPunto = RespuestaOSRM.recorridos(puntos)
            var cruces: [Cruce] = []
            var vias: [String] = []
            for tramo in ruta.legs ?? [] {
                for paso in tramo.steps ?? [] {
                    vias.append(via(nombre: paso.name, numero: paso.ref))
                    for cruce in paso.intersections ?? [] {
                        guard cruce.location.count >= 2, let rumbos = cruce.bearings else { continue }
                        // Las calles laterales: todas salvo la de llegada y la de salida
                        let laterales = rumbos.indices
                            .filter { $0 != cruce.entrada && $0 != cruce.salida }
                            .map { rumbos[$0] }
                        guard !laterales.isEmpty else { continue }
                        let indice = cruce.indiceTrazado ?? -1
                        cruces.append(Cruce(
                            punto: PuntoRuta(latitud: cruce.location[1], longitud: cruce.location[0]),
                            rumbos: laterales,
                            recorrido: hastaPunto.indices.contains(indice) ? hastaPunto[indice] : nil
                        ))
                    }
                }
            }
            return RutaConCruces(puntos: puntos, cruces: cruces, vias: vias)
        }
    }

    /// La vía de un paso como se escribe junto a la flecha: el número y el
    /// nombre («A-6, Autovía del Noroeste»), o el que haya («M-510», «Calle
    /// Mayor»); vacío si no hay ninguno.
    public static func via(nombre: String?, numero: String?) -> String {
        let partes = [numero, nombre]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return partes.joined(separator: ", ")
    }

    /// Metros recorridos hasta cada punto del trazado, desde el primero.
    static func recorridos(_ puntos: [PuntoRuta]) -> [Double] {
        guard let primero = puntos.first else { return [] }
        var lista = [0.0]
        var previo = primero
        for punto in puntos.dropFirst() {
            lista.append(lista[lista.count - 1] + Trazo.distancia(previo, punto))
            previo = punto
        }
        return lista
    }

    // Solo los campos que usa la app
    struct Respuesta: Decodable {
        let routes: [Ruta]
    }

    struct Ruta: Decodable {
        let geometry: String
        let legs: [Tramo]?
    }

    struct Tramo: Decodable {
        let steps: [Paso]?
    }

    struct Paso: Decodable {
        let intersections: [Interseccion]?
        let name: String?
        let ref: String?
    }

    struct Interseccion: Decodable {
        /// Longitud y latitud.
        let location: [Double]
        /// Valhalla los da enteros; como Double valen igual.
        let bearings: [Double]?
        /// Índices en `bearings` de la calle de llegada (no está en la salida)
        /// y de la de salida (no está en la llegada).
        let entrada: Int?
        let salida: Int?
        /// Índice del cruce en el trazado de la ruta (Valhalla lo da para la
        /// ruta entera: crece de paso en paso).
        let indiceTrazado: Int?

        enum CodingKeys: String, CodingKey {
            case location
            case bearings
            case entrada = "in"
            case salida = "out"
            case indiceTrazado = "geometry_index"
        }
    }
}

/// Las calles que salen del tramo de TRAZO, para CRUCES (§7 quater, v0.6).
public enum Cruces {
    /// Metros como mucho entre un cruce y la ruta del tramo para que sea suyo.
    /// Valhalla pone cada cruce en un vértice del trazado, así que basta poco.
    static let tolerancia = 5.0

    /// La ruta de `rutas` con el mismo trazado que `geometria` (la del guiado de
    /// Ferrostar): el mismo número de puntos y todos a menos de 1 m. Todos, no
    /// solo los extremos: las alternativas de una respuesta los comparten (lo
    /// vio la revisión de la 0.10.0). Solo se hace al cambiar de ruta. Nil si no
    /// hay ninguna.
    public static func buscar(_ geometria: [PuntoRuta], en rutas: [RutaConCruces]) -> RutaConCruces? {
        guard !geometria.isEmpty else { return nil }
        return rutas.first { ruta in
            ruta.puntos.count == geometria.count
                && zip(ruta.puntos, geometria).allSatisfy { Trazo.distancia($0, $1) < 1 }
        }
    }

    /// Las calles de los `cruces` que quedan sobre el tramo (a menos de
    /// `tolerancia` metros de `ruta`, la del tramo sin simplificar, que empieza
    /// en la moto), en los ejes de la moto (el origen en el primer punto de
    /// `ruta` y `sentido` hacia arriba, como TRAZO). Los cruces más cercanos a
    /// la moto, a lo largo de la ruta, primero; como mucho `maximo` calles.
    /// `ventana`: los metros de la ruta entera que cubre el tramo, desde la moto
    /// (Cruce.recorrido); un cruce con recorrido fuera de ella no cuenta, aunque
    /// caiga cerca del tramo (otra pasada por la misma calle o un cruce ya
    /// pasado; revisión de la 0.10.0). Tampoco el que queda en la moto o detrás.
    public static func calles(
        de cruces: [Cruce],
        ruta: [PuntoRuta],
        sentido: Double,
        maximo: Int = MensajeCruces.maximoCalles,
        ventana: ClosedRange<Double>? = nil
    ) -> [CalleCruce] {
        guard let origen = ruta.first, ruta.count >= 2, maximo > 0, !cruces.isEmpty else { return [] }

        // La ruta en metros (proyección local, como aEjesMoto) y lo recorrido
        // hasta cada punto
        let coseno = cos(origen.latitud * .pi / 180)
        func plano(_ punto: PuntoRuta) -> (x: Double, y: Double) {
            ((punto.longitud - origen.longitud) * Trazo.metrosPorGrado * coseno,
             (punto.latitud - origen.latitud) * Trazo.metrosPorGrado)
        }
        let planos = ruta.map { plano($0) }
        var recorrido = [0.0]
        var minimoX = planos[0].x, maximoX = planos[0].x
        var minimoY = planos[0].y, maximoY = planos[0].y
        for i in 1..<planos.count {
            recorrido.append(recorrido[i - 1] + hypot(planos[i].x - planos[i - 1].x, planos[i].y - planos[i - 1].y))
            minimoX = min(minimoX, planos[i].x)
            maximoX = max(maximoX, planos[i].x)
            minimoY = min(minimoY, planos[i].y)
            maximoY = max(maximoY, planos[i].y)
        }

        // Cada cruce, en el segmento más cercano (el primero, si hay empate);
        // un recuadro alrededor de la ruta descarta deprisa los lejanos, que con
        // una ruta larga son casi todos
        var encontrados: [(recorrido: Double, orden: Int)] = []
        for (orden, cruce) in cruces.enumerated() {
            if let ventana, let enRuta = cruce.recorrido,
               enRuta <= ventana.lowerBound || enRuta > ventana.upperBound + tolerancia {
                continue
            }
            let p = plano(cruce.punto)
            guard p.x >= minimoX - tolerancia, p.x <= maximoX + tolerancia,
                  p.y >= minimoY - tolerancia, p.y <= maximoY + tolerancia
            else { continue }
            var mejor = tolerancia
            var donde: Double?
            for i in 0..<(planos.count - 1) {
                let a = planos[i]
                let b = planos[i + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let largo2 = dx * dx + dy * dy
                let t = largo2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / largo2)) : 0
                let distancia = hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
                if distancia < mejor {
                    mejor = distancia
                    donde = recorrido[i] + t * largo2.squareRoot()
                }
            }
            // En la moto (o detrás, recortado a ella) no: ya se está pasando
            if let donde, donde >= 1 {
                encontrados.append((recorrido: donde, orden: orden))
            }
        }
        encontrados.sort { $0.recorrido != $1.recorrido ? $0.recorrido < $1.recorrido : $0.orden < $1.orden }

        var calles: [CalleCruce] = []
        for encontrado in encontrados {
            let cruce = cruces[encontrado.orden]
            guard let enEjes = Trazo.aEjesMoto([cruce.punto], origen: origen, rumbo: sentido).first else { continue }
            for rumbo in cruce.rumbos {
                guard calles.count < maximo else { return calles }
                calles.append(CalleCruce(x: enEjes.x, y: enEjes.y, direccion: direccion(rumbo: rumbo, sentido: sentido)))
            }
        }
        return calles
    }

    /// Dirección de una calle respecto al sentido de la marcha, en 1/256 de
    /// vuelta y en sentido horario: 0 delante, 64 derecha, 128 atrás, 192
    /// izquierda.
    static func direccion(rumbo: Double, sentido: Double) -> UInt8 {
        guard rumbo.isFinite, sentido.isFinite else { return 0 }
        var relativo = (rumbo - sentido).truncatingRemainder(dividingBy: 360)
        if relativo < 0 { relativo += 360 }
        return UInt8(Int((relativo * 256 / 360).rounded()) % 256)
    }
}
