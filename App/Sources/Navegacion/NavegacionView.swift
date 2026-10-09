import MapKit
import SwiftUI
import LPRCore

/// Mapa con la posición y un buscador (Apple Maps), en el 55 % de arriba; en
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
    /// La barra del tiempo extra, desplegada con su botón (0.9.4)
    @State private var mostrarMargen = false
    @FocusState private var escribiendo: Bool

    /// Parte de la pantalla para el mapa; el resto, para el panel.
    private let partePantallaMapa: CGFloat = 0.55

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
            .botonOcultarTeclado()
            .sheet(isPresented: $mostrarAjustes) {
                AjustesView(navegacion: navegacion)
            }
        }
    }

    // MARK: - Exploración: mapa, búsqueda y rutas

    /// Con destino, el panel se despliega hacia arriba con las rutas.
    private var conDestino: Bool { navegacion.destino != nil }

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
                    // Mientras se escribe, todo para el mapa y las sugerencias.
                    // Sin destino, el mapa se queda con todo lo que no ocupe el
                    // panel, que solo lleva los botones (a petición del autor,
                    // 2026-10-09, con vista previa); con destino, el 55 %
                    .frame(height: escribiendo ? alto : (conDestino ? alto * partePantallaMapa : nil))
                    .frame(maxHeight: .infinity)
                if !escribiendo {
                    panelInferior
                        .frame(height: conDestino ? alto * (1 - partePantallaMapa) : nil)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: conDestino)
        }
        .onChange(of: navegacion.consulta) { _, _ in
            navegacion.consultaCambiada()
        }
        // Al terminar un cálculo, la ruta elegida entera. La barra del tiempo
        // extra sigue abierta si lo estaba, por si se cambia algo más
        .onChange(of: navegacion.calculos) { _, _ in
            encuadrarElegida()
        }
        .onChange(of: navegacion.destino == nil) { _, sinDestino in
            if sinDestino {
                mostrarMargen = false
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

    /// Arriba, los botones de peajes, autovías y tiempo extra, en una línea. Sin
    /// destino, solo eso (y la barra del tiempo, si se abre), con el alto justo:
    /// el resto es mapa (0.10.0). Con destino, se despliega hacia arriba con las
    /// rutas (o la barra del tiempo extra, si se abre, en su sitio) y los
    /// botones de cancelar e iniciar. Diseño aprobado por el autor el
    /// 2026-10-09 con vistas previas.
    private var panelInferior: some View {
        VStack(spacing: 8) {
            filaOpciones
            if mostrarMargen {
                barraMargen
                    .transition(.opacity)
            }
            if conDestino {
                if !mostrarMargen {
                    rutasPropuestas
                }
                botonesRuta
            }
            atribucion
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: conDestino ? .infinity : nil, alignment: .top)
        .background(.regularMaterial)
    }

    /// Los tres botones en cápsula, en la misma línea aunque haya que bajar la
    /// letra (a petición del autor): evitar peajes y evitar autovías se activan
    /// y desactivan; el del tiempo extra abre y cierra su barra. Activado o
    /// abierto, relleno del color de la app con el texto en blanco (y el icono
    /// tachado en los de evitar). Al cambiar algo con un destino elegido se
    /// vuelven a calcular las rutas.
    private var filaOpciones: some View {
        HStack(spacing: 6) {
            botonCapsula(activo: navegacion.evitarPeajes) {
                navegacion.evitarPeajes.toggle()
            } label: {
                IconoTachable(nombre: "eurosign.circle", tachado: navegacion.evitarPeajes)
                Text("Evitar peajes")
            }
            botonCapsula(activo: navegacion.evitarAutopistas) {
                navegacion.evitarAutopistas.toggle()
            } label: {
                IconoTachable(nombre: "road.lanes", tachado: navegacion.evitarAutopistas)
                Text("Evitar autovías")
            }
            botonCapsula(activo: mostrarMargen, ancho: false) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mostrarMargen.toggle()
                }
            } label: {
                Image(systemName: "clock")
                Text(verbatim: textoMargen)
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Tiempo extra alternativas: \(textoMargen)"))
        }
        .disabled(navegacion.preparando)
    }

    /// Botón en cápsula: sin activar, con el borde del color de la app; activado,
    /// relleno de ese color y con el texto en blanco. `ancho`: se reparte el
    /// sitio que sobra (los de evitar); si no, mide lo que su contenido.
    private func botonCapsula<Contenido: View>(
        activo: Bool,
        ancho: Bool = true,
        accion: @escaping () -> Void,
        @ViewBuilder label: () -> Contenido
    ) -> some View {
        Button(action: accion) {
            HStack(spacing: 4) {
                label()
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 9)
            .frame(maxWidth: ancho ? .infinity : nil, minHeight: 36)
            .foregroundStyle(activo ? Color.white : Color.accentColor)
            .background(activo ? Color.accentColor.opacity(0.85) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(activo ? 0.85 : 1), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !ancho, vertical: false)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    /// Barra del tiempo extra admitido para las alternativas, de 0 a 200 %, con
    /// − y + de 25 en 25 % a los lados. La despliega el botón del reloj; con
    /// destino, en el sitio de las rutas.
    private var barraMargen: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tiempo extra alternativas")
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
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxHeight: navegacion.destino != nil ? .infinity : nil)
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
            // Mientras se prepara la navegación, la elegida no se cambia. Si la
            // de más curvas es la misma que la más rápida, su tarjeta sale
            // igual, vacía (a petición del autor, 2026-10-09: sin una tarjeta
            // grande sola; tarjetaSinCoincidencia). La más rápida lleva
            // entonces solo su nombre
            let sinCurvasAparte = navegacion.variantes.contains {
                $0.tipos.contains(.rapida) && $0.tipos.contains(.divertida)
            }
            VStack(spacing: 8) {
                ForEach(navegacion.variantes) { variante in
                    tarjetaVariante(variante, nombre: sinCurvasAparte ? variante.tipo.nombre : variante.nombre)
                }
                if sinCurvasAparte {
                    tarjetaSinCoincidencia(.divertida)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .disabled(navegacion.preparando)
        }
    }

    /// Tarjeta de una ruta (diseño aprobado por el autor el 2026-10-09, 0.9.4):
    /// a la izquierda, el título; km, curvas y lo que tarda de más; y un aviso
    /// por línea, el peaje primero. Las líneas se reparten el alto: con menos
    /// avisos quedan menos líneas y todas las tarjetas miden lo mismo. A la
    /// derecha, en grande, el tiempo, en el sitio de la antigua marca de
    /// elegida (la elegida se distingue por el borde y el fondo).
    private func tarjetaVariante(_ variante: VarianteRuta, nombre: String) -> some View {
        let esElegida = variante.tipos.contains(navegacion.elegida)
        let tono = color(variante.tipo)
        let lista = avisos(variante)
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
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(verbatim: nombre)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(verbatim: resumen(variante))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ForEach(lista, id: \.self) { aviso in
                        Spacer(minLength: 0)
                        // La autopista solo informa (a petición del autor); el
                        // peaje y la tierra, advierten
                        Label {
                            Text(verbatim: aviso.texto)
                        } icon: {
                            Image(systemName: aviso.advierte ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(aviso.advierte ? Color.orange : Color.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: -2) {
                    ForEach(lineasDuracion(variante.segundos), id: \.self) { linea in
                        Text(verbatim: linea)
                    }
                }
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(esElegida ? tono : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
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

    /// Tarjeta de un papel sin ruta propia (la de más curvas, cuando coincide
    /// con la más rápida): del mismo alto que las demás, apagada y sin pulsar,
    /// con «No hay coincidencia» y el tiempo extra con el que se ha buscado.
    private func tarjetaSinCoincidencia(_ tipo: TipoVariante) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tipo.icono)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color(tipo).opacity(0.4), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(verbatim: tipo.nombre)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                // Si hay otras dentro del margen pero con menos curvas, subirlo
                // no ayudaría: se dice lo que pasa
                Text(navegacion.otrasEnMargen
                     ? "La más rápida es también la de más curvas"
                     : "No hay coincidencia con \(textoMargen) de tiempo extra")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
    }

    /// «1 h 26 min» en dos renglones («1 h» y «26 min»); con menos de una hora,
    /// uno («48 min»).
    private func lineasDuracion(_ segundos: Double) -> [String] {
        let texto = Flechas.duracion(segundos)
        guard let corte = texto.range(of: " h ") else { return [texto] }
        return [String(texto[..<corte.lowerBound]) + " h", String(texto[corte.upperBound...])]
    }

    /// «95 km · 33 curvas», y si no es la más rápida, lo que tarda de más
    /// («· +15 min»). El tiempo va aparte, en grande.
    private func resumen(_ variante: VarianteRuta) -> String {
        var partes = [
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

    /// Peaje, autopista y tierra de la ruta, si los lleva; `advierte` es false
    /// para lo que solo informa (la autopista). Desde la 0.10.0, tramo a tramo:
    /// por maniobras eran un máximo, porque Valhalla marca la maniobra entera
    /// (Segovia → Ávila → Talavera: 44 km de autopista en vez de 10).
    private func avisos(_ variante: VarianteRuta) -> [AvisoRuta] {
        // Tramo a tramo (Navegacion.detalles), cuando llegan: un momento
        // después que las rutas, y mientras tanto ninguno. Si no se pudieron
        // pedir, los de las maniobras, que son un máximo: «hasta». Por debajo
        // de 100 m no se avisa (un enlace o un cruce sueltos)
        let detalle = navegacion.detalles[variante.indice]
        guard detalle != nil || navegacion.detallesFallidos.contains(variante.indice) else { return [] }
        let peaje = detalle?.metrosPeaje ?? variante.metrosPeaje
        let autopista = detalle?.metrosAutopista ?? variante.metrosAutopista
        let tierra = detalle?.metrosSinAsfaltar ?? variante.metrosSinAsfaltar
        let hasta = detalle == nil ? "hasta " : ""
        var avisos: [AvisoRuta] = []
        if peaje >= 100 {
            avisos.append(AvisoRuta(texto: "Peaje \(hasta)\(Flechas.distancia(peaje))", advierte: true))
        }
        if autopista >= 100 {
            avisos.append(AvisoRuta(texto: "Autopista \(hasta)\(Flechas.distancia(autopista))", advierte: false))
        }
        if tierra >= 100 {
            avisos.append(AvisoRuta(texto: "Sin asfaltar \(hasta)\(Flechas.distancia(tierra))", advierte: true))
        }
        return avisos
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
                    if navegacion.llegada, let viaje = navegacion.resumenLlegada {
                        // Al llegar, el resumen del viaje, como en el cuadro
                        // (NAV, v0.10): lo recorrido por el GPS, el tiempo
                        // desde «Iniciar» y la velocidad media
                        VStack {
                            Text("Recorrido").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: Flechas.distancia(viaje.metros)).font(.headline)
                        }
                        VStack {
                            Text("Tiempo").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: Flechas.duracion(viaje.segundos)).font(.headline)
                        }
                        if let media = viaje.velocidadMedia {
                            VStack {
                                Text("Media").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: "\(Int((media * 3.6).rounded())) km/h").font(.headline)
                            }
                        }
                    } else {
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
                    // Solo la vía o la salida, como en el cuadro (Flechas.nombre)
                    if let texto = navegacion.maniobra?.texto, !texto.isEmpty {
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
        .background(.black)
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

/// Aviso de una ruta en su tarjeta (peaje, autopista, tierra).
private struct AvisoRuta: Hashable {
    let texto: String
    /// true: advierte (triángulo naranja); false: solo informa (círculo azul)
    let advierte: Bool
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
                            Text(verbatim: "50 km/h").tag(UInt64(1))
                            Text(verbatim: "100 km/h").tag(UInt64(2))
                            Text(verbatim: "150 km/h").tag(UInt64(3))
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
            .botonOcultarTeclado()
        }
    }
}
