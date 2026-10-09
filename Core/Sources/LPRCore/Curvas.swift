import Foundation

/// Un punto de una geometría, en grados.
public struct PuntoRuta: Equatable {
    public var latitud: Double
    public var longitud: Double

    public init(latitud: Double, longitud: Double) {
        self.latitud = latitud
        self.longitud = longitud
    }
}

/// Cuánto gira una ruta a lo largo de sus carreteras.
public struct Sinuosidad: Equatable {
    /// Curvas de al menos `giroMinimoCurva` grados.
    public var curvas: Int
    /// Grados girados por kilómetro (solo los giros que superan el ruido).
    public var gradosPorKm: Double
    public var metros: Double

    public init(curvas: Int, gradosPorKm: Double, metros: Double) {
        self.curvas = curvas
        self.gradosPorKm = gradosPorKm
        self.metros = metros
    }
}

/// Cuenta las curvas de una ruta a partir de su trazado. Valhalla no las mide,
/// así que «la más divertida» se elige con esto (Eleccion.swift).
///
/// Se mide cada tramo por separado (un tramo es la carretera entre dos
/// maniobras), para que los giros en los cruces no cuenten como curvas. Cada
/// tramo se remuestrea cada `paso` metros; una curva es una racha de cambios de
/// rumbo en el mismo sentido que suma al menos `giroMinimoCurva` grados, y los
/// cambios de menos de `giroMinimoPorPaso` grados se toman como ruido o recta.
public enum Curvas {
    public static func medir(
        tramos: [[PuntoRuta]],
        paso: Double = 25,
        giroMinimoPorPaso: Double = 4,
        giroMinimoCurva: Double = 30
    ) -> Sinuosidad {
        var curvas = 0
        var grados = 0.0
        var metros = 0.0

        for tramo in tramos {
            let (puntos, longitud) = remuestrear(tramo, paso: paso)
            metros += longitud
            guard puntos.count >= 3 else { continue }

            var rumbos: [Double] = []
            for indice in 0..<(puntos.count - 1) {
                rumbos.append(rumbo(desde: puntos[indice], hasta: puntos[indice + 1]))
            }

            var sentido = 0
            var acumulado = 0.0
            func cerrarCurva() {
                if acumulado >= giroMinimoCurva {
                    curvas += 1
                }
                sentido = 0
                acumulado = 0
            }

            for indice in 0..<(rumbos.count - 1) {
                let giro = normalizar(rumbos[indice + 1] - rumbos[indice])
                if abs(giro) < giroMinimoPorPaso {
                    cerrarCurva()
                    continue
                }
                grados += abs(giro)
                let sentidoGiro = giro > 0 ? 1 : -1
                if sentidoGiro != sentido {
                    cerrarCurva()
                    sentido = sentidoGiro
                }
                acumulado += abs(giro)
            }
            cerrarCurva()
        }

        return Sinuosidad(
            curvas: curvas,
            gradosPorKm: metros > 0 ? grados / (metros / 1000) : 0,
            metros: metros
        )
    }

    /// Puntos cada `paso` metros a lo largo del tramo, en metros respecto a su
    /// primer punto (proyección local, suficiente para tramos de carretera), y la
    /// longitud total.
    static func remuestrear(_ tramo: [PuntoRuta], paso: Double) -> ([(x: Double, y: Double)], Double) {
        guard tramo.count >= 2, let origen = tramo.first else { return ([], 0) }
        let metrosPorGrado = 111_320.0
        let cosenoLatitud = cos(origen.latitud * .pi / 180)
        let planos = tramo.map {
            (x: ($0.longitud - origen.longitud) * metrosPorGrado * cosenoLatitud,
             y: ($0.latitud - origen.latitud) * metrosPorGrado)
        }

        var salida = [planos[0]]
        var total = 0.0
        var hastaSiguiente = paso
        for indice in 1..<planos.count {
            var desde = planos[indice - 1]
            let hasta = planos[indice]
            var segmento = hypot(hasta.x - desde.x, hasta.y - desde.y)
            total += segmento
            while segmento >= hastaSiguiente, segmento > 0 {
                let t = hastaSiguiente / segmento
                let punto = (x: desde.x + (hasta.x - desde.x) * t, y: desde.y + (hasta.y - desde.y) * t)
                salida.append(punto)
                desde = punto
                segmento -= hastaSiguiente
                hastaSiguiente = paso
            }
            hastaSiguiente -= segmento
        }
        return (salida, total)
    }

    /// Rumbo en grados desde el norte, en sentido horario.
    static func rumbo(desde a: (x: Double, y: Double), hasta b: (x: Double, y: Double)) -> Double {
        atan2(b.x - a.x, b.y - a.y) * 180 / .pi
    }

    /// Diferencia de rumbo entre -180 y 180 (positiva, a la derecha).
    static func normalizar(_ grados: Double) -> Double {
        var resultado = grados.truncatingRemainder(dividingBy: 360)
        if resultado > 180 { resultado -= 360 }
        if resultado < -180 { resultado += 360 }
        return resultado
    }
}
