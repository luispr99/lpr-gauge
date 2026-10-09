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

/// Un tramo listo para el cuadro (Trazo.tramo).
public struct TramoTrazo: Equatable {
    /// Simplificado y en los ejes de la moto (TRAZO).
    public var puntos: [PuntoPlano]
    /// Índice del próximo giro en `puntos`, o nil.
    public var giro: Int?
    /// La misma ruta sin simplificar, en grados, desde la posición de la moto
    /// (el primer punto): para buscar los cruces del tramo (Cruces.calles).
    public var ruta: [PuntoRuta]
    /// El sentido de la marcha de los ejes de la moto, en grados desde el norte.
    public var sentido: Double

    public init(puntos: [PuntoPlano], giro: Int?, ruta: [PuntoRuta], sentido: Double) {
        self.puntos = puntos
        self.giro = giro
        self.ruta = ruta
        self.sentido = sentido
    }
}

/// El tramo de ruta por delante que se dibuja en el cuadro (TRAZO,
/// docs/PROTOCOLO.md §7 ter): desde la posición de la moto sobre la ruta hasta
/// unos metros por delante, en los ejes de la moto (el sentido de la marcha
/// hacia arriba) y simplificado para que quepa en un mensaje.
public enum Trazo {
    static let metrosPorGrado = 111_320.0

    // MARK: Escala por niveles (§7 ter, v0.6)

    /// Metros desde la moto hasta el borde de arriba del dibujo en cada nivel
    /// de escala (bits 1-2 de los flags de TRAZO): 1 = 250, 2 = 500, 3 = 1000.
    public static func metros(nivel: Int) -> Double {
        switch nivel {
        case ...1: return 250
        case 2: return 500
        default: return 1000
        }
    }

    /// Metros de ruta que se mandan con cada nivel: 1,25 veces los del nivel,
    /// para que el tramo llegue hasta arriba del dibujo.
    public static func metrosTramo(nivel: Int) -> Double {
        metros(nivel: nivel) * 1.25
    }

    /// El nivel de escala según los metros que faltan para la maniobra: más de
    /// 500 m, el 3 (1000 m); de 500 a 200 m, el 2 (500 m); menos de 200 m, el
    /// 1 (250 m). Antes el tramo se acortaba al acercarse al giro y el cuadro
    /// se acercaba, y parecía que faltaba más (lo vio el autor el 2026-10-09).
    /// Dentro de una misma maniobra el nivel solo baja (`anterior`, el que
    /// llevaba; nil con una maniobra nueva): como mucho hay dos saltos y, entre
    /// ellos, el giro baja hacia la moto sin cambiar de escala, aunque el GPS
    /// haga crecer un poco la distancia. Sin distancia (NaN), se queda en el
    /// anterior.
    public static func nivel(metrosAlGiro metros: Double, anterior: Int?) -> Int {
        let segunDistancia: Int
        if metros.isNaN || metros > 500 {
            segunDistancia = 3
        } else if metros >= 200 {
            segunDistancia = 2
        } else {
            segunDistancia = 1
        }
        guard let anterior else { return segunDistancia }
        return min(segunDistancia, max(1, min(3, anterior)))
    }

    // MARK: Ruta por delante

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

    /// Cuántos pasos, desde el actual, hacen falta para recorrer `metros` desde
    /// la moto: del actual cuenta lo que queda (`restanteEnActual`), no su
    /// distancia entera, que haría parar en el giro sin la carretera de salida
    /// (lo vio la revisión de la 0.9.0); de los demás, su distancia, con 50 m de
    /// margen. Al menos uno, si hay pasos.
    public static func pasosNecesarios(distancias: [Double], restanteEnActual: Double, metros: Double) -> Int {
        guard !distancias.isEmpty else { return 0 }
        var suma = max(0, restanteEnActual)
        var cuantos = 1
        while suma < metros + 50 && cuantos < distancias.count {
            suma += max(0, distancias[cuantos])
            cuantos += 1
        }
        return cuantos
    }

    /// Rumbo de la marcha para el tramo: el de la ruta hasta `anticipacion`
    /// metros por delante, pero sin pasar del final del paso actual (si no, la
    /// cuerda cruzaría el giro y el dibujo rotaría hacia la salida, como vio la
    /// revisión de la 0.9.0). A menos de 3 m del final, el del último segmento
    /// del paso (por donde se llega al giro). Nil si no hay con qué calcularlo.
    static func sentido(paso: [PuntoRuta]?, indice: Int?, desde origen: PuntoRuta, anticipacion: Double) -> Double? {
        guard let paso else { return nil }
        let enPaso = recorrer(pasos: [paso], indice: indice, desde: origen, metros: anticipacion)
        if let fin = enPaso.last, distancia(origen, fin) >= 3 {
            return rumbo(de: origen, a: fin)
        }
        // El último segmento del paso de 1 m o más
        var i = paso.count - 1
        while i > 0 {
            if distancia(paso[i - 1], paso[i]) >= 1 {
                return rumbo(de: paso[i - 1], a: paso[i])
            }
            i -= 1
        }
        return nil
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
    /// que está `anticipacion` metros por delante dentro del paso actual (más
    /// estable que el del GPS y que el de un solo segmento; ver `sentido`). Se
    /// simplifica hasta que quepan
    /// `maximoPuntos`. `giro` es el punto del próximo giro (el final del paso
    /// actual): su índice en el tramo, si está (a menos de 10 m de un punto de
    /// la ruta). Ese punto se conserva al simplificar: si no, en un giro suave
    /// Douglas-Peucker lo quitaría (lo vio la revisión de la 0.9.1).
    /// Devuelve también la ruta sin simplificar y el sentido de la marcha,
    /// para poner los cruces en los mismos ejes (CRUCES, v0.6).
    /// Nil si no hay al menos dos puntos.
    public static func tramo(
        pasos: [[PuntoRuta]],
        indice: Int?,
        desde origen: PuntoRuta,
        metros total: Double,
        giro: PuntoRuta?,
        anticipacion: Double = 25,
        maximoPuntos: Int = MensajeTrazo.maximoPuntos
    ) -> TramoTrazo? {
        let ruta = recorrer(pasos: pasos, indice: indice, desde: origen, metros: total)
        guard ruta.count >= 2 else { return nil }
        let sentido = Self.sentido(paso: pasos.first, indice: indice, desde: origen, anticipacion: anticipacion)
            ?? rumbo(de: origen, a: ruta[1])

        // El giro en la ruta sin simplificar: el punto más cercano, a 10 m o menos
        var giroEnRuta: Int?
        if let giro {
            var mejor = 10.0
            for (numero, punto) in ruta.enumerated() where numero > 0 {
                let d = distancia(punto, giro)
                if d <= mejor {
                    mejor = d
                    giroEnRuta = numero
                }
            }
        }

        let limite = max(2, maximoPuntos)
        var tolerancia = 2.0
        var simple = simplificar(ruta, conservando: giroEnRuta, tolerancia: tolerancia)
        var intentos = 0
        while simple.puntos.count > limite && intentos < 40 {
            tolerancia *= 1.5
            simple = simplificar(ruta, conservando: giroEnRuta, tolerancia: tolerancia)
            intentos += 1
        }
        var puntos = simple.puntos
        var indiceGiro = simple.giro
        if puntos.count > limite {
            puntos = Array(puntos.prefix(limite))
            if let g = indiceGiro, g >= limite { indiceGiro = nil }
        }
        return TramoTrazo(puntos: aEjesMoto(puntos, origen: origen, rumbo: sentido), giro: indiceGiro,
                          ruta: ruta, sentido: sentido)
    }

    /// Douglas-Peucker sin perder el punto `conservando` (el giro): se
    /// simplifica por separado antes y después de él. Devuelve también dónde
    /// queda ese punto.
    static func simplificar(_ ruta: [PuntoRuta], conservando indice: Int?, tolerancia: Double) -> (puntos: [PuntoRuta], giro: Int?) {
        guard let indice, indice > 0, indice < ruta.count - 1 else {
            let simple = Simplificar.douglasPeucker(ruta, tolerancia: tolerancia)
            // El primero y el último siempre se conservan
            let giro = indice.map { $0 == 0 ? 0 : simple.count - 1 }
            return (simple, giro)
        }
        let antes = Simplificar.douglasPeucker(Array(ruta[0...indice]), tolerancia: tolerancia)
        let despues = Simplificar.douglasPeucker(Array(ruta[indice...]), tolerancia: tolerancia)
        return (antes + despues.dropFirst(), antes.count - 1)
    }
}
