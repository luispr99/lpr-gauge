import MapKit
import SwiftUI
import LPRCore

/// Mapa con la posición y un buscador (Apple Maps). Con los botones de
/// preferencias (peajes, autopistas, asfalto) y la barra de tiempo extra; al
/// elegir un destino se previsualizan la ruta más rápida, la más divertida y,
/// sin «Solo asfalto», la de tierra; al iniciar, el guiado: cartel con la
/// flecha y los metros, mapa que sigue la posición y lo que falta.
struct NavegacionView: View {
    @ObservedObject var navegacion: Navegacion
    @State private var mostrarAjustes = false
    @State private var camara: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Simplificación de las rayas para el zoom actual (TrazoMapa).
    @State private var nivelTrazo: Int?
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
        GeometryReader { geometria in
            let anchura = geometria.size.width
            let altoPanel = geometria.size.height * 0.7
            mapaExploracion
                .onMapCameraChange(frequency: .onEnd) { contexto in
                    let nivel = TrazoMapa.nivel(
                        metrosPorPunto: TrazoMapa.metrosPorPunto(region: contexto.region, anchura: anchura)
                    )
                    if nivel != nivelTrazo {
                        nivelTrazo = nivel
                    }
                }
                .safeAreaInset(edge: .top) {
                    barraBusqueda
                }
                .safeAreaInset(edge: .bottom) {
                    // Mientras se escribe, sitio para las sugerencias
                    if !escribiendo {
                        panelInferior(altoMaximo: altoPanel)
                    }
                }
        }
        .onChange(of: navegacion.consulta) { _, _ in
            navegacion.consultaCambiada()
        }
        .onChange(of: navegacion.calculos) { _, _ in
            encuadrarVariantes()
        }
    }

    /// Mapa con la posición, las rutas propuestas y el destino. Las rayas se
    /// simplifican según el zoom (TrazoMapa) y van con uniones redondeadas, para
    /// que en las curvas cerradas no salgan picos fuera de la carretera.
    private var mapaExploracion: some View {
        Map(position: $camara) {
            UserAnnotation()
            // La elegida, encima de las demás
            ForEach(variantesOrdenadas) { variante in
                let elegida = variante.tipos.contains(navegacion.elegida)
                MapPolyline(coordinates: variante.trazo.coordenadas(nivel: nivelTrazo))
                    .stroke(
                        color(variante.tipo).opacity(elegida ? 1 : 0.55),
                        style: StrokeStyle(lineWidth: elegida ? 7 : 5, lineCap: .round, lineJoin: .round)
                    )
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
    }

    private var variantesOrdenadas: [VarianteRuta] {
        navegacion.variantes.filter { !$0.tipos.contains(navegacion.elegida) }
            + navegacion.variantes.filter { $0.tipos.contains(navegacion.elegida) }
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

    /// Panel de abajo, de como mucho `altoMaximo`. Arriba, fijas, las
    /// preferencias y la barra (fuera de la parte que se desplaza, para que
    /// mover la barra no la vuelva a crear y corte el gesto); en medio, lo que
    /// se desplaza si no cabe; abajo, fijo, el pie.
    private func panelInferior(altoMaximo: CGFloat) -> some View {
        let limite = AltoMaximo(alto: altoMaximo)
        return limite {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    preferenciasRuta
                    barraMargen
                        .disabled(navegacion.preparando)
                }
                .padding([.horizontal, .top])
                ViewThatFits(in: .vertical) {
                    contenidoPanel
                    ScrollView {
                        contenidoPanel
                    }
                }
                piePanel
            }
            .frame(maxWidth: .infinity)
        }
        .background(.regularMaterial)
    }

    private var contenidoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                // Mientras se prepara la navegación, la elegida no se cambia
                VStack(spacing: 10) {
                    ForEach(navegacion.variantes) { variante in
                        tarjetaVariante(variante)
                    }
                }
                .disabled(navegacion.preparando)
                if navegacion.sinRutaDeAsfalto {
                    avisoRutas("No hay ninguna ruta solo por asfalto: todas llevan algún tramo sin asfaltar.")
                }
                if navegacion.sinRutaPorTierra {
                    avisoRutas("Ninguna ruta por tierra cabe en el margen de tiempo. Prueba a subirlo.")
                }
                Text(verbatim: notaVariantes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !navegacion.variantes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Simular el recorrido", isOn: $navegacion.simular)
                    if navegacion.simular {
                        Picker("Velocidad", selection: $navegacion.factorSimulacion) {
                            Text(verbatim: "36 km/h").tag(UInt64(1))
                            Text(verbatim: "72 km/h").tag(UInt64(2))
                            Text(verbatim: "108 km/h").tag(UInt64(3))
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .disabled(navegacion.preparando)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Lo que tiene que verse siempre: el aviso, los botones y la atribución.
    private var piePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let aviso = navegacion.aviso {
                Text(verbatim: aviso)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !navegacion.variantes.isEmpty {
                HStack {
                    Button("Cancelar") {
                        navegacion.cancelarRuta()
                        camara = .userLocation(fallback: .automatic)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        navegacion.iniciar()
                    } label: {
                        HStack {
                            if navegacion.preparando {
                                ProgressView()
                            }
                            Text(navegacion.preparando ? "Preparando…" : "Iniciar")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(navegacion.preparando)
                }
                .controlSize(.large)
            }
            atribucion
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .bottom])
        .padding(.top, 8)
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
        HStack(spacing: 8) {
            botonPreferencia("Evitar peajes", icono: "eurosign.circle.fill", activa: $navegacion.evitarPeajes)
            botonPreferencia("Evitar autopistas", icono: "car.rear.road.lane", activa: $navegacion.evitarAutopistas)
            botonPreferencia("Solo asfalto", icono: "road.lanes", activa: $navegacion.soloAsfalto)
        }
    }

    private func botonPreferencia(_ titulo: LocalizedStringKey, icono: String, activa: Binding<Bool>) -> some View {
        let marcado = activa.wrappedValue
        return Button {
            activa.wrappedValue.toggle()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icono)
                    .font(.title2)
                Text(titulo)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .foregroundStyle(marcado ? Color.white : Color.primary)
            .background(
                marcado ? Color.accentColor : Color.secondary.opacity(0.15),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(alignment: .topTrailing) {
                if marcado {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcado ? .isSelected : [])
    }

    /// Barra del tiempo extra admitido para la más divertida y la de tierra.
    private var barraMargen: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Tiempo extra para divertida y tierra", systemImage: "timer")
                    .font(.footnote)
                Spacer()
                Text(verbatim: "+\(Int((navegacion.margenExtra * 100).rounded())) %")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            Slider(value: $navegacion.margenExtra, in: 0...2, step: 0.05)
        }
    }

    private func tarjetaVariante(_ variante: VarianteRuta) -> some View {
        let esElegida = variante.tipos.contains(navegacion.elegida)
        let tono = color(variante.tipo)
        return Button {
            navegacion.elegida = variante.tipo
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: variante.tipo.icono)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(tono, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: variante.nombre)
                        .font(.headline)
                    HStack(spacing: 10) {
                        Text(verbatim: Flechas.duracion(variante.segundos))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(verbatim: Flechas.distancia(variante.metros))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(verbatim: detalle(variante))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if variante.metrosPeaje > 0 || variante.metrosSinAsfaltar > 0 {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { etiquetas(variante) }
                            VStack(alignment: .leading, spacing: 4) { etiquetas(variante) }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: esElegida ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(esElegida ? tono : Color.secondary)
            }
            .padding(12)
            .background(
                esElegida ? tono.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(esElegida ? tono : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(esElegida ? .isSelected : [])
    }

    /// Avisos de peaje y tierra de una ruta. Los km son un máximo: Valhalla
    /// marca la maniobra entera.
    @ViewBuilder
    private func etiquetas(_ variante: VarianteRuta) -> some View {
        if variante.metrosPeaje > 0 {
            etiqueta("Peaje · hasta \(Flechas.distancia(variante.metrosPeaje))", icono: "eurosign.circle.fill", tono: .orange)
        }
        if variante.metrosSinAsfaltar > 0 {
            etiqueta("Sin asfaltar · hasta \(Flechas.distancia(variante.metrosSinAsfaltar))", icono: "mountain.2.fill", tono: .brown)
        }
    }

    private func etiqueta(_ texto: String, icono: String, tono: Color) -> some View {
        Label {
            Text(verbatim: texto)
        } icon: {
            Image(systemName: icono)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tono.opacity(0.18), in: Capsule())
        .foregroundStyle(tono)
    }

    private func avisoRutas(_ texto: LocalizedStringKey) -> some View {
        Label(texto, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }

    private var notaVariantes: String {
        let margen = Int((navegacion.margenExtra * 100).rounded())
        var nota = "La más divertida es la de más curvas sin tardar más de un \(margen) % que la más rápida."
        if !navegacion.soloAsfalto {
            nota += " «Por tierra», la de más tramos sin asfaltar con el mismo margen."
        }
        return nota + " Las curvas las cuenta la app; los km de peaje y sin asfaltar son un máximo."
    }

    /// «32 curvas», y si no es la más rápida, lo que tarda de más.
    private func detalle(_ variante: VarianteRuta) -> String {
        let curvas = variante.curvas == 1 ? "1 curva" : "\(variante.curvas) curvas"
        guard !variante.tipos.contains(.rapida),
              let rapida = navegacion.variantes.first(where: { $0.tipos.contains(.rapida) })
        else { return curvas }
        let demas = variante.segundos - rapida.segundos
        guard demas >= 60 else { return curvas }
        return curvas + " · +" + Flechas.duracion(demas)
    }

    private func color(_ tipo: TipoVariante) -> Color {
        switch tipo {
        case .rapida: return .blue
        case .divertida: return .orange
        case .tierra: return .brown
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

/// Propone a su contenido como mucho `alto` y ocupa solo lo que el contenido
/// necesite. Un `.frame(maxHeight:)` crecería hasta el máximo si le proponen
/// más altura.
private struct AltoMaximo: Layout {
    var alto: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let contenido = subviews.first else { return .zero }
        return contenido.sizeThatFits(
            ProposedViewSize(width: proposal.width, height: min(proposal.height ?? alto, alto))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
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
