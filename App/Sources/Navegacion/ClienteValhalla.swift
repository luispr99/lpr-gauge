import Foundation
import FerrostarCore
import FerrostarCoreFFI
import LPRCore

/// Una petición de rutas a Valhalla, guardada para poder repetirla igual.
struct PeticionRutas {
    /// Opciones de la moto (`costing_options.motorcycle`).
    let opcionesMoto: [String: Any]
    let alternativas: Int
    let origen: UserLocation
    let destino: Waypoint

    /// Proveedor de Ferrostar con estas opciones, en español y en km. Con
    /// `alternativas` se cambia cuántas pedir: el de guiado va sin ellas,
    /// porque al recalcular Ferrostar solo usa la primera ruta.
    func proveedor(alternativas: Int? = nil) throws -> WellKnownRouteProvider {
        var opciones: [String: Any] = [
            "language": "es-ES",
            "units": "kilometers",
            "costing_options": ["motorcycle": opcionesMoto],
        ]
        let cuantas = alternativas ?? self.alternativas
        if cuantas > 0 {
            opciones["alternates"] = cuantas
        }
        return try WellKnownRouteProvider
            .valhalla(endpointUrl: Servidores.rutas, profile: "motorcycle")
            .withJsonOptions(options: opciones)
    }
}

/// Peticiones a Valhalla fuera del núcleo de Ferrostar (docs/DECISIONES.md):
/// - las rutas propuestas se piden en el formato propio de Valhalla, que marca
///   la tierra y los peajes de cada maniobra (el formato OSRM no trae la tierra);
/// - al empezar, se repite la misma petición en formato OSRM, que es el que
///   entiende Ferrostar. Valhalla devuelve las mismas rutas en el mismo orden.
///
/// El cuerpo lo genera siempre Ferrostar, para que las dos peticiones solo
/// difieran en el formato de salida.
enum ClienteValhalla {
    enum Fallo: LocalizedError {
        case peticionNoValida
        case servidor(estado: Int, mensaje: String?)

        var errorDescription: String? {
            switch self {
            case .peticionNoValida:
                return "No se pudo preparar la petición de rutas."
            case let .servidor(estado, mensaje):
                return "El servidor de rutas respondió \(estado)" + (mensaje.map { ": \($0)" } ?? ".")
            }
        }
    }

    /// Las rutas en el formato propio de Valhalla: la principal y las
    /// alternativas, en ese orden.
    static func rutasPropuestas(_ peticion: PeticionRutas) async throws -> [RutaValhalla] {
        let adaptador = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: peticion.proveedor())
        let (direccion, cabeceras, cuerpo) = try partes(
            adaptador.generateRequest(userLocation: peticion.origen, waypoints: [peticion.destino])
        )
        // Lo que se quita solo afecta a la salida en formato OSRM, no al cálculo
        guard var json = try JSONSerialization.jsonObject(with: cuerpo) as? [String: Any] else {
            throw Fallo.peticionNoValida
        }
        json["format"] = "json"
        json["filters"] = nil
        json["banner_instructions"] = nil
        json["voice_instructions"] = nil
        let datos = try await enviar(direccion, cabeceras, JSONSerialization.data(withJSONObject: json))
        return try RespuestaValhalla.rutas(de: datos)
    }

    /// Las mismas rutas en formato OSRM, como las pide Ferrostar, para guiar.
    /// Sus cruces quedan guardados para el cuadro (RutasRecientes): Ferrostar
    /// no los conserva en sus rutas.
    static func rutasFerrostar(_ peticion: PeticionRutas) async throws -> [Route] {
        let adaptador = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: peticion.proveedor())
        let (direccion, cabeceras, cuerpo) = try partes(
            adaptador.generateRequest(userLocation: peticion.origen, waypoints: [peticion.destino])
        )
        let datos = try await enviar(direccion, cabeceras, cuerpo)
        let rutas = try adaptador.parseResponse(response: datos)
        RutasRecientes.compartida.guardar(datos)
        return rutas
    }

    /// Km de autopista, peaje y sin asfaltar de una ruta, tramo a tramo
    /// (/trace_attributes, en el mismo servidor que /route; LPRCore,
    /// Atributos.swift). Los de las maniobras se pasaban (0.10.0).
    static func detalleVias(_ puntos: [PuntoRuta]) async throws -> DetalleVias {
        guard let base = URL(string: Servidores.rutas) else { throw Fallo.peticionNoValida }
        let direccion = base.deletingLastPathComponent().appendingPathComponent("trace_attributes")
        let cuerpo = try JSONSerialization.data(withJSONObject: RespuestaAtributos.cuerpo(forma: puntos))
        let datos = try await enviar(direccion, ["Content-Type": "application/json"], cuerpo)
        return try RespuestaAtributos.detalle(de: datos)
    }

    private static func partes(_ peticion: RouteRequest) throws -> (URL, [String: String], Data) {
        guard case let .httpPost(url, headers, body) = peticion, let direccion = URL(string: url) else {
            throw Fallo.peticionNoValida
        }
        return (direccion, headers, body)
    }

    /// POST como lo hace Ferrostar (cabeceras del generador y 15 s de espera),
    /// con la identificación de la app (ClienteRutas). Los cruces los guarda,
    /// si hacen falta, quien llama: las rutas propuestas no vienen en formato
    /// OSRM.
    private static func enviar(_ direccion: URL, _ cabeceras: [String: String], _ cuerpo: Data) async throws -> Data {
        var peticion = URLRequest(url: direccion)
        peticion.httpMethod = "POST"
        peticion.httpBody = cuerpo
        for (nombre, valor) in cabeceras {
            peticion.setValue(valor, forHTTPHeaderField: nombre)
        }
        peticion.timeoutInterval = 15
        let (datos, respuesta) = try await ClienteRutas(guardarCruces: false).loadData(with: peticion)
        if let http = respuesta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Fallo.servidor(estado: http.statusCode, mensaje: RespuestaValhalla.mensajeDeError(datos))
        }
        return datos
    }
}

/// Las rutas en formato OSRM de las últimas respuestas (la de «Iniciar» y las
/// de los recálculos de Ferrostar), con sus cruces, para mandar al cuadro las
/// calles del tramo (CRUCES, PROTOCOLO.md §7 quater). Navegacion se queda con
/// los de la ruta cuyo trazado coincide con el del guiado (Cruces.buscar).
/// Ferrostar pide los recálculos fuera del hilo principal (ClienteRutas), así
/// que el acceso va con un cerrojo.
final class RutasRecientes: @unchecked Sendable {
    static let compartida = RutasRecientes()

    /// Bastan las de las dos últimas respuestas (hasta tres rutas cada una,
    /// con las alternativas).
    private static let maximo = 6
    private let cerrojo = NSLock()
    private var rutas: [RutaConCruces] = []

    /// Decodifica una respuesta y guarda sus rutas, delante de las anteriores.
    /// Lo que no sea una respuesta OSRM se ignora.
    func guardar(_ datos: Data) {
        guard let nuevas = try? RespuestaOSRM.rutas(de: datos), !nuevas.isEmpty else { return }
        cerrojo.lock()
        defer { cerrojo.unlock() }
        rutas = Array((nuevas + rutas).prefix(Self.maximo))
    }

    func todas() -> [RutaConCruces] {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        return rutas
    }

    /// Al terminar la ruta.
    func olvidar() {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        rutas = []
    }
}
