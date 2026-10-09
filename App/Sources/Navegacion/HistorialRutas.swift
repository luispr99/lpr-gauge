import Foundation
import LPRCore
import SwiftUI

/// Las rutas hechas de la pestaña «Rutas» (LPRCore, RutasGuardadas.swift), de
/// la más reciente a la más antigua, y los tres accesos directos que salen en
/// el cuadro (desde la 0.18.0; solo los que fija el usuario: los huecos
/// libres se llenan en el cuadro con las más recientes, no aquí). Se guardan en el propio iPhone (UserDefaults):
/// no salen de él ni van a ningún servidor; al cuadro solo van las tres que
/// enseña (RUTAS, PROTOCOLO.md §7 quinquies).
@MainActor
final class HistorialRutas: ObservableObject {
    private static let clave = "rutas.historial"
    private static let claveAccesos = "rutas.accesos"

    @Published private(set) var rutas: [RutaGuardada]
    /// Un id por hueco (nil, libre); siempre `RutasGuardadas.huecos`.
    @Published private(set) var accesos: [UUID?]

    /// Lo llama con las que salen en el cuadro cada vez que cambian (el
    /// enlace se las manda).
    var alCambiar: (@MainActor ([RutaGuardada]) -> Void)?

    init() {
        let rutas = UserDefaults.standard.data(forKey: Self.clave).map(RutasGuardadas.decodificar) ?? []
        let guardados = UserDefaults.standard.stringArray(forKey: Self.claveAccesos) ?? []
        var accesos = guardados.prefix(RutasGuardadas.huecos).map { texto in
            UUID(uuidString: texto).flatMap { id in rutas.contains { $0.id == id } ? id : nil }
        }
        accesos += Array(repeating: nil, count: RutasGuardadas.huecos - accesos.count)
        self.rutas = rutas
        self.accesos = accesos
    }

    /// Las tres que salen en el cuadro: los accesos directos y, en los huecos
    /// libres, las más recientes.
    var paraElCuadro: [RutaGuardada] { RutasGuardadas.paraElCuadro(rutas, accesos: accesos) }

    func ruta(enHueco hueco: Int) -> RutaGuardada? {
        accesos[hueco].flatMap { id in rutas.first { $0.id == id } }
    }

    func esAcceso(_ ruta: RutaGuardada) -> Bool { accesos.contains(ruta.id) }

    var hayHuecoLibre: Bool { accesos.contains(nil) }

    /// La pone la primera; si ya estaba, la sustituye (RutasGuardadas.anadir).
    /// Los accesos directos no se quitan por viejos.
    func guardar(_ ruta: RutaGuardada) {
        rutas = RutasGuardadas.anadir(ruta, a: rutas, conservar: Set(accesos.compactMap { $0 }))
        persistir()
    }

    func borrar(_ posiciones: IndexSet) {
        let ids = Set(posiciones.map { rutas[$0].id })
        rutas.remove(atOffsets: posiciones)
        accesos = accesos.map { id in id.flatMap { ids.contains($0) ? nil : $0 } }
        persistir()
    }

    /// En el primer hueco libre (si no hay ninguno, nada).
    func fijar(_ ruta: RutaGuardada) {
        guard !esAcceso(ruta), let hueco = accesos.firstIndex(where: { $0 == nil }) else { return }
        accesos[hueco] = ruta.id
        persistir()
    }

    func quitar(hueco: Int) {
        accesos[hueco] = nil
        persistir()
    }

    private func persistir() {
        if let datos = try? RutasGuardadas.codificar(rutas) {
            UserDefaults.standard.set(datos, forKey: Self.clave)
        }
        UserDefaults.standard.set(accesos.map { $0?.uuidString ?? "" }, forKey: Self.claveAccesos)
        alCambiar?(paraElCuadro)
    }
}
