import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

/// Proveedor de ubicación para Ferrostar.
///
/// Es propio, en vez del `CoreLocationProvider` de Ferrostar, por dos motivos
/// (docs/DECISIONES.md, «Altitud: lo comprobado»):
/// - aquel deja `pausesLocationUpdatesAutomatically` en `true`, y con permiso
///   «Cuando se use» una pausa (la moto parada en un semáforo) corta la ubicación
///   hasta volver a abrir la app;
/// - hace falta la altitud, que el `UserLocation` de Ferrostar no lleva.
///
/// Mientras se guía, sigue en segundo plano y con la pantalla bloqueada
/// (`guiadoEnFondo`, 2026-10-09; docs/DECISIONES.md).
final class ProveedorUbicacion: NSObject, LocationProviding, CLLocationManagerDelegate {
    weak var delegate: LocationManagingDelegate?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: UserLocation?
    private(set) var lastHeading: Heading?

    /// Cada ubicación completa de Core Location (con la altitud). Llega en el hilo
    /// principal, porque el gestor se crea en él.
    var alCambiar: ((CLLocation) -> Void)?

    private let gestor = CLLocationManager()

    override init() {
        authorizationStatus = gestor.authorizationStatus
        super.init()
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gestor.activityType = .automotiveNavigation
        gestor.pausesLocationUpdatesAutomatically = false
        if gestor.authorizationStatus == .notDetermined {
            gestor.requestWhenInUseAuthorization()
        }
    }

    func startUpdating() {
        gestor.startUpdatingLocation()
    }

    func stopUpdating() {
        gestor.stopUpdatingLocation()
    }

    /// Sesión que mantiene el permiso «Cuando se use» con la app en segundo
    /// plano (iOS 17; WWDC23 10180). Hay que guardarla: si se libera, se acaba.
    private var sesionFondo: CLBackgroundActivitySession?

    /// Guiado con la app en segundo plano y la pantalla bloqueada. Hay que
    /// llamarlo en primer plano (al pulsar «Iniciar»): Core Location no deja
    /// empezar en segundo plano. Activa las actualizaciones en segundo plano,
    /// crea la sesión y vuelve a arrancar el GPS con la propiedad ya puesta,
    /// como pide la documentación. Sin el modo `location` en el Info.plist,
    /// activar la propiedad cerraría la app, así que se comprueba antes
    func guiadoEnFondo(_ activo: Bool) {
        let modos = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard modos.contains("location") else { return }
        gestor.allowsBackgroundLocationUpdates = activo
        gestor.showsBackgroundLocationIndicator = activo
        if activo {
            if sesionFondo == nil {
                sesionFondo = CLBackgroundActivitySession()
            }
            gestor.stopUpdatingLocation()
            gestor.startUpdatingLocation()
        } else {
            sesionFondo?.invalidate()
            sesionFondo = nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let ultima = locations.last else { return }
        lastLocation = ultima.userLocation
        alCambiar?(ultima)
        delegate?.locationManager(self, didUpdateLocations: locations.map { $0.userLocation })
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

/// Añade a cada petición de rutas las cabeceras que piden las condiciones de uso
/// del servidor Valhalla de FOSSGIS (User-Agent y X-Client-Id). Ferrostar pide
/// por aquí las rutas de los recálculos: se guardan sus cruces para el cuadro
/// (RutasRecientes, desde la 0.10.0), porque Ferrostar no los conserva.
struct ClienteRutas: URLRequestLoading {
    /// Si guarda los cruces de las respuestas correctas. ClienteValhalla no:
    /// sus rutas propuestas no vienen en formato OSRM, y las de «Iniciar» las
    /// guarda él.
    var guardarCruces = true

    func loadData(with urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        var peticion = urlRequest
        peticion.setValue(Servidores.identificacion, forHTTPHeaderField: "User-Agent")
        peticion.setValue(Servidores.clienteId, forHTTPHeaderField: "X-Client-Id")
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        if guardarCruces, let http = respuesta as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            RutasRecientes.compartida.guardar(datos)
        }
        return (datos, respuesta)
    }
}
