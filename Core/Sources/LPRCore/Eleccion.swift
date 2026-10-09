import Foundation

/// Una ruta entre las que elegir: lo que tarda, sus curvas y cuánto lleva sin
/// asfaltar.
public struct Candidata: Equatable {
    public var segundos: Double
    public var sinuosidad: Sinuosidad
    /// Para «Por tierra»: sin contar la tierra de salida ni de llegada
    /// (RutaValhalla.metrosSinAsfaltarEnMedio).
    public var metrosSinAsfaltar: Double
    /// Lleva tierra fuera del principio y del final (RutaValhalla).
    public var tierraEnMedio: Bool

    public init(
        segundos: Double,
        sinuosidad: Sinuosidad,
        metrosSinAsfaltar: Double = 0,
        tierraEnMedio: Bool = false
    ) {
        self.segundos = segundos
        self.sinuosidad = sinuosidad
        self.metrosSinAsfaltar = metrosSinAsfaltar
        self.tierraEnMedio = tierraEnMedio
    }
}

/// Qué candidata va en cada propuesta (índices). Pueden coincidir: la más
/// rápida puede ser también la más divertida.
public struct Eleccion: Equatable {
    public var rapida: Int
    public var divertida: Int
    /// Solo si se pide buscar tierra y alguna candidata dentro del margen lleva
    /// al menos `Eleccion.minimoTierra` metros sin asfaltar.
    public var porTierra: Int?
    /// Todas las candidatas llevan tierra en medio: la más rápida y la más
    /// divertida también.
    public var todasConTierra: Bool

    public init(rapida: Int, divertida: Int, porTierra: Int? = nil, todasConTierra: Bool = false) {
        self.rapida = rapida
        self.divertida = divertida
        self.porTierra = porTierra
        self.todasConTierra = todasConTierra
    }

    /// Margen de tiempo por defecto sobre la más rápida (0,25 = un 25 % más). Es
    /// un supuesto; el usuario lo cambia con la barra de la app.
    public static let margenPorDefecto = 0.25

    /// Metros sin asfaltar a partir de los que una ruta cuenta como «por
    /// tierra». Supuesto, pendiente de ajustar con rutas reales.
    public static let minimoTierra = 500.0

    /// La más rápida y la más divertida se eligen entre las candidatas sin
    /// tierra en medio (entre todas, si ninguna va solo por asfalto):
    /// - la más rápida es la que menos tarda;
    /// - la más divertida, la de más curvas entre las que no pasan del margen
    ///   de tiempo sobre la más rápida; a igualdad, la de más grados por km y
    ///   después la que menos tarda.
    /// La de tierra (si `buscarTierra`) se elige entre todas las que no pasan
    /// del margen: la de más metros sin asfaltar; a igualdad, la de más curvas y
    /// después la que menos tarda.
    /// Devuelve nil si no hay candidatas.
    public static func elegir(
        _ candidatas: [Candidata],
        margen: Double = margenPorDefecto,
        buscarTierra: Bool = false
    ) -> Eleccion? {
        let asfalto = candidatas.indices.filter { !candidatas[$0].tierraEnMedio }
        let base = asfalto.isEmpty ? Array(candidatas.indices) : asfalto
        guard let rapida = base.min(by: { candidatas[$0].segundos < candidatas[$1].segundos })
        else { return nil }
        let limite = candidatas[rapida].segundos * (1 + max(0, margen))
        let dentro = base.filter { candidatas[$0].segundos <= limite }

        let divertida = dentro.max { a, b in
            let x = candidatas[a]
            let y = candidatas[b]
            if x.sinuosidad.curvas != y.sinuosidad.curvas {
                return x.sinuosidad.curvas < y.sinuosidad.curvas
            }
            if x.sinuosidad.gradosPorKm != y.sinuosidad.gradosPorKm {
                return x.sinuosidad.gradosPorKm < y.sinuosidad.gradosPorKm
            }
            return x.segundos > y.segundos
        } ?? rapida

        var porTierra: Int?
        if buscarTierra {
            porTierra = candidatas.indices
                .filter { candidatas[$0].segundos <= limite && candidatas[$0].metrosSinAsfaltar >= minimoTierra }
                .max { a, b in
                    let x = candidatas[a]
                    let y = candidatas[b]
                    if x.metrosSinAsfaltar != y.metrosSinAsfaltar {
                        return x.metrosSinAsfaltar < y.metrosSinAsfaltar
                    }
                    if x.sinuosidad.curvas != y.sinuosidad.curvas {
                        return x.sinuosidad.curvas < y.sinuosidad.curvas
                    }
                    return x.segundos > y.segundos
                }
        }
        return Eleccion(
            rapida: rapida,
            divertida: divertida,
            porTierra: porTierra,
            todasConTierra: asfalto.isEmpty
        )
    }
}
