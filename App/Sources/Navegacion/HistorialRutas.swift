import Foundation
import LPRCore
import SwiftUI

/// Las rutas hechas de la pestaña «Rutas» (LPRCore, RutasGuardadas.swift), de
/// la más reciente a la más antigua. Se guardan en el propio iPhone
/// (UserDefaults): no salen de él ni van a ningún servidor.
@MainActor
final class HistorialRutas: ObservableObject {
    private static let clave = "rutas.historial"

    @Published private(set) var rutas: [RutaGuardada]

    init() {
        rutas = UserDefaults.standard.data(forKey: Self.clave).map(RutasGuardadas.decodificar) ?? []
    }

    /// La pone la primera; si ya estaba, la sustituye (RutasGuardadas.anadir).
    func guardar(_ ruta: RutaGuardada) {
        rutas = RutasGuardadas.anadir(ruta, a: rutas)
        persistir()
    }

    func borrar(_ posiciones: IndexSet) {
        rutas.remove(atOffsets: posiciones)
        persistir()
    }

    private func persistir() {
        if let datos = try? RutasGuardadas.codificar(rutas) {
            UserDefaults.standard.set(datos, forKey: Self.clave)
        }
    }
}
