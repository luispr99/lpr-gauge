import LPRCore
import SwiftUI

/// Las rutas hechas (a petición del autor, 2026-10-10). Arriba, los tres
/// accesos directos, que son los que salen en el cuadro sin ruta (los huecos
/// libres, con las más recientes); debajo, todas, de la más reciente a la más
/// antigua. Al tocar una, `abrir` la carga en «Navegar» con el mismo destino,
/// tipo de ruta y preferencias (Navegacion.cargar): solo falta pulsar
/// «Iniciar». Deslizando: a la derecha, acceso directo; a la izquierda, borrar
/// (o quitar el acceso directo).
struct RutasView: View {
    @ObservedObject var historial: HistorialRutas
    @ObservedObject var navegacion: Navegacion
    let abrir: (RutaGuardada) -> Void

    /// Mientras se guía (o se prepara el guiado) no se puede cargar otra.
    private var ocupado: Bool { navegacion.navegando || navegacion.preparando }

    /// Lo que sale en cada hueco: el acceso directo o, si está libre, la
    /// reciente que lo llena (nil si no hay ninguna).
    private var enHuecos: [(ruta: RutaGuardada?, fijada: Bool)] {
        var recientes = historial.paraElCuadro.filter { !historial.esAcceso($0) }
        return (0..<RutasGuardadas.huecos).map { hueco in
            if let fijada = historial.ruta(enHueco: hueco) {
                return (fijada, true)
            }
            return (recientes.isEmpty ? nil : recientes.removeFirst(), false)
        }
    }

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
                        accesosDirectos
                        recientes
                    }
                }
            }
            .navigationTitle("Rutas")
        }
    }

    private var accesosDirectos: some View {
        Section {
            ForEach(Array(enHuecos.enumerated()), id: \.offset) { hueco, contenido in
                if let ruta = contenido.ruta {
                    Button {
                        abrir(ruta)
                    } label: {
                        FilaRuta(ruta: ruta, fijada: contenido.fijada, reciente: !contenido.fijada)
                    }
                    .disabled(ocupado)
                    .swipeActions(edge: .trailing) {
                        if contenido.fijada {
                            Button {
                                historial.quitar(hueco: hueco)
                            } label: {
                                Label("Quitar", systemImage: "pin.slash")
                            }
                            .tint(.orange)
                        }
                    }
                } else {
                    Label("Hueco libre", systemImage: "square.dashed")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Accesos directos")
        } footer: {
            Text("Son las tres que salen en la pantalla del cuadro cuando no hay ruta. Los huecos sin acceso directo se llenan con las rutas más recientes. Para añadir una, desliza a la derecha en la lista de abajo; para quitarla, a la izquierda aquí.")
        }
    }

    private var recientes: some View {
        Section {
            ForEach(historial.rutas) { ruta in
                Button {
                    abrir(ruta)
                } label: {
                    FilaRuta(ruta: ruta, fijada: historial.esAcceso(ruta), reciente: false)
                }
                .disabled(ocupado)
                .swipeActions(edge: .leading) {
                    if !historial.esAcceso(ruta) && historial.hayHuecoLibre {
                        Button {
                            historial.fijar(ruta)
                        } label: {
                            Label("Acceso directo", systemImage: "pin")
                        }
                        .tint(.blue)
                    }
                }
            }
            .onDelete { historial.borrar($0) }
        } header: {
            Text("Recientes")
        } footer: {
            Text(ocupado
                 ? "Termina la ruta en curso para cargar otra."
                 : "Toca una para cargarla en «Navegar» con el mismo tipo de ruta y las mismas preferencias: solo faltará pulsar «Iniciar». Las rutas se calculan desde donde estés. Desliza a la izquierda para borrar.")
        }
    }
}

/// Una ruta de la lista: el destino, el tipo de ruta y lo que medía la ruta
/// propuesta la última vez que se inició, con el peaje y la autopista como en
/// las tarjetas de «Navegar». `fijada`: acceso directo; `reciente`: llena un
/// hueco libre de los accesos directos.
struct FilaRuta: View {
    let ruta: RutaGuardada
    var fijada = false
    var reciente = false

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
        var texto = ruta.veces > 1 ? "\(fecha) · \(ruta.veces) veces" : fecha
        if reciente {
            texto += " · la más reciente"
        }
        return texto
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
