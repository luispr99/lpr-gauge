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
/// De momento solo en primer plano: el modo de fondo llega en el paso siguiente.
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
/// del servidor Valhalla de FOSSGIS (User-Agent y X-Client-Id).
struct ClienteRutas: URLRequestLoading {
    func loadData(with urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        var peticion = urlRequest
        peticion.setValue(Servidores.identificacion, forHTTPHeaderField: "User-Agent")
        peticion.setValue(Servidores.clienteId, forHTTPHeaderField: "X-Client-Id")
        return try await URLSession.shared.data(for: peticion)
    }
}
