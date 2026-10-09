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

/// La lista de rutas hechas, de la más reciente a la más antigua.
public enum RutasGuardadas {
    /// Como mucho se guardan estas (supuesto: las de un buen puñado de salidas).
    public static let maximo = 30
    /// Metros entre dos destinos para tomarlos por el mismo (supuesto: Apple
    /// Maps puede dar el mismo sitio con unos metros de diferencia).
    public static let mismoSitio = 100.0

    /// La lista con `nueva` la primera. Si ya estaba la misma ruta
    /// (`esLaMisma`), la sustituye conservando su id y sumando una vez; si
    /// pasan de `maximo`, se quitan las más antiguas.
    public static func anadir(_ nueva: RutaGuardada, a lista: [RutaGuardada], maximo: Int = maximo) -> [RutaGuardada] {
        var nueva = nueva
        var resto = lista
        if let i = resto.firstIndex(where: { $0.esLaMisma(que: nueva) }) {
            nueva.id = resto[i].id
            nueva.veces = resto[i].veces + 1
            resto.remove(at: i)
        }
        return Array(([nueva] + resto).prefix(max(0, maximo)))
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
