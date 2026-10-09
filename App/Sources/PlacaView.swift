import SwiftUI
import LPRCore

// Prueba del enlace BLE con la placa (PROTOCOLO.md v0.6): estado de la
// conexión, batería del iPhone que se envía en MOVIL, un texto de prueba para
// la cara de navegación (NAV_TEXT), si se mandan la siguiente maniobra (NAV),
// el tramo de ruta (TRAZO) y sus cruces (CRUCES), y los ecos de STATUS. (El
// registro para depurar, que iba aquí hasta la 0.8.2, va al del sistema:
// EnlaceBLE.anotar)
struct PlacaView: View {
    @ObservedObject var enlace: EnlaceBLE
    @State private var textoPrueba = ""

    private let versionApp =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    var body: some View {
        NavigationStack {
            List {
                Section("Placa") {
                    LabeledContent("Estado") { Text(enlace.estado.texto) }
                    if enlace.estado.admiteReintento {
                        Button("Reintentar") { enlace.reintentar() }
                    }
                    if let nombre = enlace.nombre {
                        LabeledContent("Dispositivo") { Text(verbatim: nombre) }
                    }
                    if let info = enlace.info {
                        LabeledContent("Firmware") {
                            Text(verbatim: info.firmware.map { String($0) }.joined(separator: "."))
                        }
                    }
                }

                Section("Batería del iPhone") {
                    LabeledContent("Carga") { Text(enlace.bateria.estado.texto) }
                    LabeledContent("Nivel") {
                        if let nivel = enlace.bateria.nivel {
                            Text("\(Int(nivel)) %")
                        } else {
                            Text("Desconocido")
                        }
                    }
                }

                Section("Envío") {
                    LabeledContent("Última secuencia") { Text(texto(enlace.ultimaSecuencia)) }
                    LabeledContent("Eco de la placa") { Text(texto(enlace.ultimoEco)) }
                    LabeledContent("Latencia") {
                        if let latencia = enlace.latenciaMs {
                            Text("\(latencia) ms")
                        } else {
                            Text(verbatim: "—")
                        }
                    }
                    Button("Reenviar ahora") { enlace.reenviar() }
                        .disabled(enlace.estado != .conectado)
                }

                Section {
                    TextField("Texto para la cara de navegación", text: $textoPrueba, axis: .vertical)
                        .lineLimit(1...4)
                    HStack {
                        Button("Enviar") { enlace.ponerTextoPrueba(textoPrueba) }
                            .disabled(textoPrueba.isEmpty)
                        Spacer()
                        Button("Borrar", role: .destructive) {
                            textoPrueba = ""
                            enlace.ponerTextoPrueba(nil)
                        }
                    }
                    .buttonStyle(.borderless)
                    LabeledContent("Enviándose") {
                        Text(verbatim: enlace.textoCuadro ?? "—")
                            .lineLimit(2)
                    }
                    LabeledContent("Eco de la placa") { Text(texto(enlace.ecoTexto)) }
                } header: {
                    Text("Texto en el cuadro")
                } footer: {
                    Text("Sale en la cara de navegación del cuadro. Con una ruta iniciada, la app manda la indicación en su lugar.")
                }

                Section {
                    LabeledContent("Siguiente maniobra") {
                        if enlace.admiteNav {
                            Text(enlace.navActivo ? "Enviándose" : "Sin ruta")
                        } else {
                            Text("La placa no lo admite")
                        }
                    }
                    LabeledContent("Eco de la placa") { Text(texto(enlace.ecoNav)) }
                } header: {
                    Text("Flecha en el cuadro")
                } footer: {
                    Text("Con una ruta iniciada, la app manda la flecha de la siguiente maniobra, la distancia, lo que queda y la hora de llegada.")
                }

                Section {
                    LabeledContent("Tramo de ruta") {
                        if enlace.admiteTrazo {
                            Text(enlace.trazoActivo ? "Enviándose" : "Sin tramo")
                        } else {
                            Text("La placa no lo admite")
                        }
                    }
                    LabeledContent("Eco de la placa") { Text(texto(enlace.ecoTrazo)) }
                    LabeledContent("Cruces") {
                        if enlace.admiteCruces {
                            Text(enlace.trazoActivo ? "Con cada tramo" : "Sin tramo")
                        } else {
                            Text("La placa no lo admite")
                        }
                    }
                    LabeledContent("Eco de los cruces") { Text(texto(enlace.ecoCruces)) }
                    LabeledContent("Anillos de las rotondas") {
                        Text(enlace.admiteAnillos ? "Con los cruces" : "La placa no los dibuja")
                    }
                    LabeledContent("Movimiento suave") {
                        Text(enlace.admiteMovimiento ? "Con el tramo" : "La placa no lo admite")
                    }
                } header: {
                    Text("Recorrido en el cuadro")
                } footer: {
                    Text("Con una ruta iniciada, la app manda el tramo de ruta que queda por delante para dibujarlo en la cara de navegación, con las calles que salen de él.")
                }

                Section {
                    LabeledContent("GPS") {
                        Text(enlace.admiteGPS ? "Con cada posición" : "La placa no lo admite")
                    }
                    LabeledContent("Eco de la placa") { Text(texto(enlace.ecoGPS)) }
                } header: {
                    Text("GPS en el cuadro")
                } footer: {
                    Text("La precisión de la posición, para el punto de color del GPS en la cara de navegación. La posición no se manda.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .botonOcultarTeclado()
            .navigationTitle("Placa")
            .safeAreaInset(edge: .bottom) {
                Text("Versión \(versionApp) · protocolo v\(Int(Protocolo.version))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private func texto(_ valor: UInt8?) -> String {
        valor.map { String($0) } ?? "—"
    }
}

private extension EnlaceBLE.Estado {
    var texto: LocalizedStringKey {
        switch self {
        case .iniciando: return "Iniciando Bluetooth…"
        case .bluetoothApagado: return "Bluetooth apagado"
        case .sinPermiso: return "Sin permiso de Bluetooth"
        case .noDisponible: return "Bluetooth no disponible"
        case .buscando: return "Buscando la placa…"
        case .conectando: return "Conectando…"
        case .preparando: return "Preparando la conexión…"
        case .conectado: return "Conectado"
        case .sinServicio: return "La placa no muestra el servicio LPR"
        case .sinEmparejar: return "Sin emparejar"
        case .vinculoPerdido: return "La placa no reconoce el emparejamiento: omítela en Ajustes > Bluetooth"
        }
    }
}

private extension EstadoBateria {
    var texto: LocalizedStringKey {
        switch self {
        case .desconocido: return "Desconocido"
        case .sinCargar: return "Sin cargar"
        case .cargando: return "Cargando"
        case .cargada: return "Cargada"
        }
    }
}
