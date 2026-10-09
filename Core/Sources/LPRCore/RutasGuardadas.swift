import Foundation

/// Una ruta hecha, para volver a cargarla desde la pestaña «Rutas»: el
/// destino, el tipo de ruta elegido y las preferencias con las que se calculó
/// (a petición del autor, 2026-10-10: «que solo falte darle a iniciar»). Lo
/// demás (km, tiempo y curvas de la ruta propuesta) es para la lista.
public struct RutaGuardada: Codable, Equatable, Identifiable {
    public var id: UUID
    public var nombre: String
    public var descripcion: String
    public var latitud: Double
    public var longitud: Double
    /// El tipo de ruta elegido (en la app, el rawValue de TipoVariante).
    public var tipo: String
    public var evitarPeajes: Bool
    public var evitarAutopistas: Bool
    /// Margen de tiempo sobre la más rápida (Eleccion).
    public var margen: Double
    public var metros: Double
    public var segundos: Double
    public var curvas: Int
    /// Metros de peaje y de autopista de la ruta propuesta, como los enseña
    /// la app en su tarjeta (desde la 0.18.0; las guardadas antes, 0).
    public var metrosPeaje: Double
    public var metrosAutopista: Double
    /// La última vez que se inició.
    public var fecha: Date
    /// Cuántas veces se ha iniciado.
    public var veces: Int

    public init(
        id: UUID = UUID(),
        nombre: String,
        descripcion: String = "",
        latitud: Double,
        longitud: Double,
        tipo: String,
        evitarPeajes: Bool,
        evitarAutopistas: Bool,
        margen: Double,
        metros: Double,
        segundos: Double,
        curvas: Int,
        metrosPeaje: Double = 0,
        metrosAutopista: Double = 0,
        fecha: Date,
        veces: Int = 1
    ) {
        self.id = id
        self.nombre = nombre
        self.descripcion = descripcion
        self.latitud = latitud
        self.longitud = longitud
        self.tipo = tipo
        self.evitarPeajes = evitarPeajes
        self.evitarAutopistas = evitarAutopistas
        self.margen = margen
        self.metros = metros
        self.segundos = segundos
        self.curvas = curvas
        self.metrosPeaje = metrosPeaje
        self.metrosAutopista = metrosAutopista
        self.fecha = fecha
        self.veces = veces
    }

    /// La misma ruta: destino a `RutasGuardadas.mismoSitio` metros o menos y
    /// el mismo tipo y preferencias (con otro tipo o margen sale otra ruta).
    public func esLaMisma(que otra: RutaGuardada) -> Bool {
        tipo == otra.tipo
            && evitarPeajes == otra.evitarPeajes
            && evitarAutopistas == otra.evitarAutopistas
            && abs(margen - otra.margen) < 0.001
            && Trazo.distancia(PuntoRuta(latitud: latitud, longitud: longitud),
                               PuntoRuta(latitud: otra.latitud, longitud: otra.longitud)) <= RutasGuardadas.mismoSitio
    }
}

extension RutaGuardada {
    private enum Claves: String, CodingKey {
        case id, nombre, descripcion, latitud, longitud, tipo, evitarPeajes, evitarAutopistas, margen, metros,
             segundos, curvas, metrosPeaje, metrosAutopista, fecha, veces
    }

    /// Las guardadas por la 0.17 no llevan peaje ni autopista: 0, para no
    /// perder la lista al leerla.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Claves.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            nombre: try c.decode(String.self, forKey: .nombre),
            descripcion: try c.decodeIfPresent(String.self, forKey: .descripcion) ?? "",
            latitud: try c.decode(Double.self, forKey: .latitud),
            longitud: try c.decode(Double.self, forKey: .longitud),
            tipo: try c.decode(String.self, forKey: .tipo),
            evitarPeajes: try c.decode(Bool.self, forKey: .evitarPeajes),
            evitarAutopistas: try c.decode(Bool.self, forKey: .evitarAutopistas),
            margen: try c.decode(Double.self, forKey: .margen),
            metros: try c.decode(Double.self, forKey: .metros),
            segundos: try c.decode(Double.self, forKey: .segundos),
            curvas: try c.decode(Int.self, forKey: .curvas),
            metrosPeaje: try c.decodeIfPresent(Double.self, forKey: .metrosPeaje) ?? 0,
            metrosAutopista: try c.decodeIfPresent(Double.self, forKey: .metrosAutopista) ?? 0,
            fecha: try c.decode(Date.self, forKey: .fecha),
            veces: try c.decodeIfPresent(Int.self, forKey: .veces) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Claves.self)
        try c.encode(id, forKey: .id)
        try c.encode(nombre, forKey: .nombre)
        try c.encode(descripcion, forKey: .descripcion)
        try c.encode(latitud, forKey: .latitud)
        try c.encode(longitud, forKey: .longitud)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(evitarPeajes, forKey: .evitarPeajes)
        try c.encode(evitarAutopistas, forKey: .evitarAutopistas)
        try c.encode(margen, forKey: .margen)
        try c.encode(metros, forKey: .metros)
        try c.encode(segundos, forKey: .segundos)
        try c.encode(curvas, forKey: .curvas)
        try c.encode(metrosPeaje, forKey: .metrosPeaje)
        try c.encode(metrosAutopista, forKey: .metrosAutopista)
        try c.encode(fecha, forKey: .fecha)
        try c.encode(veces, forKey: .veces)
    }
}

/// La lista de rutas hechas, de la más reciente a la más antigua.
public enum RutasGuardadas {
    /// Como mucho se guardan estas (supuesto: las de un buen puñado de salidas).
    public static let maximo = 30
    /// Metros entre dos destinos para tomarlos por el mismo (supuesto: Apple
    /// Maps puede dar el mismo sitio con unos metros de diferencia).
    public static let mismoSitio = 100.0

    /// Huecos de los accesos directos (los que salen en el cuadro).
    public static let huecos = 3

    /// La lista con `nueva` la primera. Si ya estaba (la misma entrada, con
    /// su id, como al cargarla desde la lista; o la misma ruta, `esLaMisma`),
    /// la sustituye conservando su id y sumando una vez; si pasan de
    /// `maximo`, se quitan las más antiguas que no estén en `conservar` (los
    /// accesos directos).
    public static func anadir(_ nueva: RutaGuardada, a lista: [RutaGuardada], maximo: Int = maximo,
                              conservar: Set<UUID> = []) -> [RutaGuardada] {
        var nueva = nueva
        var resto = lista
        if let i = resto.firstIndex(where: { $0.id == nueva.id }) ?? resto.firstIndex(where: { $0.esLaMisma(que: nueva) }) {
            nueva.id = resto[i].id
            nueva.veces = resto[i].veces + 1
            resto.remove(at: i)
        }
        var todas = [nueva] + resto
        while todas.count > max(0, maximo), let i = todas.lastIndex(where: { !conservar.contains($0.id) }) {
            todas.remove(at: i)
        }
        return todas
    }

    /// Las que salen en el cuadro (a petición del autor, 2026-10-10): los
    /// accesos directos, en el orden de sus huecos, y los huecos vacíos (o de
    /// una ruta que ya no está) con las más recientes que no sean ya acceso
    /// directo. Como mucho `huecos`.
    public static func paraElCuadro(_ lista: [RutaGuardada], accesos: [UUID?]) -> [RutaGuardada] {
        let fijadas = accesos.prefix(huecos).compactMap { id in lista.first { $0.id == id } }
        let ids = Set(fijadas.map(.id))
        let recientes = lista.filter { !ids.contains($0.id) }
        return Array((fijadas + recientes).prefix(huecos))
    }

    public static func codificar(_ lista: [RutaGuardada]) throws -> Data {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        return try codificador.encode(lista)
    }

    /// Vacía si los datos no se pueden leer.
    public static func decodificar(_ datos: Data) -> [RutaGuardada] {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return (try? decodificador.decode([RutaGuardada].self, from: datos)) ?? []
    }
}
