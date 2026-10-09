import Foundation

/// Una ruta de Valhalla tal como la usa la app para proponerla: medidas,
/// trazado y lo que lleva de peaje y sin asfaltar.
public struct RutaValhalla: Equatable {
    public var metros: Double
    public var segundos: Double
    /// El trazado completo.
    public var puntos: [PuntoRuta]
    /// El trazado de cada maniobra, sin las rotondas, para contar curvas.
    public var tramosParaCurvas: [[PuntoRuta]]
    /// Metros de las maniobras con algún tramo de peaje. Es un máximo: Valhalla
    /// marca la maniobra entera.
    public var metrosPeaje: Double
    /// Metros de las maniobras con algún tramo sin asfaltar. También un máximo.
    public var metrosSinAsfaltar: Double
    /// Hay tierra entre la primera y la última maniobra asfaltada de algún
    /// tramo. La tierra seguida desde la salida o hasta la llegada no cuenta,
    /// como en `exclude_unpaved` de Valhalla. Es una aproximación por maniobra:
    /// la tierra dentro de esas maniobras de salida o de llegada no se ve,
    /// aunque tenga asfalto a los dos lados.
    public var tierraEnMedio: Bool
    /// Metros de las maniobras con tierra en medio (un máximo). Si un tramo va
    /// entero sin asfaltar, cuenta entero.
    public var metrosSinAsfaltarEnMedio: Double

    public init(
        metros: Double,
        segundos: Double,
        puntos: [PuntoRuta],
        tramosParaCurvas: [[PuntoRuta]],
        metrosPeaje: Double,
        metrosSinAsfaltar: Double,
        tierraEnMedio: Bool,
        metrosSinAsfaltarEnMedio: Double
    ) {
        self.metros = metros
        self.segundos = segundos
        self.puntos = puntos
        self.tramosParaCurvas = tramosParaCurvas
        self.metrosPeaje = metrosPeaje
        self.metrosSinAsfaltar = metrosSinAsfaltar
        self.tierraEnMedio = tierraEnMedio
        self.metrosSinAsfaltarEnMedio = metrosSinAsfaltarEnMedio
    }
}

/// Respuesta de /route de Valhalla en su formato propio (`"format": "json"`).
/// A diferencia del formato OSRM, marca por maniobra los tramos sin asfaltar
/// (`rough`) y de peaje (`toll`) (docs/DECISIONES.md). Las longitudes vienen en
/// km porque la app pide `"units": "kilometers"`.
public enum RespuestaValhalla {
    /// Valhalla: tipo de maniobra «entrar en la rotonda» (kRoundaboutEnter).
    static let tipoEntrarRotonda = 26
    /// Una rotonda más larga que esto se mide como carretera normal.
    static let metrosMaximosRotonda = 300.0

    /// Las rutas, en el orden de Valhalla: la principal y después las
    /// alternativas. Es el mismo orden que en el formato OSRM.
    public static func rutas(de datos: Data) throws -> [RutaValhalla] {
        let decodificador = JSONDecoder()
        decodificador.keyDecodingStrategy = .convertFromSnakeCase
        let respuesta = try decodificador.decode(Respuesta.self, from: datos)
        let viajes = [respuesta.trip] + (respuesta.alternates ?? []).map(\.trip)
        return viajes.map { ruta($0) }
    }

    /// El mensaje de error de Valhalla (`"error"`), si lo hay.
    public static func mensajeDeError(_ datos: Data) -> String? {
        struct Fallo: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Fallo.self, from: datos))?.error
    }

    static func ruta(_ viaje: Viaje) -> RutaValhalla {
        var puntos: [PuntoRuta] = []
        var tramos: [[PuntoRuta]] = []
        var metrosPeaje = 0.0
        var metrosSinAsfaltar = 0.0
        var tierraEnMedio = false
        var metrosSinAsfaltarEnMedio = 0.0

        for tramo in viaje.legs {
            let forma = Polilinea.decodificar(tramo.shape, precision: 6)
            // Los tramos comparten el punto de unión
            if let ultimo = puntos.last, forma.first == ultimo {
                puntos += forma.dropFirst()
            } else {
                puntos += forma
            }

            // Tierra en medio: la que queda entre la primera y la última maniobra
            // asfaltada (con longitud)
            let conLongitud = tramo.maneuvers.indices.filter { tramo.maneuvers[$0].length > 0 }
            let asfaltadas = conLongitud.filter { tramo.maneuvers[$0].rough != true }
            for indice in conLongitud where tramo.maneuvers[indice].rough == true {
                let enMedio: Bool
                if let primera = asfaltadas.first, let ultima = asfaltadas.last {
                    enMedio = indice > primera && indice < ultima
                } else {
                    // El tramo entero va sin asfaltar
                    enMedio = false
                    metrosSinAsfaltarEnMedio += tramo.maneuvers[indice].length * 1000
                }
                if enMedio {
                    tierraEnMedio = true
                    metrosSinAsfaltarEnMedio += tramo.maneuvers[indice].length * 1000
                }
            }

            for maniobra in tramo.maneuvers {
                let metros = maniobra.length * 1000
                if maniobra.toll == true {
                    metrosPeaje += metros
                }
                if maniobra.rough == true {
                    metrosSinAsfaltar += metros
                }
                let esRotonda = (maniobra.type == tipoEntrarRotonda || maniobra.roundaboutExitCount != nil)
                    && metros < metrosMaximosRotonda
                guard !esRotonda,
                      maniobra.beginShapeIndex >= 0,
                      maniobra.beginShapeIndex < maniobra.endShapeIndex,
                      maniobra.endShapeIndex < forma.count
                else { continue }
                tramos.append(Array(forma[maniobra.beginShapeIndex...maniobra.endShapeIndex]))
            }
        }

        return RutaValhalla(
            metros: viaje.summary.length * 1000,
            segundos: viaje.summary.time,
            puntos: puntos,
            tramosParaCurvas: tramos,
            metrosPeaje: metrosPeaje,
            metrosSinAsfaltar: metrosSinAsfaltar,
            tierraEnMedio: tierraEnMedio,
            metrosSinAsfaltarEnMedio: metrosSinAsfaltarEnMedio
        )
    }

    // Solo los campos que usa la app
    struct Respuesta: Decodable {
        let trip: Viaje
        let alternates: [Alternativa]?
    }

    struct Alternativa: Decodable {
        let trip: Viaje
    }

    struct Viaje: Decodable {
        let legs: [Tramo]
        let summary: Resumen
    }

    struct Resumen: Decodable {
        let length: Double
        let time: Double
    }

    struct Tramo: Decodable {
        let shape: String
        let maneuvers: [Maniobra]
    }

    struct Maniobra: Decodable {
        let type: Int
        let length: Double
        let beginShapeIndex: Int
        let endShapeIndex: Int
        let toll: Bool?
        let rough: Bool?
        let roundaboutExitCount: Int?
    }
}
