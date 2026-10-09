import Foundation

/// Un lugar encontrado al buscar el destino.
struct ResultadoBusqueda: Identifiable, Hashable {
    let id: String
    let nombre: String
    let descripcion: String
    let latitud: Double
    let longitud: Double
}

enum ErrorBusqueda: LocalizedError {
    case direccionNoValida
    case servidor(Int)

    var errorDescription: String? {
        switch self {
        case .direccionNoValida: return "La dirección del servidor de búsqueda no es válida"
        case let .servidor(codigo): return "El servidor de búsqueda ha respondido con el código \(codigo)"
        }
    }
}

/// Búsqueda de destinos con Nominatim. Cumple su política de uso
/// (https://operations.osmfoundation.org/policies/nominatim/):
/// - se busca solo al pulsar «Buscar», nunca mientras se escribe (está prohibido
///   autocompletar);
/// - como mucho una petición por segundo;
/// - cada petición identifica la app con el User-Agent;
/// - la vista muestra la atribución «© OpenStreetMap».
@MainActor
final class BuscadorNominatim {
    private var ultimaPeticion: Date?

    func buscar(_ texto: String) async throws -> [ResultadoBusqueda] {
        if let ultima = ultimaPeticion {
            let espera = 1 - Date().timeIntervalSince(ultima)
            if espera > 0 {
                try await Task.sleep(for: .seconds(espera))
            }
        }
        ultimaPeticion = Date()

        guard var componentes = URLComponents(string: Servidores.busqueda) else {
            throw ErrorBusqueda.direccionNoValida
        }
        componentes.queryItems = [
            URLQueryItem(name: "q", value: texto),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "accept-language", value: "es"),
        ]
        guard let url = componentes.url else { throw ErrorBusqueda.direccionNoValida }

        var peticion = URLRequest(url: url)
        peticion.setValue(Servidores.identificacion, forHTTPHeaderField: "User-Agent")
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        if let http = respuesta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ErrorBusqueda.servidor(http.statusCode)
        }

        let lugares = try JSONDecoder().decode([Lugar].self, from: datos)
        return lugares.compactMap { lugar -> ResultadoBusqueda? in
            guard let latitud = Double(lugar.lat), let longitud = Double(lugar.lon) else { return nil }
            let nombre = lugar.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? lugar.display_name.components(separatedBy: ",").first
                ?? lugar.display_name
            let identificador = (lugar.osm_type ?? "?") + (lugar.osm_id.map { String($0) } ?? lugar.display_name)
            return ResultadoBusqueda(
                id: identificador,
                nombre: nombre,
                descripcion: lugar.display_name,
                latitud: latitud,
                longitud: longitud
            )
        }
    }

    /// Lo que se usa de la respuesta jsonv2 de Nominatim.
    private struct Lugar: Decodable {
        let osm_type: String?
        let osm_id: Int?
        let lat: String
        let lon: String
        let name: String?
        let display_name: String
    }
}
