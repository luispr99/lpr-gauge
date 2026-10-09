import SwiftUI

/// Dos pestañas: la navegación y la prueba del enlace con la placa. El enlace
/// vive aquí para que no se corte al cambiar de pestaña. La navegación se lo
/// queda para pasarle el texto y el tramo de ruta del cuadro directamente, sin
/// pasar por las vistas, que con la app en segundo plano pueden no actualizarse.
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
        .onAppear {
            navegacion.enlace = enlace
        }
    }
}
