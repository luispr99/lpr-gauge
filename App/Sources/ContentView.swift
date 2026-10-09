import SwiftUI

/// Dos pestañas: la navegación y la prueba del enlace con la placa. El enlace
/// vive aquí para que no se corte al cambiar de pestaña, y aquí se le pasa el
/// texto de la navegación para la cara del cuadro (NAV_TEXT).
struct ContentView: View {
    @StateObject private var enlace = EnlaceBLE()
    @StateObject private var navegacion = Navegacion()

    var body: some View {
        TabView {
            NavegacionView(navegacion: navegacion)
                .tabItem { Label("Navegar", systemImage: "arrow.triangle.turn.up.right.diamond") }
            PlacaView(enlace: enlace)
                .tabItem { Label("Placa", systemImage: "dot.radiowaves.left.and.right") }
        }
        .onChange(of: navegacion.textoCuadro) { _, texto in
            enlace.ponerTexto(texto)
        }
    }
}
