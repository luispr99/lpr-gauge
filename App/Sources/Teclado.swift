import SwiftUI
import UIKit

/// Botón «Ocultar teclado» en la barra de encima del teclado, para todos los
/// campos de texto (a petición del autor, 2026-10-09). Se pone una vez por
/// pantalla, dentro de su NavigationStack: la barra del teclado es de la
/// pantalla, no de cada campo, y con uno por campo el botón saldría repetido.
/// Quita el foco al que lo tenga, sea cual sea el campo.
private struct BotonOcultarTeclado: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                } label: {
                    Label("Ocultar teclado", systemImage: "keyboard.chevron.compact.down")
                        .labelStyle(.titleAndIcon)
                }
                // Un poco más arriba: pegado al teclado quedaba muy justo
                // (lo pidió el autor el 2026-10-09). Sin probar en el iPhone
                .padding(.bottom, 8)
            }
        }
    }
}

extension View {
    /// Añade el botón «Ocultar teclado» encima del teclado (ver BotonOcultarTeclado).
    func botonOcultarTeclado() -> some View {
        modifier(BotonOcultarTeclado())
    }
}
