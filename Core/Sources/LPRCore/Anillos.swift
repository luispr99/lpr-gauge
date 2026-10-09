import Foundation

/// El anillo de una rotonda de la ruta (CRUCES, docs/PROTOCOLO.md §7 quater,
/// v0.8). En la respuesta de Valhalla solo viene el arco que se recorre: el
/// anillo es el círculo que mejor se ajusta a ese arco (`ajustar`). Comprobado
/// con rutas reales el 2026-10-09: en 11 de 12 rotondas el círculo del arco
/// coincide con el anillo de OpenStreetMap a menos de 1 m, y en 41 de 54
/// rotondas de 4 rutas pasa la regla de aceptación (docs/DECISIONES.md, 0.12.0).
public struct Anillo: Equatable {
    public var centro: PuntoRuta
    /// Metros.
    public var radio: Double
    /// Metros por la ruta, desde su principio, hasta la entrada en la rotonda
    /// (el primer cruce del paso de la rotonda) y hasta la salida (el primer
    /// cruce del paso siguiente).
    public var recorridoEntrada: Double
    public var recorridoSalida: Double

    public init(centro: PuntoRuta, radio: Double, recorridoEntrada: Double, recorridoSalida: Double) {
        self.centro = centro
        self.radio = radio
        self.recorridoEntrada = recorridoEntrada
        self.recorridoSalida = recorridoSalida
    }

    // Regla de aceptación del círculo. Supuestos a ajustar en la moto (salen
    // de las rutas reales del 2026-10-09)

    /// Puntos del arco como mínimo.
    static let minimoPuntos = 5
    /// Grados que gira el arco visto desde el centro, como mínimo: con menos,
    /// el círculo no queda bien determinado.
    static let minimoGiro = 40.0
    /// Error cuadrático medio, en metros, de la distancia de cada punto al
    /// círculo, como máximo: así se descartan los óvalos y las rotondas
    /// partidas.
    static let maximoError = 0.07
    /// Radio, en metros, entre estos dos.
    static let minimoRadio = 5.0
    static let maximoRadio = 80.0

    /// El anillo de una rotonda a partir del `arco` de la ruta que va por ella
    /// (de su entrada a su salida, en grados), o nil si el círculo no pasa la
    /// regla de aceptación. Los puntos se pasan a metros con una proyección
    /// local (como Cruces.calles); el círculo se ajusta con Kåsa y se afina
    /// con Gauss-Newton (AjusteCirculo).
    static func ajustar(arco: [PuntoRuta], recorridoEntrada: Double, recorridoSalida: Double) -> Anillo? {
        guard arco.count >= minimoPuntos, let origen = arco.first else { return nil }
        let coseno = cos(origen.latitud * .pi / 180)
        guard coseno.isFinite, coseno > 1e-6 else { return nil }
        let planos = arco.map { punto in
            PuntoPlano(x: (punto.longitud - origen.longitud) * Trazo.metrosPorGrado * coseno,
                       y: (punto.latitud - origen.latitud) * Trazo.metrosPorGrado)
        }
        guard let circulo = AjusteCirculo.ajustar(planos) else { return nil }
        let giro = abs(AjusteCirculo.giro(planos, centro: PuntoPlano(x: circulo.x, y: circulo.y)))
        guard giro >= minimoGiro,
              circulo.error <= maximoError,
              circulo.radio >= minimoRadio,
              circulo.radio <= maximoRadio
        else { return nil }
        return Anillo(
            centro: PuntoRuta(latitud: origen.latitud + circulo.y / Trazo.metrosPorGrado,
                              longitud: origen.longitud + circulo.x / (Trazo.metrosPorGrado * coseno)),
            radio: circulo.radio,
            recorridoEntrada: recorridoEntrada,
            recorridoSalida: recorridoSalida
        )
    }
}

/// Ajuste de un círculo a puntos en metros. Es el de anillo/lib.js del estudio
/// con las rutas reales (docs/DECISIONES.md, 0.12.0).
enum AjusteCirculo {
    struct Circulo: Equatable {
        var x: Double
        var y: Double
        var radio: Double
        /// Error cuadrático medio, en metros, de la distancia de cada punto al
        /// círculo.
        var error: Double
    }

    /// Iteraciones de Gauss-Newton como mucho.
    static let maximoIteraciones = 50

    /// Kåsa y, desde él, Gauss-Newton. Nil con menos de 3 puntos o si están
    /// en línea recta.
    static func ajustar(_ puntos: [PuntoPlano]) -> Circulo? {
        guard let inicio = kasa(puntos) else { return nil }
        let circulo = geometrico(puntos, desde: inicio)
        guard circulo.x.isFinite, circulo.y.isFinite, circulo.radio.isFinite, circulo.error.isFinite else { return nil }
        return circulo
    }

    /// Ajuste algebraico de Kåsa (mínimos cuadrados de x² + y² + Dx + Ey + F,
    /// con los puntos centrados en su media). Nil con menos de 3 puntos o si
    /// están en línea recta.
    static func kasa(_ puntos: [PuntoPlano]) -> Circulo? {
        guard puntos.count >= 3 else { return nil }
        let n = Double(puntos.count)
        let mediaX = puntos.reduce(0.0) { $0 + $1.x } / n
        let mediaY = puntos.reduce(0.0) { $0 + $1.y } / n
        var suu = 0.0, svv = 0.0, suv = 0.0
        var suuu = 0.0, svvv = 0.0, suvv = 0.0, svuu = 0.0
        for punto in puntos {
            let u = punto.x - mediaX
            let v = punto.y - mediaY
            suu += u * u
            svv += v * v
            suv += u * v
            suuu += u * u * u
            svvv += v * v * v
            suvv += u * v * v
            svuu += v * u * u
        }
        let determinante = suu * svv - suv * suv
        guard determinante.isFinite, abs(determinante) >= 1e-9 else { return nil }
        let b1 = 0.5 * (suuu + suvv)
        let b2 = 0.5 * (svvv + svuu)
        let uc = (b1 * svv - b2 * suv) / determinante
        let vc = (b2 * suu - b1 * suv) / determinante
        let radio = (uc * uc + vc * vc + (suu + svv) / n).squareRoot()
        let centro = PuntoPlano(x: uc + mediaX, y: vc + mediaY)
        return Circulo(x: centro.x, y: centro.y, radio: radio,
                       error: errorMedio(puntos, x: centro.x, y: centro.y, radio: radio))
    }

    /// Ajuste geométrico (minimiza la suma de los cuadrados de la distancia de
    /// cada punto al círculo) con Gauss-Newton amortiguado (Levenberg-
    /// Marquardt, sistema 3x3), desde `inicio`: si un paso no mejora, se
    /// amortigua más y se prueba otra vez; si mejora menos de 1e-10, o no se
    /// puede resolver el sistema, para. Como mucho `iteraciones`.
    static func geometrico(_ puntos: [PuntoPlano], desde inicio: Circulo,
                           iteraciones: Int = maximoIteraciones) -> Circulo {
        guard !puntos.isEmpty else { return inicio }
        var a = inicio.x
        var b = inicio.y
        var r = inicio.radio
        var amortiguamiento = 1e-3
        func coste(_ a: Double, _ b: Double, _ r: Double) -> Double {
            sumaDeCuadrados(puntos, x: a, y: b, radio: r)
        }
        var f = coste(a, b, r)
        for _ in 0..<max(0, iteraciones) {
            // JᵀJ y Jᵀe
            var m: [[Double]] = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
            var g: [Double] = [0, 0, 0]
            for punto in puntos {
                let dx = punto.x - a
                let dy = punto.y - b
                let calculada = hypot(dx, dy)
                let d = calculada > 0 ? calculada : 1e-9
                let e = d - r
                let jacobiano = [-dx / d, -dy / d, -1.0]
                for i in 0..<3 {
                    g[i] += jacobiano[i] * e
                    for k in 0..<3 {
                        m[i][k] += jacobiano[i] * jacobiano[k]
                    }
                }
            }
            for i in 0..<3 {
                m[i][i] *= 1 + amortiguamiento
            }
            guard let paso = resolver3(m, [-g[0], -g[1], -g[2]]) else { break }
            let nuevaA = a + paso[0]
            let nuevaB = b + paso[1]
            let nuevoR = r + paso[2]
            let nuevo = coste(nuevaA, nuevaB, nuevoR)
            if nuevo < f {
                let mejora = f - nuevo
                a = nuevaA
                b = nuevaB
                r = nuevoR
                f = nuevo
                amortiguamiento /= 3
                if mejora < 1e-10 { break }
            } else {
                amortiguamiento *= 5
            }
        }
        return Circulo(x: a, y: b, radio: abs(r), error: (f / Double(puntos.count)).squareRoot())
    }

    /// Error cuadrático medio de la distancia de los puntos al círculo.
    static func errorMedio(_ puntos: [PuntoPlano], x: Double, y: Double, radio: Double) -> Double {
        guard !puntos.isEmpty else { return 0 }
        return (sumaDeCuadrados(puntos, x: x, y: y, radio: radio) / Double(puntos.count)).squareRoot()
    }

    /// Suma de los cuadrados de la distancia de los puntos al círculo.
    static func sumaDeCuadrados(_ puntos: [PuntoPlano], x: Double, y: Double, radio: Double) -> Double {
        var suma = 0.0
        for punto in puntos {
            let e = hypot(punto.x - x, punto.y - y) - radio
            suma += e * e
        }
        return suma
    }

    /// Sistema 3x3 por Gauss-Jordan con pivote parcial; nil si es singular (o
    /// no tiene la forma).
    static func resolver3(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        guard a.count == 3, b.count == 3, a.allSatisfy({ $0.count == 3 }) else { return nil }
        var m = (0..<3).map { a[$0] + [b[$0]] }
        for i in 0..<3 {
            var pivote = i
            for j in (i + 1)..<3 where abs(m[j][i]) > abs(m[pivote][i]) {
                pivote = j
            }
            guard abs(m[pivote][i]) >= 1e-12 else { return nil }
            m.swapAt(i, pivote)
            for j in 0..<3 where j != i {
                let factor = m[j][i] / m[i][i]
                for k in i..<4 {
                    m[j][k] -= factor * m[i][k]
                }
            }
        }
        return [m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]]
    }

    /// Grados que gira la polilínea vista desde `centro`, con signo (positivo
    /// en sentido contrario a las agujas del reloj).
    static func giro(_ puntos: [PuntoPlano], centro: PuntoPlano) -> Double {
        guard puntos.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<puntos.count {
            let a = atan2(puntos[i - 1].y - centro.y, puntos[i - 1].x - centro.x)
            let b = atan2(puntos[i].y - centro.y, puntos[i].x - centro.x)
            var d = b - a
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            total += d
        }
        return total * 180 / .pi
    }
}

// MARK: - Rotondas en CRUCES (v0.8)

/// Una calle de un cruce de una rotonda con anillo, en metros desde el centro
/// del anillo (x al este, y al norte).
private struct CalleDeRotonda {
    /// Índice del cruce.
    var cruce: Int
    var punto: PuntoPlano
    var rumbo: Double
    var entrada: Bool?
    /// Rumbo del centro al cruce (la radial hacia fuera).
    var radial: Double
}

extension Cruces {
    // Supuestos a ajustar en la moto (salen de las rutas reales del 2026-10-09)

    /// Una calle de un cruce de la rotonda que forma más de estos grados con la
    /// radial hacia fuera es el propio anillo, que ya se dibuja entero (acertó
    /// en 91 de 92 calles).
    static let gradosAnillo = 90.0
    /// Dos calles de un mismo cruce de la rotonda a menos de estos grados son
    /// una (paso b de anillo/propuesta.js: en Cuatro Caminos, 229° y 251°).
    static let gradosMismoCruce = 30.0
    /// Brazos con isleta: dos calles seguidas, la primera de salida de la
    /// rotonda (`entry` true) y la segunda de entrada (`entry` false), de
    /// cruces distintos a estos grados o menos vistos desde el centro...
    static let gradosBrazo = 90.0
    /// ...cuyas semirrectas se cortan por fuera a menos de estos metros de los
    /// dos cruces...
    static let metrosCorteBrazo = 100.0
    /// ...o son casi paralelas (menos de estos grados) y sus cruces están a
    /// menos de estos metros.
    static let gradosParalelasBrazo = 15.0
    static let metrosParalelasBrazo = 30.0

    /// Los cruces para un cuadro que dibuja los anillos (v0.8). En los cruces
    /// de cada rotonda con anillo (Cruce.anillo, el índice en `anillos`), en el
    /// orden de la ruta:
    /// - a) fuera las calles que forman más de `gradosAnillo` con la radial
    ///   hacia fuera: son el anillo;
    /// - b) las calles de un mismo cruce a menos de `gradosMismoCruce` quedan
    ///   en una, la primera, con el rumbo medio y por la que se puede entrar si
    ///   se puede por alguna (0.12.1; faltaba en la 0.12.0);
    /// - c) los brazos con isleta (`esBrazoConIsleta`) quedan en una calle, en
    ///   el anillo a medio camino entre sus dos cruces y con el rumbo medio. Va
    ///   en un cruce nuevo, justo detrás del primero, con el recorrido de ese
    ///   primero y por el que se puede entrar.
    /// Con `soloEn`, solo en las rotondas de esos índices; en las demás, los
    /// cruces se quedan como están. Los cruces que se quedan sin calles se
    /// quitan; los demás no cambian. Es el algoritmo de anillo/propuesta.js del
    /// estudio con las rutas reales (docs/DECISIONES.md, 0.12.0).
    public static func conAnillos(_ cruces: [Cruce], anillos: [Anillo], soloEn elegidos: Set<Int>? = nil) -> [Cruce] {
        guard !anillos.isEmpty else { return cruces }
        // Los cruces de cada rotonda, de una pasada
        var suyosDe: [Int: [Int]] = [:]
        for (c, cruce) in cruces.enumerated() {
            if let indice = cruce.anillo, elegidos?.contains(indice) ?? true {
                suyosDe[indice, default: []].append(c)
            }
        }
        // Las calles que se quedan en cada cruce de una rotonda (con su rumbo,
        // que el paso b puede cambiar) y los cruces nuevos de los brazos, que
        // van detrás del suyo
        var quedan: [Int: [(rumbo: Double, entrada: Bool?)]] = [:]
        var nuevos: [Int: [Cruce]] = [:]
        for (indice, anillo) in anillos.enumerated() {
            guard let suyos = suyosDe[indice], !suyos.isEmpty else { continue }
            let origen = anillo.centro
            let coseno = cos(origen.latitud * .pi / 180)
            guard coseno.isFinite, coseno > 1e-6 else { continue }
            func plano(_ punto: PuntoRuta) -> PuntoPlano {
                PuntoPlano(x: (punto.longitud - origen.longitud) * Trazo.metrosPorGrado * coseno,
                           y: (punto.latitud - origen.latitud) * Trazo.metrosPorGrado)
            }
            func enGrados(_ punto: PuntoPlano) -> PuntoRuta {
                PuntoRuta(latitud: origen.latitud + punto.y / Trazo.metrosPorGrado,
                          longitud: origen.longitud + punto.x / (Trazo.metrosPorGrado * coseno))
            }

            // a) Las calles de la rotonda, sin las del anillo
            var todas: [CalleDeRotonda] = []
            for c in suyos {
                quedan[c] = []
                let punto = plano(cruces[c].punto)
                // En el centro no hay radial (no pasa con radios de 5 m o más)
                let conRadial = hypot(punto.x, punto.y) >= 0.5
                let radial = rumbo(de: punto)
                for (k, rumboCalle) in cruces[c].rumbos.enumerated() {
                    if conRadial && abs(diferenciaAngular(rumboCalle, radial)) > gradosAnillo { continue }
                    todas.append(CalleDeRotonda(cruce: c, punto: punto, rumbo: rumboCalle,
                                                entrada: cruces[c].entrada(k), radial: radial))
                }
            }

            // b) Las de un mismo cruce casi iguales, en una, antes de buscar
            // los brazos: cada una se compara con las que ya quedan de su
            // cruce, con el rumbo ya juntado
            var calles: [CalleDeRotonda] = []
            for calle in todas {
                if let k = calles.firstIndex(where: {
                    $0.cruce == calle.cruce && abs(diferenciaAngular($0.rumbo, calle.rumbo)) < gradosMismoCruce
                }) {
                    calles[k].rumbo = rumboMedio(calles[k].rumbo, calle.rumbo)
                    if calle.entrada == true {
                        calles[k].entrada = true
                    }
                } else {
                    calles.append(calle)
                }
            }

            // c) Los brazos con isleta, en una
            var i = 0
            while i < calles.count {
                let a = calles[i]
                if i + 1 < calles.count && esBrazoConIsleta(a, calles[i + 1]) {
                    let b = calles[i + 1]
                    let medio = PuntoPlano(x: (a.punto.x + b.punto.x) / 2, y: (a.punto.y + b.punto.y) / 2)
                    let distancia = hypot(medio.x, medio.y)
                    let enAnillo = distancia > 0
                        ? PuntoPlano(x: medio.x / distancia * anillo.radio, y: medio.y / distancia * anillo.radio)
                        : medio
                    nuevos[a.cruce, default: []].append(Cruce(
                        punto: enGrados(enAnillo),
                        rumbos: [rumboMedio(a.rumbo, b.rumbo)],
                        recorrido: cruces[a.cruce].recorrido,
                        entradas: [true],
                        anillo: indice
                    ))
                    i += 2
                } else {
                    quedan[a.cruce, default: []].append((rumbo: a.rumbo, entrada: a.entrada))
                    i += 1
                }
            }
        }

        var resultado: [Cruce] = []
        for (c, cruce) in cruces.enumerated() {
            guard let calles = quedan[c] else {
                resultado.append(cruce)
                continue
            }
            if !calles.isEmpty {
                var copia = cruce
                copia.rumbos = calles.map { $0.rumbo }
                copia.entradas = calles.map { $0.entrada }
                resultado.append(copia)
            }
            resultado += nuevos[c] ?? []
        }
        return resultado
    }

    /// Si dos calles seguidas de una rotonda son las dos calzadas de un brazo
    /// con isleta (ver las constantes).
    private static func esBrazoConIsleta(_ a: CalleDeRotonda, _ b: CalleDeRotonda) -> Bool {
        guard a.entrada == true, b.entrada == false, a.cruce != b.cruce,
              abs(diferenciaAngular(b.radial, a.radial)) <= gradosBrazo
        else { return false }
        if abs(diferenciaAngular(a.rumbo, b.rumbo)) < gradosParalelasBrazo
            && hypot(a.punto.x - b.punto.x, a.punto.y - b.punto.y) < metrosParalelasBrazo {
            return true
        }
        // a.punto + t·u = b.punto + s·v, con u y v los vectores de los rumbos
        let u = vector(a.rumbo)
        let v = vector(b.rumbo)
        let determinante = u.x * -v.y - u.y * -v.x
        guard abs(determinante) >= 1e-9 else { return false }
        let dx = b.punto.x - a.punto.x
        let dy = b.punto.y - a.punto.y
        let t = (dx * -v.y - dy * -v.x) / determinante
        let s = (u.x * dy - u.y * dx) / determinante
        return t > 0 && s > 0 && t < metrosCorteBrazo && s < metrosCorteBrazo
    }

    /// El vector unitario de un rumbo (x al este, y al norte).
    static func vector(_ rumbo: Double) -> PuntoPlano {
        PuntoPlano(x: sin(rumbo * .pi / 180), y: cos(rumbo * .pi / 180))
    }

    /// El rumbo de un vector (x al este, y al norte), de 0 a 360.
    static func rumbo(de vector: PuntoPlano) -> Double {
        let grados = atan2(vector.x, vector.y) * 180 / .pi
        return grados < 0 ? grados + 360 : grados
    }

    /// El rumbo medio de dos: el de la suma de sus vectores.
    static func rumboMedio(_ a: Double, _ b: Double) -> Double {
        let u = vector(a)
        let v = vector(b)
        return rumbo(de: PuntoPlano(x: u.x + v.x, y: u.y + v.y))
    }

    /// Los anillos de las rotondas del tramo de TRAZO (CRUCES, v0.8), en los
    /// ejes de la moto (el origen en el primer punto de `ruta`, la del tramo
    /// sin simplificar, y `sentido` hacia arriba, como Cruces.calles). Cuentan
    /// los que se empiezan a recorrer dentro de la `ventana` (los metros de la
    /// ruta entera que cubre el tramo, como en Cruces.calles) y los que se
    /// acaban de recorrer como mucho `metrosAnilloDetras` antes de ella, para
    /// que no desaparezcan dentro de la rotonda. En el orden de la ruta (los
    /// más cercanos primero), como mucho `maximo`.
    public static func anillos(
        de anillos: [Anillo],
        ruta: [PuntoRuta],
        sentido: Double,
        ventana: ClosedRange<Double>,
        maximo: Int = MensajeCruces.maximoAnillos
    ) -> [AnilloCruce] {
        anillosConIndices(de: anillos, ruta: ruta, sentido: sentido, ventana: ventana, maximo: maximo).anillos
    }

    /// Los mismos anillos que `anillos(de:ruta:sentido:ventana:maximo:)` y, en
    /// el mismo orden, sus índices en `anillos`: las rotondas que van en el
    /// mensaje, que son las que llevan las calles sin las del anillo
    /// (RutaConCruces.crucesConAnillosSoloEn(_:)). Si hay más de `maximo` en la
    /// ventana, las que no caben se dibujan con sus calles, sin anillo
    /// (revisión de la 0.12.0).
    public static func anillosConIndices(
        de anillos: [Anillo],
        ruta: [PuntoRuta],
        sentido: Double,
        ventana: ClosedRange<Double>,
        maximo: Int = MensajeCruces.maximoAnillos
    ) -> (anillos: [AnilloCruce], indices: [Int]) {
        guard let origen = ruta.first, maximo > 0, !anillos.isEmpty else { return (anillos: [], indices: []) }
        let enVentana: [Int] = anillos.indices.filter {
            anillos[$0].recorridoEntrada <= ventana.upperBound
                && anillos[$0].recorridoSalida >= ventana.lowerBound - metrosAnilloDetras
        }
        let ordenados: [Int] = enVentana.sorted {
            anillos[$0].recorridoEntrada != anillos[$1].recorridoEntrada
                ? anillos[$0].recorridoEntrada < anillos[$1].recorridoEntrada
                : $0 < $1
        }
        let indices = Array(ordenados.prefix(maximo))
        let centros = Trazo.aEjesMoto(indices.map { anillos[$0].centro }, origen: origen, rumbo: sentido)
        let elegidos = zip(indices, centros).map { AnilloCruce(x: $0.1.x, y: $0.1.y, radio: anillos[$0.0].radio) }
        return (anillos: elegidos, indices: indices)
    }

    /// Metros que sigue contando un anillo después de su salida, por detrás de
    /// la ventana (supuesto a ajustar en la moto).
    static let metrosAnilloDetras = 20.0
}
