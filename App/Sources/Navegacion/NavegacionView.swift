import SwiftUI

/// Buscar el destino y, al elegirlo, guiar: flecha, metros hasta el giro,
/// instrucción, lo que falta y la altitud.
struct NavegacionView: View {
    @ObservedObject var navegacion: Navegacion
    @State private var mostrarAjustes = false

    var body: some View {
        NavigationStack {
            Group {
                if navegacion.navegando {
                    guiado
                } else {
                    busqueda
                }
            }
            .navigationTitle("Navegar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrarAjustes = true
                    } label: {
                        Label("Servidores", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $mostrarAjustes) {
                AjustesServidoresView()
            }
        }
    }

    // MARK: - Búsqueda

    private var busqueda: some View {
        List {
            Section {
                HStack {
                    TextField("Destino: calle, pueblo, lugar…", text: $navegacion.consulta)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { navegacion.buscar() }
                    if navegacion.buscando {
                        ProgressView()
                    } else {
                        Button("Buscar") { navegacion.buscar() }
                            .disabled(navegacion.consulta.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } footer: {
                Text("La búsqueda se hace al pulsar Buscar, no mientras escribes.")
            }

            if let aviso = navegacion.aviso {
                Section {
                    Text(verbatim: aviso)
                        .foregroundStyle(.red)
                }
            }

            if !navegacion.resultados.isEmpty {
                Section("Resultados") {
                    ForEach(navegacion.resultados) { resultado in
                        Button {
                            navegacion.navegar(a: resultado)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: resultado.nombre)
                                    .foregroundStyle(.primary)
                                Text(verbatim: resultado.descripcion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .disabled(navegacion.calculando)
                    }
                }
            }

            if navegacion.calculando {
                Section {
                    HStack {
                        ProgressView()
                        Text("Calculando la ruta en moto…")
                    }
                }
            }

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
            } footer: {
                Text("La posición recorre la ruta sola, para ver cambiar las indicaciones sin moverte. La ruta sale de tu posición real.")
            }

            Section("GPS") {
                LabeledContent("Posición") {
                    Text(navegacion.hayPosicion ? "Con señal" : "Esperando señal…")
                }
                LabeledContent("Altitud") { Text(textoAltitud) }
            }

            Section {
                atribucion
            }
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
                if let destino = navegacion.destino {
                    Text(verbatim: destino.nombre)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(role: .destructive) {
                    navegacion.terminar()
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
                aviso("Simulación: la posición no es la real", icono: "play.circle", color: .blue)
            }
            if navegacion.recalculando {
                aviso("Recalculando la ruta…", icono: "arrow.triangle.2.circlepath", color: .orange)
            } else if navegacion.fueraDeRuta {
                aviso("Fuera de ruta", icono: "exclamationmark.triangle", color: .orange)
            }
        }
    }

    private func aviso(_ texto: LocalizedStringKey, icono: String, color: Color) -> some View {
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

    /// Atribución que exigen los datos de OpenStreetMap (ODbL) y la política de
    /// uso de Nominatim.
    private var atribucion: some View {
        Text(verbatim: "Mapa: Apple · Rutas: Valhalla (FOSSGIS) · Búsqueda: Nominatim · Datos de ruta © colaboradores de OpenStreetMap")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Direcciones de los servidores de rutas y de búsqueda (Servidores.swift).
struct AjustesServidoresView: View {
    @Environment(\.dismiss) private var cerrar
    @AppStorage(Servidores.claveRutas) private var rutas = ""
    @AppStorage(Servidores.claveBusqueda) private var busqueda = ""

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
                    TextField(Servidores.busquedaPorDefecto, text: $busqueda)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Búsqueda (Nominatim)")
                } footer: {
                    Text("Vacío: el servidor público de OpenStreetMap, con su política de uso: operations.osmfoundation.org/policies/nominatim")
                }
                Section {
                    Button("Volver a los servidores públicos") {
                        rutas = ""
                        busqueda = ""
                    }
                }
            }
            .navigationTitle("Servidores")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
        }
    }
}
