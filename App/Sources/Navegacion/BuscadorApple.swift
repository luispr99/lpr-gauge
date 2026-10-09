import Foundation
import MapKit

/// Un destino elegido.
struct ResultadoBusqueda: Identifiable, Hashable {
    let id: String
    let nombre: String
    let descripcion: String
    let latitud: Double
    let longitud: Double

    var coordenada: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitud, longitude: longitud)
    }
}

enum ErrorBusqueda: LocalizedError {
    case sinResultado

    var errorDescription: String? {
        "Apple Maps no ha devuelto la posición de ese lugar"
    }
}

/// Búsqueda de destinos con el buscador de Apple Maps (MapKit): sugerencias
/// mientras se escribe (MKLocalSearchCompleter) y, al elegir una, su posición
/// (MKLocalSearch). Gratuito y sin clave.
@MainActor
final class BuscadorApple: NSObject, MKLocalSearchCompleterDelegate {
    /// Sugerencias nuevas (llegan en el hilo principal).
    var alCambiar: (([MKLocalSearchCompletion]) -> Void)?
    var alFallar: ((Error) -> Void)?

    private let completador = MKLocalSearchCompleter()

    override init() {
        super.init()
        completador.delegate = self
        completador.resultTypes = [.address, .pointOfInterest]
    }

    /// Pide sugerencias para el texto, favoreciendo lo que esté cerca.
    func sugerir(_ texto: String, cercaDe posicion: CLLocationCoordinate2D?) {
        if let posicion {
            completador.region = MKCoordinateRegion(
                center: posicion,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }
        completador.queryFragment = texto
    }

    func resolver(_ sugerencia: MKLocalSearchCompletion) async throws -> ResultadoBusqueda {
        let respuesta = try await MKLocalSearch(request: MKLocalSearch.Request(completion: sugerencia)).start()
        guard let lugar = respuesta.mapItems.first else { throw ErrorBusqueda.sinResultado }
        let coordenada = lugar.placemark.coordinate
        return ResultadoBusqueda(
            id: "\(coordenada.latitude),\(coordenada.longitude)",
            nombre: lugar.name ?? sugerencia.title,
            descripcion: sugerencia.subtitle,
            latitud: coordenada.latitude,
            longitud: coordenada.longitude
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate (llega en el hilo principal)

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let resultados = completer.results
        MainActor.assumeIsolated {
            self.alCambiar?(resultados)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.alFallar?(error)
        }
    }
}
