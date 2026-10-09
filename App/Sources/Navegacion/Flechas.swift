import Foundation
import FerrostarCoreFFI
import LPRCore

/// La maniobra que se está mostrando, tal como la da Ferrostar (tipo y
/// modificador al estilo OSRM; docs/DECISIONES.md, «Maniobras: lo comprobado»).
struct Maniobra: Equatable {
    var tipo: ManeuverType?
    var modificador: ManeuverModifier?
    /// Grados que se recorren dentro de la rotonda (180: seguir recto).
    var gradosRotonda: UInt16?
    /// Número de salida de la rotonda (1 = primera), si se conoce.
    var salidaRotonda: UInt8?
    /// Lado por el que se circula en el paso de la maniobra; nil: por la
    /// derecha.
    var ladoCirculacion: DrivingSide?
    /// Lo que va junto a la flecha: la calle, la salida o «Destino»
    /// (Flechas.nombre); vacío si la vía no tiene nombre.
    var texto: String
}

/// Flecha que se dibuja en la pantalla del iPhone y, para el cuadro, el código
/// de maniobra y el ángulo de NAV (PROTOCOLO.md §5 y §8, v0.6).
enum Flechas {
    static func simbolo(_ maniobra: Maniobra?) -> String {
        guard let maniobra else { return "arrow.up" }
        switch maniobra.tipo {
        case .arrive?:
            return "flag.checkered"
        case .roundabout?, .rotary?, .roundaboutTurn?, .exitRoundabout?, .exitRotary?:
            return "arrow.triangle.turn.up.right.circle"
        case .merge?:
            return "arrow.triangle.merge"
        case .fork?:
            return "arrow.triangle.branch"
        default:
            break
        }
        switch maniobra.modificador {
        case .uTurn?: return "arrow.uturn.down"
        case .sharpRight?: return "arrow.turn.right.down"
        case .right?: return "arrow.turn.up.right"
        case .slightRight?: return "arrow.up.right"
        case .slightLeft?: return "arrow.up.left"
        case .left?: return "arrow.turn.up.left"
        case .sharpLeft?: return "arrow.turn.left.down"
        case .straight?, nil: return "arrow.up"
        }
    }

    // MARK: - Cuadro (NAV)

    /// Código de maniobra del cuadro (§8): la llegada, la salida y las
    /// rotondas, por el tipo; el cambio de sentido, por el modificador; las
    /// bifurcaciones, incorporaciones, rampas y finales de vía, giro; lo demás,
    /// giro o recto según el modificador (recto también sin modificador). Sin
    /// maniobra, o sin tipo ni modificador, desconocida.
    static func codigo(_ maniobra: Maniobra?) -> CodigoManiobra {
        guard let maniobra else { return .desconocida }
        switch maniobra.tipo {
        case .arrive?:
            return .llegada
        case .depart?:
            return .salida
        case .roundabout?, .rotary?, .roundaboutTurn?, .exitRoundabout?, .exitRotary?:
            return .rotonda
        default:
            break
        }
        if case .uTurn? = maniobra.modificador {
            return .cambioDeSentido
        }
        switch maniobra.tipo {
        case .fork?, .merge?, .onRamp?, .offRamp?, .endOfRoad?:
            return .giro
        default:
            break
        }
        switch maniobra.modificador {
        case .sharpRight?, .right?, .slightRight?, .slightLeft?, .left?, .sharpLeft?:
            return .giro
        case .uTurn?:
            return .cambioDeSentido
        case .straight?:
            return .recto
        case nil:
            return maniobra.tipo == nil ? .desconocida : .recto
        }
    }

    /// Ángulo nominal de la flecha del cuadro (§5), en grados y positivo a la
    /// derecha: del modificador, recto 0, ligero ±45, normal ±90 y cerrado
    /// ±135. El cambio de sentido, ±180 hacia el lado contrario al de la
    /// circulación (circulando por la derecha, -180). En rotondas, la dirección
    /// de la salida a partir de los grados que se recorren dentro, si se
    /// conocen; si no, del modificador. Nil si no se sabe.
    static func angulo(_ maniobra: Maniobra?) -> Int? {
        guard let maniobra else { return nil }
        let porLaDerecha = maniobra.ladoCirculacion != .left
        let codigoManiobra = codigo(maniobra)
        if codigoManiobra == .rotonda, let grados = maniobra.gradosRotonda {
            return CodigoManiobra.anguloRotonda(grados: Int(grados), porLaDerecha: porLaDerecha)
        }
        switch maniobra.modificador {
        case .uTurn?: return porLaDerecha ? -180 : 180
        case .sharpRight?: return 135
        case .right?: return 90
        case .slightRight?: return 45
        case .straight?: return 0
        case .slightLeft?: return -45
        case .left?: return -90
        case .sharpLeft?: return -135
        case nil: return codigoManiobra == .recto ? 0 : nil
        }
    }

    /// Número de salida de la rotonda de la maniobra que hay al final de
    /// `paso`: va en el paso que empieza en ella (`despues`); ya dentro de la
    /// rotonda (instrucción «salga de la rotonda»), en `paso`, que es el de la
    /// rotonda (comprobado con respuestas de Valhalla; lo vio la revisión de
    /// la 0.10.0).
    static func salidaRotonda(tipo: ManeuverType?, paso: RouteStep?, despues: RouteStep?) -> UInt8? {
        switch tipo {
        case .exitRoundabout?, .exitRotary?:
            return despues?.roundaboutExitNumber ?? paso?.roundaboutExitNumber
        default:
            return despues?.roundaboutExitNumber
        }
    }

    /// La maniobra que va después de la siguiente («y luego», NAV v0.11, §5)
    /// y los metros entre las dos. La siguiente maniobra es la del final del
    /// paso actual (`pasos[0]`); la de luego, la del final del paso siguiente
    /// (`pasos[1]`), con las mismas reglas que la siguiente (código, ángulo y
    /// salida de rotonda; llegada si ese paso acaba en el destino). La
    /// distancia es la longitud de ese paso. La instrucción, la primera del
    /// paso: la que se enseñaría al empezarlo (supuesto: las de un mismo paso
    /// describen la misma maniobra). Nil si no hay paso siguiente, si no tiene
    /// instrucción (el último paso, el de la llegada, de longitud 0, no la
    /// tiene en las respuestas de Valhalla) o si su código es desconocido.
    static func luego(_ pasos: [RouteStep]) -> (maniobra: Maniobra, metros: Double)? {
        guard pasos.count >= 2, let visual = pasos[1].visualInstructions.first else { return nil }
        let paso = pasos[1]
        let despues: RouteStep? = pasos.count >= 3 ? pasos[2] : nil
        let contenido = visual.primaryContent
        let maniobra = Maniobra(
            tipo: contenido.maneuverType,
            modificador: contenido.maneuverModifier,
            gradosRotonda: contenido.roundaboutExitDegrees,
            salidaRotonda: salidaRotonda(tipo: contenido.maneuverType, paso: paso, despues: despues),
            ladoCirculacion: despues?.drivingSide ?? paso.drivingSide,
            // El cuadro no recibe texto para la de luego
            texto: ""
        )
        guard codigo(maniobra) != .desconocida else { return nil }
        return (maniobra: maniobra, metros: paso.distance)
    }

    // MARK: - Texto de la maniobra

    /// Lo que se escribe junto a la flecha, en el iPhone y en el cuadro: solo
    /// la vía, sin frases como «Gire a la derecha hacia…» (a petición del
    /// autor, 2026-10-09: «solo icono y calle / avenida / salida»).
    /// - Al llegar, «Destino».
    /// - En rotondas, «Salida 2» y la vía.
    /// - En salidas numeradas (autovías), «Salida 23» y la vía.
    /// - Si no, la calle o carretera a la que se entra (`via`: el nombre del
    ///   paso siguiente, el que empieza en la maniobra).
    /// Vacío si no hay nada de eso (una vía sin nombre): solo la flecha y la
    /// distancia. Valhalla, con formato OSRM, sí da frases en el texto de las
    /// instrucciones cuando la vía no tiene nombre (comprobado el 2026-10-09),
    /// por eso no se usa.
    static func nombre(tipo: ManeuverType?, salidaRotonda: UInt8?, salidas: [String], via: String?) -> String {
        if case .arrive? = tipo { return "Destino" }
        var partes: [String] = []
        switch tipo {
        case .roundabout?, .rotary?, .roundaboutTurn?, .exitRoundabout?, .exitRotary?:
            if let salidaRotonda, salidaRotonda > 0 {
                partes.append("Salida \(salidaRotonda)")
            }
        default:
            if let numero = salidas.first(where: { !$0.isEmpty }) {
                partes.append("Salida \(numero)")
            }
        }
        let calle = via?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !calle.isEmpty {
            partes.append(calle)
        }
        return partes.joined(separator: ", ")
    }

    /// Distancia como la leería un motorista: «350 m», «1,2 km».
    static func distancia(_ metros: Double) -> String {
        let espanol = Locale(identifier: "es_ES")
        if metros < 1000 {
            let redondeo = metros < 100 ? 10.0 : 50.0
            let valor = Int((metros / redondeo).rounded() * redondeo)
            return "\(valor) m"
        }
        let km = metros / 1000
        let decimales = km < 10 ? 1 : 0
        return km.formatted(.number.precision(.fractionLength(decimales)).locale(espanol)) + " km"
    }

    /// Duración como «1 h 05 min» o «12 min».
    static func duracion(_ segundos: Double) -> String {
        let minutos = Int((segundos / 60).rounded())
        if minutos < 60 { return "\(minutos) min" }
        return String(format: "%d h %02d min", minutos / 60, minutos % 60)
    }
}
