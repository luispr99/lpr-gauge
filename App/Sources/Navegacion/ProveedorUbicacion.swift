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
                alDiagnostico?("Sesión de actividad en segundo plano creada al iniciar")
            }
            gestor.stopUpdatingLocation()
            gestor.startUpdatingLocation()
        }
        // Desde la 0.20.3 la sesión no se suelta al dejar de guiar: soltarla
        // con la app en segundo plano le quita el «en uso» y el cuadro ya no
        // podía volver a arrancar el GPS hasta abrir la app (lo vio el autor:
        // la segunda ruta sin GPS, la tercera «abre la app"). Sin ruta no se
        // piden posiciones: el GPS sigue apagado (apagar)
    }

    /// Lo que pasa con el GPS, para el registro de «Placa» (0.20.3): por qué
    /// iOS no da posiciones (iOS 18) y cuándo se crean las sesiones.
    var alDiagnostico: ((String) -> Void)?
    private var ultimoDiagnostico = ""

    private func diagnosticar(_ actualizacion: CLLocationUpdate) {
        var partes: [String] = []
        if #available(iOS 18.0, *) {
            if actualizacion.insufficientlyInUse { partes.append("la app no está lo bastante «en uso»") }
            if actualizacion.serviceSessionRequired { partes.append("hace falta una sesión de servicio") }
            if actualizacion.locationUnavailable { partes.append("posición no disponible") }
            if actualizacion.stationary { partes.append("iPhone quieto: posiciones en pausa") }
        } else if actualizacion.isStationary {
            partes.append("iPhone quieto: posiciones en pausa")
        }
        let texto = partes.joined(separator: ", ")
        guard texto != ultimoDiagnostico else { return }
        ultimoDiagnostico = texto
        alDiagnostico?(texto.isEmpty ? "GPS: llegan posiciones" : "GPS: " + texto)
    }

    // MARK: - CLLocationManagerDelegate

    // MARK: - Desde el cuadro, con la app en segundo plano (prueba, 0.19.0)

    /// Sesión de servicio (iOS 18) y actualizaciones en vivo (iOS 17) para
    /// intentar arrancar el GPS con la app en segundo plano, cuando la despierta
    /// una orden del cuadro. Según un ingeniero de Apple en los foros (junio de
    /// 2025, no es documentación), es lo que lo permite si la app ha estado en
    /// primer plano al menos una vez; con startUpdatingLocation(), no. Sin
    /// probar: si no llegan posiciones, la orden contesta «abre la app».
    private var sesionServicio: AnyObject?
    private var tareaEnVivo: Task<Void, Never>?
    private(set) var enVivo = false
    /// Si la sesión de servicio se creó con la app abierta (para el registro).
    private(set) var sesionDePrimerPlano = false

    /// La sesión de servicio, creada con la app abierta y mantenida mientras
    /// vive (0.20.1): la 0.20.0 la soltaba al apagar el GPS y, desde el
    /// segundo plano, iOS no dejaba crear otra (al cancelar una ruta en el
    /// cuadro y tocar otra: sin posiciones; lo vio el autor). Mantenerla no
    /// enciende el GPS: solo deja empezar las posiciones desde el segundo
    /// plano (supuesto, a comprobar en el iPhone).
    func mantenerSesion(primerPlano: Bool) {
        if #available(iOS 18.0, *), sesionServicio == nil {
            sesionServicio = CLServiceSession(authorization: .whenInUse)
            sesionDePrimerPlano = primerPlano
        }
        // Y la sesión de actividad en segundo plano (0.20.3), con la app
        // abierta y para toda su vida: es la que la deja «en uso» con el
        // iPhone bloqueado para arrancar el GPS desde el cuadro. Puede hacer
        // que iOS enseñe el indicador de ubicación (aceptado por el autor)
        if primerPlano && sesionFondo == nil {
            sesionFondo = CLBackgroundActivitySession()
            alDiagnostico?("Sesión de actividad en segundo plano creada con la app abierta")
        }
    }

    func arrancarEnFondo() {
        let modos = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modos.contains("location") {
            gestor.allowsBackgroundLocationUpdates = true
            gestor.showsBackgroundLocationIndicator = true
        }
        mantenerSesion(primerPlano: false)
        gestor.startUpdatingLocation()
        guard tareaEnVivo == nil else { return }
        enVivo = true
        tareaEnVivo = Task { [weak self] in
            do {
                for try await actualizacion in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    if Task.isCancelled { break }
                    await MainActor.run { self?.diagnosticar(actualizacion) }
                    guard let posicion = actualizacion.location else { continue }
                    await MainActor.run { self?.recibir([posicion]) }
                }
            } catch {
                // Sin posiciones: la orden se contesta por el tiempo de espera
            }
        }
    }

    /// Vuelve a arrancar las posiciones en vivo desde cero, con la app en
    /// segundo plano (0.20.2): al pulsar «Iniciar» en el cuadro tras un rato
    /// con la propuesta en pantalla, iOS podía haber dejado de mandarlas (el
    /// GPS del cuadro en rojo y sin la flecha de ubicación en el iPhone; lo
    /// vio el autor). También la sesión de actividad en segundo plano (iOS 17).
    func reiniciarEnFondo() {
        tareaEnVivo?.cancel()
        tareaEnVivo = nil
        if sesionFondo == nil {
            sesionFondo = CLBackgroundActivitySession()
            alDiagnostico?("Sesión de actividad en segundo plano creada en segundo plano")
        }
        ultimoDiagnostico = ""
        arrancarEnFondo()
    }

    /// GPS apagado (a petición del autor: al terminar una ruta, hasta que se
    /// ponga otra): las actualizaciones y el segundo plano. La sesión de
    /// servicio se queda (mantenerSesion): sin ella no se podría volver a
    /// empezar desde el cuadro.
    func apagar() {
        tareaEnVivo?.cancel()
        tareaEnVivo = nil
        enVivo = false
        guiadoEnFondo(false)
        gestor.allowsBackgroundLocationUpdates = false
        gestor.stopUpdatingLocation()
    }

    private func recibir(_ locations: [CLLocation]) {
        guard let ultima = locations.last else { return }
        lastLocation = ultima.userLocation
        alCambiar?(ultima)
        delegate?.locationManager(self, didUpdateLocations: locations.map { $0.userLocation })
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        recibir(locations)
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
