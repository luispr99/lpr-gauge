import Foundation

/// Punto en metros en los ejes de la moto: x a la derecha, y hacia delante.
public struct PuntoPlano: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// El tramo de ruta por delante que se dibuja en el cuadro (TRAZO,
/// docs/PROTOCOLO.md §7 ter): desde la posición de la moto sobre la ruta hasta
/// unos metros por delante, en los ejes de la moto (el sentido de la marcha
/// hacia arriba) y simplificado para que quepa en un mensaje.
public enum Trazo {
    static let metrosPorGrado = 111_320.0

    /// Metros entre dos puntos cercanos (proyección local, como Curvas y
    /// Simplificar).
    public static func distancia(_ a: PuntoRuta, _ b: PuntoRuta) -> Double {
        let coseno = cos((a.latitud + b.latitud) / 2 * .pi / 180)
        return hypot((b.longitud - a.longitud) * metrosPorGrado * coseno, (b.latitud - a.latitud) * metrosPorGrado)
    }

    /// Rumbo de `a` a `b`, en grados desde el norte en sentido horario (0-360).
    public static func rumbo(de a: PuntoRuta, a b: PuntoRuta) -> Double {
        let coseno = cos((a.latitud + b.latitud) / 2 * .pi / 180)
        var grados = atan2((b.longitud - a.longitud) * coseno, b.latitud - a.latitud) * 180 / .pi
        if grados < 0 { grados += 360 }
        return grados
    }

    /// La ruta desde `origen` (la posición de la moto sobre el paso actual)
    /// hasta `metros` por delante, siguiendo los pasos: del primero, desde el
    /// punto `indice + 1` (Ferrostar da el origen del segmento en el que está la
    /// moto; nil: el paso no sirve y se empieza en el siguiente); de los demás,
    /// enteros. Sin puntos repetidos (a menos de 0,5 m, como el vértice que
    /// comparten dos pasos seguidos). El último se interpola para cortar justo
    /// en `metros`, salvo que la ruta acabe antes.
    public static func recorrer(pasos: [[PuntoRuta]], indice: Int?, desde origen: PuntoRuta, metros total: Double) -> [PuntoRuta] {
        var salida = [origen]
        var previo = origen
        var acumulado = 0.0
        for (numero, paso) in pasos.enumerated() {
            let inicio = numero == 0 ? (indice.map { $0 + 1 } ?? paso.count) : 0
            guard inicio >= 0, inicio < paso.count else { continue }
            for punto in paso[inicio...] {
                let tramo = distancia(previo, punto)
                if tramo < 0.5 { continue }
                if acumulado + tramo >= total {
                    let t = (total - acumulado) / tramo
                    salida.append(PuntoRuta(
                        latitud: previo.latitud + (punto.latitud - previo.latitud) * t,
                        longitud: previo.longitud + (punto.longitud - previo.longitud) * t
                    ))
                    return salida
                }
                salida.append(punto)
                acumulado += tramo
                previo = punto
            }
        }
        return salida
    }

    /// A los ejes de la moto: el origen en `origen` y el `rumbo` (grados desde
    /// el norte) hacia arriba.
    public static func aEjesMoto(_ puntos: [PuntoRuta], origen: PuntoRuta, rumbo: Double) -> [PuntoPlano] {
        let coseno = cos(origen.latitud * .pi / 180)
        let angulo = rumbo * .pi / 180
        return puntos.map { punto in
            let este = (punto.longitud - origen.longitud) * metrosPorGrado * coseno
            let norte = (punto.latitud - origen.latitud) * metrosPorGrado
            return PuntoPlano(x: este * cos(angulo) - norte * sin(angulo),
                              y: este * sin(angulo) + norte * cos(angulo))
        }
    }

    /// El tramo listo para el cuadro: `metros` de ruta por delante, en los ejes
    /// de la moto. El sentido de la marcha es el rumbo de la ruta hasta el punto
    /// que está `anticipacion` metros por delante (más estable que el del GPS y
    /// que el de un solo segmento). Se simplifica hasta que quepan
    /// `maximoPuntos`. `giro` es el punto del próximo giro (el final del paso
    /// actual): su índice en el tramo, si está (a menos de 10 m de un punto).
    /// Nil si no hay al menos dos puntos.
    public static func tramo(
        pasos: [[PuntoRuta]],
        indice: Int?,
        desde origen: PuntoRuta,
        metros total: Double,
        giro: PuntoRuta?,
        anticipacion: Double = 25,
        maximoPuntos: Int = MensajeTrazo.maximoPuntos
    ) -> (puntos: [PuntoPlano], giro: Int?)? {
        let ruta = recorrer(pasos: pasos, indice: indice, desde: origen, metros: total)
        guard ruta.count >= 2 else { return nil }
        let adelante = recorrer(pasos: pasos, indice: indice, desde: origen, metros: anticipacion).last ?? ruta[1]
        let sentido = distancia(origen, adelante) >= 1 ? rumbo(de: origen, a: adelante) : rumbo(de: origen, a: ruta[1])

        let limite = max(2, maximoPuntos)
        var tolerancia = 2.0
        var simple = Simplificar.douglasPeucker(ruta, tolerancia: tolerancia)
        var intentos = 0
        while simple.count > limite && intentos < 40 {
            tolerancia *= 1.5
            simple = Simplificar.douglasPeucker(ruta, tolerancia: tolerancia)
            intentos += 1
        }
        if simple.count > limite {
            simple = Array(simple.prefix(limite))
        }

        var indiceGiro: Int?
        if let giro {
            var mejor = 10.0
            for (numero, punto) in simple.enumerated() where numero > 0 {
                let d = distancia(punto, giro)
                if d <= mejor {
                    mejor = d
                    indiceGiro = numero
                }
            }
        }
        return (aEjesMoto(simple, origen: origen, rumbo: sentido), indiceGiro)
    }
}
