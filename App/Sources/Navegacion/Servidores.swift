import Foundation

/// Servidores públicos de rutas (Valhalla de FOSSGIS) y de búsqueda (Nominatim de
/// OpenStreetMap). Ver docs/DECISIONES.md, «Navegación: servidores».
///
/// Las direcciones se pueden cambiar en Ajustes sin actualizar la app, como pide
/// la política de uso de Nominatim: https://operations.osmfoundation.org/policies/nominatim/
enum Servidores {
    static let claveRutas = "servidores.rutas"
    static let claveBusqueda = "servidores.busqueda"

    static let rutasPorDefecto = "https://valhalla1.openstreetmap.de/route"
    static let busquedaPorDefecto = "https://nominatim.openstreetmap.org/search"

    static var rutas: String {
        valor(claveRutas) ?? rutasPorDefecto
    }

    static var busqueda: String {
        valor(claveBusqueda) ?? busquedaPorDefecto
    }

    /// Identifica la app ante los servidores, como piden sus condiciones de uso
    /// (cabecera User-Agent).
    static var identificacion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "LPRGauge/\(version) (+https://github.com/luispr99/lpr-gauge)"
    }

    /// Cabecera X-Client-Id que pide el servidor Valhalla de FOSSGIS.
    static let clienteId = "lpr-gauge-ios"

    private static func valor(_ clave: String) -> String? {
        let texto = UserDefaults.standard.string(forKey: clave)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (texto?.isEmpty ?? true) ? nil : texto
    }
}
