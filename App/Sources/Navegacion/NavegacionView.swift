import MapKit
import SwiftUI
import LPRCore

/// Mapa con la posición y un buscador (Apple Maps), en el 60 % de arriba; en
/// el resto, las opciones de ruta (peajes, autovías y tiempo extra) y, con un
/// destino, la ruta más rápida y la de más curvas con los botones de cancelar e
/// iniciar (maqueta aprobada por el autor el 2026-10-09). Al iniciar, el
/// guiado: cartel con la flecha y los metros, mapa que sigue la posición y lo
/// que falta.
struct NavegacionView: View {
    @ObservedObject var navegacion: Navegacion
    @State private var mostrarAjustes = false
    @State private var camara: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Simplificación de las rayas para el zoom actual (TrazoMapa).
    @State private var nivelTrazo: Int?
    /// Con un destino, las opciones ocupan el sitio de las rutas.
    @State private var mostrarOpciones = false
    @FocusState private var escribiendo: Bool

    /// Parte de la pantalla para el mapa; el resto, para el panel.
    private let partePantallaMapa: CGFloat = 0.6

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
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $mostrarAjustes) {
                AjustesView(navegacion: navegacion)
            }
        }
    }

    // MARK: - Exploración: mapa, búsqueda y rutas

    private var exploracion: some View {
        GeometryReader { geometria in
            let anchura = geometria.size.width
            let alto = geometria.size.height
            VStack(spacing: 0) {
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
                    .overlay(alignment: .bottom) {
                        avisosExploracion
                            .padding(8)
                    }
                    // Mientras se escribe, todo para el mapa y las sugerencias
                    .frame(height: escribiendo ? alto : alto * partePantallaMapa)
                if !escribiendo {
                    panelInferior
                        .frame(height: alto * (1 - partePantallaMapa))
                }
            }
        }
        .onChange(of: navegacion.consulta) { _, _ in
            navegacion.consultaCambiada()
        }
        // Al terminar un cálculo, la ruta elegida entera. Las opciones siguen
        // abiertas si lo estaban, por si se cambia algo más
        .onChange(of: navegacion.calculos) { _, _ in
            encuadrarElegida()
        }
        .onChange(of: navegacion.destino == nil) { _, sinDestino in
            if sinDestino {
                mostrarOpciones = false
            }
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

    // MARK: - Panel de abajo

    /// Sin destino, solo las opciones de ruta, ocupando todo el panel. Con
    /// destino, la fila «Opciones de ruta», las rutas (o las opciones, si se
    /// abren, en el mismo sitio) y los botones de cancelar e iniciar.
    private var panelInferior: some View {
        VStack(spacing: 8) {
            if navegacion.destino == nil {
                opcionesRuta
            } else {
                filaOpciones
                if mostrarOpciones {
                    opcionesRuta
                } else {
                    rutasPropuestas
                }
                botonesRuta
            }
            atribucion
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    /// Abre y cierra las opciones; cerrada, resume las activas y el margen.
    private var filaOpciones: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mostrarOpciones.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text("Opciones de ruta")
                if !mostrarOpciones {
                    if navegacion.evitarPeajes {
                        IconoTachable(nombre: "eurosign.circle", tachado: true)
                            .foregroundStyle(Color.accentColor)
                    }
                    if navegacion.evitarAutopistas {
                        IconoTachable(nombre: "road.lanes", tachado: true)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if mostrarOpciones {
                    Text("Listo")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(verbatim: textoMargen)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: mostrarOpciones ? "chevron.up" : "chevron.down")
                    .foregroundStyle(mostrarOpciones ? Color.accentColor : Color.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        mostrarOpciones ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: mostrarOpciones ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(navegacion.preparando)
    }

    /// Botones de peajes y autovías y la barra de tiempo extra, ocupando todo el
    /// sitio que haya. Al cambiar algo con un destino elegido se vuelven a
    /// calcular las rutas.
    private var opcionesRuta: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                botonOpcion("Evitar peajes", icono: "eurosign.circle", activa: $navegacion.evitarPeajes)
                botonOpcion("Evitar autovías", icono: "road.lanes", activa: $navegacion.evitarAutopistas)
            }
            .frame(maxHeight: .infinity)
            barraMargen
        }
        .frame(maxHeight: .infinity)
    }

    /// Activada: el icono se tacha y el botón pasa a un tono claro del color de
    /// la app.
    private func botonOpcion(_ titulo: LocalizedStringKey, icono: String, activa: Binding<Bool>) -> some View {
        let marcada = activa.wrappedValue
        return Button {
            activa.wrappedValue.toggle()
        } label: {
            VStack(spacing: 8) {
                IconoTachable(nombre: icono, tachado: marcada)
                    .font(.system(size: 36))
                Text(titulo)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .foregroundStyle(marcada ? Color.accentColor : Color.primary)
            .background(
                marcada ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(marcada ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
        .disabled(navegacion.preparando)
    }

    /// Barra del tiempo extra admitido para la ruta con más curvas, de 0 a 200 %.
    /// Más corta que el panel, con − y + de 25 en 25 % a los lados.
    private var barraMargen: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Tiempo extra alternativas", systemImage: "clock")
                Spacer()
                Text(verbatim: textoMargen)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)
            HStack(spacing: 14) {
                botonPaso(icono: "minus", pasos: -1)
                Slider(value: $navegacion.margenExtra, in: 0...2, step: 0.05)
                botonPaso(icono: "plus", pasos: 1)
            }
        }
        .disabled(navegacion.preparando)
    }

    private func botonPaso(icono: String, pasos: Int) -> some View {
        Button {
            navegacion.cambiarMargen(pasos: pasos)
        } label: {
            Image(systemName: icono)
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(pasos > 0 ? "Más tiempo extra" : "Menos tiempo extra"))
    }

    private var textoMargen: String {
        "+\(Int((navegacion.margenExtra * 100).rounded())) %"
    }

    @ViewBuilder
    private var rutasPropuestas: some View {
        if navegacion.calculando {
            HStack {
                ProgressView()
                Text("Calculando las rutas…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Mientras se prepara la navegación, la elegida no se cambia
            VStack(spacing: 8) {
                ForEach(navegacion.variantes) { variante in
                    tarjetaVariante(variante)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .disabled(navegacion.preparando)
        }
    }

    private func tarjetaVariante(_ variante: VarianteRuta) -> some View {
        let esElegida = variante.tipos.contains(navegacion.elegida)
        let tono = color(variante.tipo)
        return Button {
            navegacion.elegida = variante.tipo
            // También si ya era la elegida: vuelve a encuadrarla
            encuadrarElegida()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: variante.tipo.icono)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tono, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: variante.nombre)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: resumen(variante))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let avisos = avisos(variante) {
                        Label {
                            Text(verbatim: avisos)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: esElegida ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(esElegida ? tono : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                esElegida ? tono.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(esElegida ? tono : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(esElegida ? .isSelected : [])
    }

    /// «1 h 26 min · 95 km · 33 curvas», y si no es la más rápida, lo que tarda
    /// de más.
    private func resumen(_ variante: VarianteRuta) -> String {
        var partes = [
            Flechas.duracion(variante.segundos),
            Flechas.distancia(variante.metros),
            variante.curvas == 1 ? "1 curva" : "\(variante.curvas) curvas",
        ]
        if !variante.tipos.contains(.rapida),
           let rapida = navegacion.variantes.first(where: { $0.tipos.contains(.rapida) }) {
            let demas = variante.segundos - rapida.segundos
            if demas >= 60 {
                partes.append("+" + Flechas.duracion(demas))
            }
        }
        return partes.joined(separator: " · ")
    }

    /// Peaje, autopista y tierra de la ruta, si los lleva. Los km son un
    /// máximo: Valhalla marca la maniobra entera.
    private func avisos(_ variante: VarianteRuta) -> String? {
        var partes: [String] = []
        if variante.metrosPeaje > 0 {
            partes.append("Peaje \(Flechas.distancia(variante.metrosPeaje))")
        }
        if variante.metrosAutopista > 0 {
            partes.append("Autopista \(Flechas.distancia(variante.metrosAutopista))")
        }
        if variante.metrosSinAsfaltar > 0 {
            partes.append("Sin asfaltar \(Flechas.distancia(variante.metrosSinAsfaltar))")
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    /// Cancelar (una X roja) e iniciar (grande, en verde).
    private var botonesRuta: some View {
        HStack(spacing: 12) {
            Button {
                navegacion.cancelarRuta()
                camara = .userLocation(fallback: .automatic)
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cancelar"))

            Button {
                navegacion.iniciar()
            } label: {
                HStack(spacing: 8) {
                    if navegacion.preparando {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "location.north.fill")
                    }
                    Text(navegacion.preparando ? "Preparando…" : "Iniciar")
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(navegacion.preparando || navegacion.variantes.isEmpty)
            .opacity(navegacion.variantes.isEmpty ? 0.5 : 1)
        }
    }

    /// Avisos sobre la parte de abajo del mapa: errores y rutas con tierra.
    private var avisosExploracion: some View {
        VStack(spacing: 6) {
            if let aviso = navegacion.aviso {
                etiquetaMapa(aviso, icono: "exclamationmark.circle.fill", color: .red)
            }
            if navegacion.sinRutaDeAsfalto {
                etiquetaMapa(
                    "Todas las rutas llevan algún tramo sin asfaltar.",
                    icono: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }

    private func etiquetaMapa(_ texto: String, icono: String, color: Color) -> some View {
        Label {
            Text(verbatim: texto)
        } icon: {
            Image(systemName: icono)
        }
        .font(.footnote.weight(.semibold))
        .multilineTextAlignment(.leading)
        .lineLimit(3)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(color)
    }

    /// Encuadra la ruta elegida entera en el mapa.
    private func encuadrarElegida() {
        guard let variante = navegacion.variantes.first(where: { $0.tipos.contains(navegacion.elegida) })
            ?? navegacion.variantes.first
        else { return }
        let puntos = variante.geometria
        guard puntos.count > 1 else { return }
        let rect = MKPolyline(coordinates: puntos, count: puntos.count).boundingMapRect
        let margen = max(rect.size.width, rect.size.height) * 0.15
        withAnimation {
            camara = .rect(rect.insetBy(dx: -margen, dy: -margen))
        }
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
    /// Apple la pone MapKit. Una línea, para que quepa en el panel.
    private var atribucion: some View {
        Text(verbatim: "Rutas: Valhalla (FOSSGIS) · © colaboradores de OpenStreetMap")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Icono de SF Symbols con una diagonal encima cuando `tachado` (Apple no trae
/// el euro ni la carretera tachados).
private struct IconoTachable: View {
    let nombre: String
    let tachado: Bool

    var body: some View {
        Image(systemName: nombre)
            .overlay {
                if tachado {
                    GeometryReader { geometria in
                        let lado = geometria.size
                        Path { trazo in
                            trazo.move(to: CGPoint(x: lado.width * 0.08, y: lado.height * 0.08))
                            trazo.addLine(to: CGPoint(x: lado.width * 0.92, y: lado.height * 0.92))
                        }
                        .stroke(.foreground, style: StrokeStyle(lineWidth: max(1.5, lado.width / 10), lineCap: .round))
                    }
                }
            }
    }
}

/// Ajustes: la simulación del recorrido (para pruebas) y la dirección del
/// servidor de rutas (Servidores.swift).
struct AjustesView: View {
    @ObservedObject var navegacion: Navegacion
    @Environment(\.dismiss) private var cerrar
    @AppStorage(Servidores.claveRutas) private var rutas = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Simular el recorrido", isOn: $navegacion.simular)
                    if navegacion.simular {
                        Picker("Velocidad", selection: $navegacion.factorSimulacion) {
                            Text(verbatim: "36 km/h").tag(UInt64(1))
                            Text(verbatim: "72 km/h").tag(UInt64(2))
                            Text(verbatim: "108 km/h").tag(UInt64(3))
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Pruebas")
                } footer: {
                    Text("En vez del GPS, una posición que recorre la ruta sola, para ver cambiar las indicaciones sin moverse.")
                }
                Section {
                    TextField(Servidores.rutasPorDefecto, text: $rutas)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Volver al servidor público") {
                        rutas = ""
                    }
                } header: {
                    Text("Rutas (Valhalla)")
                } footer: {
                    Text("Vacío: el servidor público de FOSSGIS. Uso razonable, como mucho una petición por segundo.")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
        }
    }
}
