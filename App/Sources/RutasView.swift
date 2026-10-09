import LPRCore
import SwiftUI

/// Las rutas hechas (a petición del autor, 2026-10-10). Arriba, los tres
/// accesos directos, que solo se configuran a mano con el botón de cada
/// ruta; son los que salen en el cuadro sin ruta y, sin ninguno, el cuadro
/// enseña las más recientes (sin añadirlas aquí). Debajo, todas, de la más
/// reciente a la más antigua. Al tocar una, `abrir` la carga en «Navegar» con
/// el mismo destino, tipo de ruta y preferencias (Navegacion.cargar): solo
/// falta pulsar «Iniciar». Deslizando a la izquierda en «Recientes», se borra.
struct RutasView: View {
    @ObservedObject var historial: HistorialRutas
    @ObservedObject var navegacion: Navegacion
    let abrir: (RutaGuardada) -> Void

    /// Mientras se guía (o se prepara el guiado) no se puede cargar otra.
    private var ocupado: Bool { navegacion.navegando || navegacion.preparando }

    private var ningunAcceso: Bool { historial.accesos.allSatisfy { $0 == nil } }

    var body: some View {
        NavigationStack {
            List {
                accesosDirectos
                recientes
            }
            .navigationTitle("Rutas")
        }
    }

    private var accesosDirectos: some View {
        Section {
            ForEach(0..<RutasGuardadas.huecos, id: \.self) { hueco in
                if let ruta = historial.ruta(enHueco: hueco) {
                    fila(ruta) {
                        BotonAcceso(estilo: .quitar) { historial.quitar(hueco: hueco) }
                    }
                } else {
                    Label("Hueco libre", systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Accesos directos")
        } footer: {
            // Dos Text con literal: así son LocalizedStringKey (negrita e icono)
            if ningunAcceso {
                Text("**Sin accesos directos: el cuadro enseña las tres rutas más recientes.** Son las rutas que salen en la pantalla del cuadro cuando no hay ruta; los huecos libres se llenan allí con las más recientes, pero no se añaden aquí. Pulsa \(Image(systemName: "pin.fill")) en una ruta para fijarla.")
            } else {
                Text("Son las rutas que salen en la pantalla del cuadro cuando no hay ruta. Los huecos libres se llenan allí con las más recientes, pero no se añaden aquí. Pulsa \(Image(systemName: "pin.fill")) en una ruta para fijarla.")
            }
        }
    }

    private var recientes: some View {
        Section {
            if historial.rutas.isEmpty {
                Text("Sin rutas todavía: cada ruta se guarda aquí al pulsar «Iniciar».")
                    .foregroundStyle(.secondary)
            }
            ForEach(historial.rutas) { ruta in
                fila(ruta, fijada: historial.esAcceso(ruta)) {
                    if let hueco = historial.accesos.firstIndex(of: ruta.id) {
                        BotonAcceso(estilo: .quitar) { historial.quitar(hueco: hueco) }
                    } else {
                        BotonAcceso(estilo: historial.hayHuecoLibre ? .fijar : .lleno) { historial.fijar(ruta) }
                    }
                }
            }
            .onDelete { historial.borrar($0) }
        } header: {
            Text("Recientes")
        } footer: {
            Text(ocupado
                 ? "Termina la ruta en curso para cargar otra."
                 : "Toca una para cargarla en «Navegar» con el mismo tipo de ruta y las mismas preferencias: solo faltará pulsar «Iniciar». Si cambias algo antes de iniciarla, se guarda como ruta nueva. Las rutas se calculan desde donde estés. Desliza a la izquierda para borrar.")
        }
    }

    /// La tarjeta (al tocarla, se carga) y su botón a la derecha. Los dos con
    /// estilo sin borde: si no, en una lista el toque en el botón cargaría
    /// también la ruta
    private func fila<Boton: View>(_ ruta: RutaGuardada, fijada: Bool = false,
                                   @ViewBuilder boton: () -> Boton) -> some View {
        HStack(spacing: 8) {
            Button {
                abrir(ruta)
            } label: {
                FilaRuta(ruta: ruta, fijada: fijada)
            }
            .buttonStyle(.borderless)
            .disabled(ocupado)
            boton()
        }
    }
}

/// El botón al lado de cada ruta: fijarla como acceso directo, quitarla, o
/// gris si los tres huecos están ocupados.
private struct BotonAcceso: View {
    enum Estilo { case fijar, quitar, lleno }
    let estilo: Estilo
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: estilo == .quitar ? "minus" : "pin.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(estilo == .quitar ? Color.red : estilo == .fijar ? Color.blue : Color.gray)
                .frame(width: 34, height: 34)
                .background((estilo == .quitar ? Color.red : estilo == .fijar ? Color.blue : Color.gray).opacity(0.12),
                            in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(estilo == .lleno)
        .accessibilityLabel(estilo == .quitar ? "Quitar de accesos directos" : "Fijar como acceso directo")
    }
}

/// Una ruta de la lista: el destino, el tipo de ruta y lo que medía la ruta
/// propuesta la última vez que se inició, con el peaje y la autopista como en
/// las tarjetas de «Navegar». `fijada`: acceso directo.
struct FilaRuta: View {
    let ruta: RutaGuardada
    var fijada = false

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
                HStack(spacing: 4) {
                    if fijada {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Text(ruta.nombre)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if !ruta.descripcion.isEmpty {
                    Text(ruta.descripcion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(tipo.nombre) · \(detalle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Como en las tarjetas de «Navegar»: el peaje advierte y la
                // autopista solo informa; por debajo de 100 m, nada
                if ruta.metrosPeaje >= 100 {
                    Label("Peaje \(Flechas.distancia(ruta.metrosPeaje))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if ruta.metrosAutopista >= 100 {
                    Label("Autopista \(Flechas.distancia(ruta.metrosAutopista))", systemImage: "info.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                Text(cuando)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
