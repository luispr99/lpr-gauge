import Foundation
import FerrostarCoreFFI

/// La maniobra que se está mostrando, tal como la da Ferrostar (tipo y
/// modificador al estilo OSRM; docs/DECISIONES.md, «Maniobras: lo comprobado»).
struct Maniobra: Equatable {
    var tipo: ManeuverType?
    var modificador: ManeuverModifier?
    /// Grados que se recorren dentro de la rotonda.
    var gradosRotonda: UInt16?
    /// Número de salida de la rotonda (1 = primera), si se conoce.
    var salidaRotonda: UInt8?
    var texto: String
}

/// Flecha que se dibuja en la pantalla del iPhone. Es provisional: la tabla de
/// flechas del cuadro (PROTOCOLO.md §8) se definirá aparte.
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
