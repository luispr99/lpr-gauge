import CoreLocation
import MapKit
import LPRCore

/// Trazado de una ruta precalculado con varias simplificaciones, para dibujarlo
/// según el zoom (LPRCore, Simplificar.swift): con poco zoom, más recto, como
/// las carreteras generalizadas del mapa base; con mucho, siguiendo la
/// carretera.
struct TrazoMapa {
    /// Tolerancias de cada nivel, en metros, de menor a mayor.
    static let tolerancias: [Double] = [2, 5, 12, 30, 75, 180, 450, 1100]
    /// Cuánto puede separarse el trazo simplificado del real, en puntos de
    /// pantalla. Supuesto: la raya mide 5–8 puntos de ancho.
    static let puntosDeTolerancia = 2.0

    let completo: [CLLocationCoordinate2D]
    private let niveles: [[CLLocationCoordinate2D]]

    init(_ coordenadas: [CLLocationCoordinate2D]) {
        completo = coordenadas
        let puntos = coordenadas.map { PuntoRuta(latitud: $0.latitude, longitud: $0.longitude) }
        niveles = Self.tolerancias.map { tolerancia in
            Simplificar.douglasPeucker(puntos, tolerancia: tolerancia)
                .map { CLLocationCoordinate2D(latitude: $0.latitud, longitude: $0.longitud) }
        }
    }

    /// El trazado para el nivel dado (nil: el completo).
    func coordenadas(nivel: Int?) -> [CLLocationCoordinate2D] {
        guard let nivel, niveles.indices.contains(nivel) else { return completo }
        return niveles[nivel]
    }

    /// Nivel para un mapa en el que un punto de pantalla son `metrosPorPunto`
    /// metros; nil si hay que dibujar el trazado completo.
    static func nivel(metrosPorPunto: Double?) -> Int? {
        guard let metrosPorPunto, metrosPorPunto > 0 else { return nil }
        let objetivo = metrosPorPunto * puntosDeTolerancia
        return tolerancias.lastIndex(where: { $0 <= objetivo })
    }

    /// Metros por punto de pantalla en el centro de una región del mapa que
    /// ocupa `anchura` puntos.
    static func metrosPorPunto(region: MKCoordinateRegion, anchura: CGFloat) -> Double? {
        guard anchura > 0, region.span.longitudeDelta > 0 else { return nil }
        let metros = region.span.longitudeDelta * 111_320 * cos(region.center.latitude * .pi / 180)
        return metros / Double(anchura)
    }
}
