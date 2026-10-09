import LPRCore
import SwiftUI

/// Las rutas hechas, de la más reciente a la más antigua (a petición del
/// autor, 2026-10-10). Al tocar una, `abrir` la carga en «Navegar» con el
/// mismo destino, tipo de ruta y preferencias (Navegacion.cargar): solo falta
/// pulsar «Iniciar». Se borran deslizando.
struct RutasView: View {
    @ObservedObject var historial: HistorialRutas
    @ObservedObject var navegacion: Navegacion
    let abrir: (RutaGuardada) -> Void

    /// Mientras se guía (o se prepara el guiado) no se puede cargar otra.
    private var ocupado: Bool { navegacion.navegando || navegacion.preparando }

    var body: some View {
        NavigationStack {
            Group {
                if historial.rutas.isEmpty {
                    ContentUnavailableView(
                        "Sin rutas todavía",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Cada ruta se guarda aquí al pulsar «Iniciar», para volver a cargarla con un toque.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(historial.rutas) { ruta in
                                Button {
                                    abrir(ruta)
                                } label: {
                                    FilaRuta(ruta: ruta)
                                }
                                .disabled(ocupado)
                            }
                            .onDelete { historial.borrar($0) }
                        } footer: {
                            Text(ocupado
                                 ? "Termina la ruta en curso para cargar otra."
                                 : "Toca una para cargarla en «Navegar» con el mismo tipo de ruta y las mismas preferencias: solo faltará pulsar «Iniciar». Las rutas se calculan desde donde estés. Desliza a la izquierda para borrar.")
                        }
                    }
                }
            }
            .navigationTitle("Rutas")
        }
    }
}

/// Una ruta de la lista: el destino, el tipo de ruta y lo que medía la ruta
/// propuesta la última vez que se inició.
private struct FilaRuta: View {
    let ruta: RutaGuardada

    private var tipo: TipoVariante { TipoVariante(rawValue: ruta.tipo) ?? .rapida }

    private var detalle: String {
        var partes = [Flechas.distancia(ruta.metros), Flechas.duracion(ruta.segundos)]
        if ruta.curvas > 0 {
            partes.append(ruta.curvas == 1 ? "1 curva" : "\(ruta.curvas) curvas")
        }
        return partes.joined(separator: " · ")
    }

    private var cuando: String {
        let fecha = ruta.fecha.formatted(.relative(presentation: .named))
        return ruta.veces > 1 ? "\(fecha) · \(ruta.veces) veces" : fecha
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tipo.icono)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(ruta.nombre)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !ruta.descripcion.isEmpty {
                    Text(ruta.descripcion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(tipo.nombre) · \(detalle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(cuando)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
