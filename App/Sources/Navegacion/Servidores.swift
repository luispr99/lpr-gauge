import Foundation

/// Servidor de rutas (Valhalla de FOSSGIS por defecto). Ver docs/DECISIONES.md,
/// «Navegación: servidores». La dirección se puede cambiar en Ajustes sin
/// actualizar la app.
enum Servidores {
    static let claveRutas = "servidores.rutas"
    static let rutasPorDefecto = "https://valhalla1.openstreetmap.de/route"

    static var rutas: String {
        let texto = UserDefaults.standard.string(forKey: claveRutas)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (texto?.isEmpty ?? true) ? rutasPorDefecto : texto!
    }

    /// Identifica la app ante el servidor, como piden sus condiciones de uso
    /// (cabecera User-Agent).
    static var identificacion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "LPRGauge/\(version) (+https://github.com/luispr99/lpr-gauge)"
    }

    /// Cabecera X-Client-Id que pide el servidor Valhalla de FOSSGIS.
    static let clienteId = "lpr-gauge-ios"
}
