import MapKit
import SwiftUI
import LPRCore

/// Mapa con la posición y un buscador (Apple Maps). Con los botones de
/// preferencias (peajes, autopistas, asfalto); al elegir un destino se
/// previsualizan la ruta más rápida y la más divertida; al iniciar, el guiado:
/// cartel con la flecha y los metros, mapa que sigue la posición y lo que falta.
struct NavegacionView: View {
    @ObservedObject var navegacion: Navegacion
    @State private var mostrarAjustes = false
    @State private var camara: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var escribiendo: Bool

    var body: some View {
        NavigationStack {
            Group {
                if navegacion.navegando {
                    guiado
                } else {
                    exploracion
                }
            }
            .navigationTitle("Navegar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrarAjustes = true
                    } label: {
                        Label("Servidor de rutas", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $mostrarAjustes) {
                AjustesServidoresView()
            }
        }
    }

    // MARK: - Exploración: mapa, búsqueda y variantes

    private var exploracion: some View {
        Map(position: $camara) {
            UserAnnotation()
            // La elegida, encima de las demás
            ForEach(variantesOrdenadas) { variante in
                let elegida = variante.tipo == navegacion.elegida
                MapPolyline(coordinates: variante.geometria)
                    .stroke(color(variante.tipo).opacity(elegida ? 1 : 0.5), lineWidth: elegida ? 8 : 5)
            }
            if let destino = navegacion.destino {
                Marker(destino.nombre, coordinate: destino.coordenada)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            barraBusqueda
        }
        .safeAreaInset(edge: .bottom) {
            panelInferior
        }
        .onChange(of: navegacion.consulta) { _, _ in
            navegacion.consultaCambiada()
        }
        .onChange(of: navegacion.variantes.count) { _, cuantas in
            if cuantas > 0 {
                encuadrarVariantes()
            }
        }
    }

    private var variantesOrdenadas: [VarianteRuta] {
        navegacion.variantes.filter { $0.tipo != navegacion.elegida }
            + navegacion.variantes.filter { $0.tipo == navegacion.elegida }
    }

    private var barraBusqueda: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar destino", text: $navegacion.consulta)
                    .focused($escribiendo)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !navegacion.consulta.isEmpty {
                    Button {
                        navegacion.cancelarRuta()
                        camara = .userLocation(fallback: .automatic)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            if escribiendo && !navegacion.sugerencias.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(navegacion.sugerencias, id: \.self) { sugerencia in
                            Button {
                                escribiendo = false
                                navegacion.elegir(sugerencia)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: sugerencia.title)
                                        .foregroundStyle(.primary)
                                    if !sugerencia.subtitle.isEmpty {
                                        Text(verbatim: sugerencia.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var panelInferior: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let aviso = navegacion.aviso {
                Text(verbatim: aviso)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            preferenciasRuta

            if navegacion.calculando {
                HStack {
                    ProgressView()
                    Text("Calculando las rutas…")
                }
            }

            if !navegacion.variantes.isEmpty {
                if let destino = navegacion.destino {
                    Text(verbatim: destino.nombre)
                        .font(.headline)
                        .lineLimit(1)
                }
                ForEach(navegacion.variantes) { variante in
                    filaVariante(variante)
                }
                Text(verbatim: notaVariantes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Simular el recorrido", isOn: $navegacion.simular)
                if navegacion.simular {
                    Picker("Velocidad", selection: $navegacion.factorSimulacion) {
                        Text(verbatim: "36 km/h").tag(UInt64(1))
                        Text(verbatim: "72 km/h").tag(UInt64(2))
                        Text(verbatim: "108 km/h").tag(UInt64(3))
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Cancelar") {
                        navegacion.cancelarRuta()
                        camara = .userLocation(fallback: .automatic)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        navegacion.iniciar()
                    } label: {
                        Text("Iniciar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if !navegacion.calculando {
                HStack {
                    Label(navegacion.posicionActual == nil
                              ? LocalizedStringKey("Esperando señal GPS…")
                              : LocalizedStringKey("GPS con señal"),
                          systemImage: "location")
                    Spacer()
                    Text(verbatim: "Altitud \(textoAltitud)")
                }
                .font(.footnote)
            }

            atribucion
        }
        .padding()
        .background(.regularMaterial)
    }

    private func encuadrarVariantes() {
        let puntos = navegacion.variantes.flatMap(\.geometria)
        guard puntos.count > 1 else { return }
        let rect = MKPolyline(coordinates: puntos, count: puntos.count).boundingMapRect
        let margen = max(rect.size.width, rect.size.height) * 0.2
        withAnimation {
            camara = .rect(rect.insetBy(dx: -margen, dy: -margen))
        }
    }

    /// Botones de preferencias de ruta. Al tocarlos con un destino elegido se
    /// vuelven a calcular las rutas.
    private var preferenciasRuta: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                botonPreferencia("Evitar peajes", activa: $navegacion.evitarPeajes)
                botonPreferencia("Evitar autopistas", activa: $navegacion.evitarAutopistas)
                botonPreferencia("Solo asfalto", activa: $navegacion.soloAsfalto)
            }
        }
    }

    private func botonPreferencia(_ titulo: LocalizedStringKey, activa: Binding<Bool>) -> some View {
        Button {
            activa.wrappedValue.toggle()
        } label: {
            Label(titulo, systemImage: activa.wrappedValue ? "checkmark.circle.fill" : "circle")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    activa.wrappedValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(activa.wrappedValue ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activa.wrappedValue ? .isSelected : [])
    }

    private func filaVariante(_ variante: VarianteRuta) -> some View {
        let esElegida = variante.tipo == navegacion.elegida
        return Button {
            navegacion.elegida = variante.tipo
        } label: {
            HStack {
                Circle()
                    .fill(color(variante.tipo))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(variante.tipo.nombre))
                    Text(verbatim: detalle(variante))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: Flechas.distancia(variante.metros))
                    .monospacedDigit()
                Text(verbatim: Flechas.duracion(variante.segundos))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: esElegida ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(esElegida ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notaVariantes: String {
        let margen = Int((Curvas.margenTiempo * 100).rounded())
        let regla = "La más divertida es la de más curvas sin tardar más de un \(margen) % que la más rápida."
        if navegacion.rapidaEsLaDivertida {
            return "La más rápida es también la de más curvas. " + regla
        }
        return regla + " Las curvas las cuenta la app sobre el trazado."
    }

    /// «32 curvas», y en la divertida lo que tarda de más sobre la rápida.
    private func detalle(_ variante: VarianteRuta) -> String {
        let curvas = variante.curvas == 1 ? "1 curva" : "\(variante.curvas) curvas"
        guard variante.tipo == .divertida,
              let rapida = navegacion.variantes.first(where: { $0.tipo == .rapida })
        else { return curvas }
        let demas = variante.segundos - rapida.segundos
        guard demas >= 60 else { return curvas }
        return curvas + " · +" + Flechas.duracion(demas)
    }

    private func color(_ tipo: TipoVariante) -> Color {
        switch tipo {
        case .rapida: return .blue
        case .divertida: return .orange
        }
    }

    // MARK: - Guiado

    private var guiado: some View {
        VStack(spacing: 0) {
            cartelManiobra

            ZStack(alignment: .top) {
                MapaGuiado(
                    ruta: navegacion.geometriaRuta,
                    posicion: navegacion.posicionEnRuta,
                    giro: navegacion.puntoGiro,
                    encuadre: EncuadreMapa(
                        posicion: navegacion.posicionEnRuta,
                        rumbo: navegacion.rumbo,
                        metrosAlGiro: navegacion.metrosAlGiro
                    )
                )
                avisosGuiado
                    .padding(8)
            }

            VStack(spacing: 10) {
                HStack(spacing: 24) {
                    if let metros = navegacion.metrosRestantes {
                        VStack {
                            Text("Quedan").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: Flechas.distancia(metros)).font(.headline)
                        }
                    }
                    if let segundos = navegacion.segundosRestantes {
                        VStack {
                            Text("Tiempo").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: Flechas.duracion(segundos)).font(.headline)
                        }
                    }
                    VStack {
                        Text("Altitud").font(.caption).foregroundStyle(.secondary)
                        Text(textoAltitud).font(.headline)
                    }
                }
                Button(role: .destructive) {
                    navegacion.terminar()
                    camara = .userLocation(fallback: .automatic)
                } label: {
                    Text("Terminar la navegación")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                atribucion
            }
            .padding()
        }
    }

    /// Cartel de la maniobra, como en los navegadores: flecha, metros e
    /// instrucción.
    private var cartelManiobra: some View {
        HStack(spacing: 16) {
            if navegacion.llegada {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 56, weight: .bold))
                Text("Has llegado")
                    .font(.title.bold())
            } else {
                Image(systemName: Flechas.simbolo(navegacion.maniobra))
                    .font(.system(size: 64, weight: .bold))
                    .frame(width: 80)
                VStack(alignment: .leading, spacing: 4) {
                    if let metros = navegacion.metrosAlGiro {
                        Text(verbatim: Flechas.distancia(metros))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    if let salida = navegacion.maniobra?.salidaRotonda {
                        Text("Salida \(Int(salida))")
                            .font(.headline)
                    }
                    if let texto = navegacion.maniobra?.texto {
                        Text(verbatim: texto)
                            .font(.headline)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.blue)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var avisosGuiado: some View {
        VStack(spacing: 6) {
            if navegacion.simulando {
                avisoMapa("Simulación: la posición no es la real", icono: "play.circle", color: .blue)
            }
            if navegacion.recalculando {
                avisoMapa("Recalculando la ruta…", icono: "arrow.triangle.2.circlepath", color: .orange)
            } else if navegacion.fueraDeRuta {
                avisoMapa("Fuera de ruta", icono: "exclamationmark.triangle", color: .orange)
            }
        }
    }

    private func avisoMapa(_ texto: LocalizedStringKey, icono: String, color: Color) -> some View {
        Label(texto, systemImage: icono)
            .font(.footnote.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Ayudas

    private var textoAltitud: String {
        guard let altitud = navegacion.altitud else { return "—" }
        let precision = navegacion.precisionVertical.map { " (±\(Int($0.rounded())) m)" } ?? ""
        return "\(Int(altitud.rounded())) m" + precision
    }

    /// Atribución de los datos de la ruta (OpenStreetMap, ODbL). La del mapa de
    /// Apple la pone MapKit.
    private var atribucion: some View {
        Text(verbatim: "Mapa y búsqueda: Apple · Rutas: Valhalla (FOSSGIS) · Datos de ruta © colaboradores de OpenStreetMap")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Dirección del servidor de rutas (Servidores.swift).
struct AjustesServidoresView: View {
    @Environment(\.dismiss) private var cerrar
    @AppStorage(Servidores.claveRutas) private var rutas = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Servidores.rutasPorDefecto, text: $rutas)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Rutas (Valhalla)")
                } footer: {
                    Text("Vacío: el servidor público de FOSSGIS. Uso razonable, como mucho una petición por segundo.")
                }
                Section {
                    Button("Volver al servidor público") {
                        rutas = ""
                    }
                }
            }
            .navigationTitle("Servidor de rutas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
        }
    }
}
