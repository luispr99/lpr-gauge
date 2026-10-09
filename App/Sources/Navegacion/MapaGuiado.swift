import MapKit
import SwiftUI

/// Encuadre de la cámara del mapa: centrado en la posición, orientado en el
/// sentido de la marcha y más cerca cuanto más cerca está el giro.
struct EncuadreMapa: Equatable {
    var latitud: Double
    var longitud: Double
    var rumbo: Double
    var distancia: Double

    init?(posicion: CLLocationCoordinate2D?, rumbo: Double?, metrosAlGiro: Double?) {
        guard let posicion else { return nil }
        latitud = posicion.latitude
        longitud = posicion.longitude
        self.rumbo = rumbo ?? 0
        // Altura de la cámara en metros: el giro cabe en pantalla sin alejarse
        // demasiado en las rectas largas
        distancia = min(1500, max(250, (metrosAlGiro ?? 400) * 2.2))
    }

    var camara: MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: latitud, longitude: longitud),
            distance: distancia,
            heading: rumbo,
            pitch: 45
        )
    }
}

/// Mapa de Apple (MapKit) con la ruta de Valhalla, la posición y el punto del
/// próximo giro. Sin gestos: la cámara sigue a la posición.
struct MapaGuiado: View {
    let ruta: [CLLocationCoordinate2D]
    let posicion: CLLocationCoordinate2D?
    let giro: CLLocationCoordinate2D?
    let encuadre: EncuadreMapa?

    @State private var camara: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camara, interactionModes: []) {
            if ruta.count > 1 {
                MapPolyline(coordinates: ruta)
                    .stroke(.blue, lineWidth: 8)
            }
            if let giro {
                Annotation("", coordinate: giro, anchor: .center) {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.blue, lineWidth: 4))
                        .frame(width: 16, height: 16)
                }
            }
            if let posicion {
                Annotation("", coordinate: posicion, anchor: .center) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, .blue)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onAppear {
            if let encuadre {
                camara = .camera(encuadre.camara)
            }
        }
        .onChange(of: encuadre) { _, nuevo in
            guard let nuevo else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                camara = .camera(nuevo.camara)
            }
        }
    }
}
