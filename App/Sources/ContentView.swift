import SwiftUI
import LPRCore

// Fase 0: solo comprueba la cadena completa (GitHub Actions → .ipa →
// Sideloadly → iPhone). Muestra la versión de la app y la del protocolo, que
// viene del paquete Core, para confirmar que el paquete queda enlazado.
struct ContentView: View {
    private let versionApp =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 56))
            Text(verbatim: "LPR Gauge")
                .font(.largeTitle.bold())
            Text("Fase 0: la app arranca en el iPhone.")
            Text("Versión \(versionApp) · protocolo v\(Int(Protocolo.version))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
