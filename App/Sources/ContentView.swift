import SwiftUI

/// Tres pestañas: la navegación, las rutas hechas (desde la 0.17.0) y la
/// prueba del enlace con la placa. El enlace vive aquí para que no se corte al
/// cambiar de pestaña. La navegación se lo queda para pasarle el texto y el
/// tramo de ruta del cuadro directamente, sin pasar por las vistas, que con la
/// app en segundo plano pueden no actualizarse. Al tocar una ruta hecha, se
/// carga y se vuelve a «Navegar».
struct ContentView: View {
    private enum Pestana: Hashable {
        case navegar, rutas, placa
    }

    @StateObject private var enlace = EnlaceBLE()
    @StateObject private var navegacion = Navegacion()
    @StateObject private var historial = HistorialRutas()
    @State private var pestana = Pestana.navegar

    var body: some View {
        TabView(selection: $pestana) {
            NavegacionView(navegacion: navegacion)
                .tabItem { Label("Navegar", systemImage: "arrow.triangle.turn.up.right.diamond") }
                .tag(Pestana.navegar)
            RutasView(historial: historial, navegacion: navegacion) { ruta in
                navegacion.cargar(ruta)
                pestana = .navegar
            }
            .tabItem { Label("Rutas", systemImage: "clock.arrow.circlepath") }
            .tag(Pestana.rutas)
            PlacaView(enlace: enlace)
                .tabItem { Label("Placa", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Pestana.placa)
        }
        .onAppear {
            navegacion.enlace = enlace
            navegacion.historial = historial
            // Las tres del cuadro (v0.13): al empezar y cada vez que cambian;
            // y sus órdenes, a la navegación
            historial.alCambiar = { rutas in enlace.ponerRutas(rutas) }
            enlace.ponerRutas(historial.paraElCuadro)
            enlace.alRecibirOrden = { orden, ruta in navegacion.ordenDelCuadro(orden, ruta: ruta) }
        }
    }
}
