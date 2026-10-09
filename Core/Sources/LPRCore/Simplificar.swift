import Foundation

/// Simplificación de un trazado para dibujarlo en el mapa. Con poco zoom el mapa
/// base dibuja las carreteras generalizadas, y un trazo con todas las curvas de
/// una carretera de montaña se sale de ellas; con más zoom hay que seguir la
/// carretera. Por eso el trazo se simplifica según los metros que ocupa un
/// punto de la pantalla (docs/DECISIONES.md).
public enum Simplificar {
    /// Douglas-Peucker: quita los puntos que se separan menos de `tolerancia`
    /// metros del trazo simplificado. Conserva siempre el primero y el último.
    /// Con tolerancia 0 o menos, o con menos de tres puntos, devuelve el trazado
    /// tal cual.
    public static func douglasPeucker(_ puntos: [PuntoRuta], tolerancia: Double) -> [PuntoRuta] {
        guard tolerancia > 0, puntos.count > 2 else { return puntos }

        // Proyección local en metros, con la latitud media (suficiente para el
        // error que se busca, de metros)
        let latitudMedia = puntos.reduce(0) { $0 + $1.latitud } / Double(puntos.count)
        let metrosPorGrado = 111_320.0
        let coseno = cos(latitudMedia * .pi / 180)
        let planos = puntos.map { (x: $0.longitud * metrosPorGrado * coseno, y: $0.latitud * metrosPorGrado) }

        var conservar = [Bool](repeating: false, count: puntos.count)
        conservar[0] = true
        conservar[puntos.count - 1] = true

        // Sin recursión, para trazados de miles de puntos
        var pendientes = [(0, puntos.count - 1)]
        while let tramo = pendientes.popLast() {
            let (desde, hasta) = tramo
            guard hasta - desde > 1 else { continue }
            var maxima = -1.0
            var indiceMaximo = desde
            for indice in (desde + 1)..<hasta {
                let distancia = distanciaASegmento(planos[indice], planos[desde], planos[hasta])
                if distancia > maxima {
                    maxima = distancia
                    indiceMaximo = indice
                }
            }
            if maxima > tolerancia {
                conservar[indiceMaximo] = true
                pendientes.append((desde, indiceMaximo))
                pendientes.append((indiceMaximo, hasta))
            }
        }
        return puntos.indices.filter { conservar[$0] }.map { puntos[$0] }
    }

    /// Distancia en metros de `punto` al trazado (al segmento más cercano); nil
    /// si el trazado está vacío.
    public static func distancia(de punto: PuntoRuta, a trazado: [PuntoRuta]) -> Double? {
        guard let primero = trazado.first else { return nil }
        let metrosPorGrado = 111_320.0
        let coseno = cos(punto.latitud * .pi / 180)
        func plano(_ p: PuntoRuta) -> (x: Double, y: Double) {
            ((p.longitud - punto.longitud) * metrosPorGrado * coseno, (p.latitud - punto.latitud) * metrosPorGrado)
        }
        let origen = (x: 0.0, y: 0.0)
        guard trazado.count > 1 else {
            let p = plano(primero)
            return hypot(p.x, p.y)
        }
        var minima = Double.infinity
        var anterior = plano(primero)
        for siguiente in trazado.dropFirst() {
            let actual = plano(siguiente)
            minima = min(minima, distanciaASegmento(origen, anterior, actual))
            anterior = actual
        }
        return minima
    }

    /// Distancia en metros de `p` al segmento `a`–`b`.
    static func distanciaASegmento(
        _ p: (x: Double, y: Double),
        _ a: (x: Double, y: Double),
        _ b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let longitud2 = dx * dx + dy * dy
        guard longitud2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / longitud2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
