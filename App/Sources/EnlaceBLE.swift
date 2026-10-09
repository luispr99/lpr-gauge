import CoreBluetooth
import Foundation
import os
import UIKit
import LPRCore

/// Enlace BLE con el cuadro o con el firmware de referencia (docs/PROTOCOLO.md,
/// v0.5). Manda `MOVIL` (estado de la batería del iPhone; con el cuadro, solo al
/// cambiar), `NAV_TEXT` (texto de la navegación) y `TRAZO` (tramo de ruta por
/// delante), y lee `STATUS`. En segundo plano sigue con el modo
/// `bluetooth-central`: cada `STATUS` despierta a la app y sirve de
/// mantenimiento (§10). Sin restauración de estado.
///
/// Core Bluetooth entrega sus avisos en la cola principal (`queue: nil`), así que
/// los métodos de los delegados pasan al actor principal con `assumeIsolated`.
@MainActor
final class EnlaceBLE: NSObject, ObservableObject {
    enum Estado: Equatable {
        case iniciando
        case bluetoothApagado
        case sinPermiso
        case noDisponible
        case buscando
        case conectando
        case preparando
        case conectado
        /// Conectado, pero sin el servicio LPR o con un error al descubrirlo.
        case sinServicio
        /// No se pudo cifrar el enlace o se canceló el emparejamiento.
        case sinEmparejar
        /// La placa ya no reconoce el emparejamiento que guarda el iPhone.
        case vinculoPerdido

        /// Estados en los que la vista ofrece «Reintentar».
        var admiteReintento: Bool {
            self == .sinServicio || self == .sinEmparejar || self == .vinculoPerdido
        }
    }

    @Published private(set) var estado: Estado = .iniciando
    @Published private(set) var nombre: String?
    @Published private(set) var info: DeviceInfo?
    /// Último estado de la batería leído; su secuencia es la del último envío.
    @Published private(set) var bateria = MensajeMovil(secuencia: 0, estado: .desconocido, nivel: nil)
    @Published private(set) var ultimaSecuencia: UInt8?
    @Published private(set) var ultimoEco: UInt8?
    @Published private(set) var latenciaMs: Int?
    /// Texto que se manda a la cara de navegación del cuadro (NAV_TEXT), nil sin
    /// texto, y el último eco de la placa.
    @Published private(set) var textoCuadro: String?
    @Published private(set) var ecoTexto: UInt8?
    /// Si se está mandando un tramo de ruta (TRAZO), y el último eco de la placa.
    @Published private(set) var trazoActivo = false
    @Published private(set) var ecoTrazo: UInt8?

    private var central: CBCentralManager?
    private var periferico: CBPeripheral?
    private var caracInfo: CBCharacteristic?
    private var caracStatus: CBCharacteristic?
    private var caracMovil: CBCharacteristic?
    private var caracTexto: CBCharacteristic?
    private var caracTrazo: CBCharacteristic?
    private var secuencia = Secuencia()
    /// Cada característica lleva su secuencia (PROTOCOLO.md §3).
    private var secuenciaTexto = Secuencia()
    private var secuenciaTrazo = Secuencia()
    private var textoPendiente = false
    private var trazoPendiente = false
    private var primerTextoAnotado = false
    private var primerTrazoAnotado = false
    /// Cuándo se mandó por última vez cada característica: el mantenimiento
    /// (§10) repite cada una cuando le toca, no todas a la vez, para que no
    /// salgan en ráfagas (lo vio la revisión de la 0.9.0).
    private var ultimoMovil: Date?
    private var ultimoTexto: Date?
    private var ultimoTrazo: Date?
    /// Hay un tramo más nuevo que el último mandado (llegó antes de 1 s).
    private var trazoNuevo = false
    /// MOVIL al cambiar (v0.5): lo último mandado, y su secuencia mientras la
    /// placa no confirme con el eco que lo ha recibido.
    private var movilEnviado: MensajeMovil?
    private var movilPorConfirmar: UInt8?
    private var ultimoReenvioPedido: Date?
    /// Hora de envío de cada secuencia pendiente de eco, para la latencia.
    private var enviados: [UInt8: Date] = [:]
    /// El primer STATUS tras suscribirse puede traer el eco 0 de «aún no he
    /// recibido nada» (PROTOCOLO.md §9): no sirve para medir la latencia.
    private var ignorarLatencia = true
    private var envioPendiente = false
    private var reintentosLectura = 0
    /// Cada preparación (descubrir servicios → DEVICE_INFO → STATUS) lleva un
    /// número; el vigilante solo actúa si sigue siendo la misma.
    private var preparacion = 0
    private var primerEnvioAnotado = false
    private var colaLlenaAnotada = false
    private var primerStatusAnotado = false
    private var inicioBusqueda: Date?
    private var pistaBusquedaDada = false
    private var mantenimiento: Timer?
    private var busqueda: Timer?

    private let uuidServicio = CBUUID(string: Protocolo.UUIDs.servicio)
    private let uuidInfo = CBUUID(string: Protocolo.UUIDs.deviceInfo)
    private let uuidStatus = CBUUID(string: Protocolo.UUIDs.status)
    private let uuidMovil = CBUUID(string: Protocolo.UUIDs.movil)
    private let uuidTexto = CBUUID(string: Protocolo.UUIDs.navText)
    private let uuidTrazo = CBUUID(string: Protocolo.UUIDs.trazo)

    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(bateriaCambiada),
                                               name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(bateriaCambiada),
                                               name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        leerBateria()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Manda ahora el estado de la batería, sin esperar al mantenimiento.
    func reenviar() {
        enviarMovil()
    }

    /// Corta la conexión y vuelve a conectar desde cero (un enlace nuevo permite
    /// volver a emparejar). Lo ofrece la vista en los estados de error.
    func reintentar() {
        reintentosLectura = 0
        guard let central, central.state == .poweredOn else { return }
        guard let periferico else {
            empezar()
            return
        }
        anotar("Reintentando: se corta la conexión y se vuelve a conectar")
        estado = .conectando
        if periferico.state == .disconnected {
            central.connect(periferico, options: nil)
        } else {
            // La desconexión llega a perdido(), que vuelve a conectar
            central.cancelPeripheralConnection(periferico)
        }
    }

    // MARK: - Batería

    @objc private func bateriaCambiada() {
        let anterior = bateria
        leerBateria()
        if bateria.estado != anterior.estado {
            anotar("Batería: \(descripcion(bateria.estado))")
        }
        // mantener() lo manda si ha cambiado respecto a lo último enviado
        if mantenimiento != nil {
            mantener()
        }
    }

    private func leerBateria() {
        let dispositivo = UIDevice.current
        let estado: EstadoBateria
        switch dispositivo.batteryState {
        case .unplugged: estado = .sinCargar
        case .charging: estado = .cargando
        case .full: estado = .cargada
        default: estado = .desconocido
        }
        let nivel: UInt8? = dispositivo.batteryLevel < 0
            ? nil
            : UInt8(min(100, max(0, (dispositivo.batteryLevel * 100).rounded())))
        // Solo si cambia: se lee cada 0,5 s (mantener) y `bateria` es @Published
        if estado != bateria.estado || nivel != bateria.nivel {
            bateria = MensajeMovil(secuencia: bateria.secuencia, estado: estado, nivel: nivel)
        }
    }

    // MARK: - Búsqueda y conexión

    private func empezar() {
        guard let central else { return }
        if conectarSiYaConectada() { return }
        estado = .buscando
        inicioBusqueda = Date()
        pistaBusquedaDada = false
        central.scanForPeripherals(withServices: [uuidServicio], options: nil)
        anotar("Buscando el servicio LPR…")
        // Mientras dura la búsqueda se vuelve a mirar si el sistema ya está
        // conectado a la placa: conectada, la placa no se anuncia
        busqueda?.invalidate()
        busqueda = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            // El temporizador va en el bucle principal: ya está en el actor principal
            MainActor.assumeIsolated {
                self.revisarBusqueda()
            }
        }
    }

    /// Si el sistema ya está conectado a la placa (por ejemplo, por las
    /// notificaciones del cuadro), aprovecha esa conexión.
    private func conectarSiYaConectada() -> Bool {
        guard let central,
              let conectado = central.retrieveConnectedPeripherals(withServices: [uuidServicio]).first
        else { return false }
        central.stopScan()
        pararBusqueda()
        anotar("La placa ya estaba conectada al iPhone")
        conectar(conectado)
        return true
    }

    private func revisarBusqueda() {
        guard estado == .buscando else {
            pararBusqueda()
            return
        }
        if conectarSiYaConectada() { return }
        if !pistaBusquedaDada, let inicio = inicioBusqueda, Date().timeIntervalSince(inicio) > 10 {
            pistaBusquedaDada = true
            anotar("Sin rastro de la placa. Si en Ajustes > Bluetooth sale como conectada, omítela y vuelve a abrir la app (PROTOCOLO.md §11)")
        }
    }

    private func pararBusqueda() {
        busqueda?.invalidate()
        busqueda = nil
    }

    private func conectar(_ periferico: CBPeripheral) {
        self.periferico = periferico
        periferico.delegate = self
        if nombre == nil { nombre = periferico.name }
        estado = .conectando
        central?.connect(periferico, options: nil)
    }

    private func encontrado(_ periferico: CBPeripheral, nombreAnunciado: String?, rssi: Int) {
        central?.stopScan()
        pararBusqueda()
        nombre = nombreAnunciado ?? periferico.name
        anotar("Encontrada \(nombre ?? "una placa sin nombre") (RSSI \(rssi) dBm)")
        conectar(periferico)
    }

    private func conectado(_ periferico: CBPeripheral) {
        estado = .preparando
        reintentosLectura = 0
        anotar("Conectado. Buscando el servicio…")
        vigilarPreparacion()
        periferico.discoverServices([uuidServicio])
    }

    /// Si la preparación no termina (por ejemplo, porque un aviso de servicios
    /// cambiados llega a mitad), corta la conexión para empezar de cero con un
    /// enlace nuevo: perdido() vuelve a conectar.
    private func vigilarPreparacion() {
        preparacion += 1
        let intento = preparacion
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.preparacion == intento, self.estado == .preparando,
                  let periferico = self.periferico else { return }
            self.anotar("La preparación no ha terminado en 10 s: se corta y se vuelve a conectar")
            self.central?.cancelPeripheralConnection(periferico)
        }
    }

    private func serviciosCambiados(_ periferico: CBPeripheral, invalidados: [CBUUID]) {
        anotar("La placa avisa de servicios cambiados (\(invalidados.count) invalidados)")
        // Solo hace falta repetir la preparación si afecta al servicio LPR
        guard invalidados.contains(uuidServicio) || caracMovil == nil else { return }
        anotar("Se vuelve a buscar el servicio LPR")
        olvidarCaracteristicas()
        estado = .preparando
        vigilarPreparacion()
        periferico.discoverServices([uuidServicio])
    }

    private func perdido(_ periferico: CBPeripheral, error: Error?, alConectar: Bool) {
        olvidarCaracteristicas()
        anotar((alConectar ? "No se pudo conectar" : "Desconectado")
               + (error.map { ": \($0.localizedDescription)" } ?? ""))
        if esVinculoPerdido(error) {
            vinculoPerdido()
            return
        }
        // Tras avisar del vínculo perdido no se reconecta: volvería a fallar
        guard estado != .vinculoPerdido, central?.state == .poweredOn else { return }
        estado = .conectando
        anotar("Esperando a que la placa vuelva…")
        if alConectar {
            // Un fallo al conectar se reintenta con un respiro
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.estado == .conectando else { return }
                self.central?.connect(periferico, options: nil)
            }
        } else {
            // Conexión pendiente: no caduca y se completa sola cuando la placa
            // vuelve a anunciarse (por ejemplo, tras reiniciarla)
            central?.connect(periferico, options: nil)
        }
    }

    private func vinculoPerdido() {
        estado = .vinculoPerdido
        anotar("La placa no reconoce el emparejamiento del iPhone. En Ajustes > Bluetooth, omite la placa y pulsa Reintentar")
        if let periferico, periferico.state != .disconnected {
            central?.cancelPeripheralConnection(periferico)
        }
    }

    private func olvidarCaracteristicas() {
        caracInfo = nil
        caracStatus = nil
        caracMovil = nil
        caracTexto = nil
        caracTrazo = nil
        info = nil
        mantenimiento?.invalidate()
        mantenimiento = nil
        ultimoMovil = nil
        ultimoTexto = nil
        ultimoTrazo = nil
        trazoNuevo = false
        movilEnviado = nil
        movilPorConfirmar = nil
        ultimoReenvioPedido = nil
        enviados.removeAll()
        envioPendiente = false
        textoPendiente = false
        trazoPendiente = false
        primerTextoAnotado = false
        primerTrazoAnotado = false
        primerEnvioAnotado = false
        colaLlenaAnotada = false
        primerStatusAnotado = false
    }

    // MARK: - Servicio y características

    private func serviciosDescubiertos(_ periferico: CBPeripheral, error: Error?) {
        if let error {
            estado = .sinServicio
            anotar("Error al buscar servicios: \(error.localizedDescription)")
            return
        }
        guard let servicio = periferico.services?.first(where: { $0.uuid == uuidServicio }) else {
            estado = .sinServicio
            anotar("La placa no muestra el servicio LPR. Si el iPhone recuerda los servicios antiguos, omite la placa en Ajustes > Bluetooth (PROTOCOLO.md §11)")
            return
        }
        periferico.discoverCharacteristics([uuidInfo, uuidStatus, uuidMovil, uuidTexto, uuidTrazo], for: servicio)
    }

    private func caracteristicasDescubiertas(_ periferico: CBPeripheral, servicio: CBService, error: Error?) {
        if let error {
            estado = .sinServicio
            anotar("Error al buscar características: \(error.localizedDescription)")
            return
        }
        for caracteristica in servicio.characteristics ?? [] {
            switch caracteristica.uuid {
            case uuidInfo: caracInfo = caracteristica
            case uuidStatus: caracStatus = caracteristica
            case uuidMovil: caracMovil = caracteristica
            case uuidTexto: caracTexto = caracteristica
            case uuidTrazo: caracTrazo = caracteristica
            default: break
            }
        }
        guard let caracInfo else {
            estado = .sinServicio
            anotar("La placa no tiene DEVICE_INFO")
            return
        }
        // DEVICE_INFO exige cifrado: al leerla, iOS cifra el enlace o pide
        // emparejar y repite la lectura (PROTOCOLO.md §2)
        periferico.readValue(for: caracInfo)
    }

    private func valorRecibido(_ caracteristica: CBCharacteristic, bytes: [UInt8]?, error: Error?) {
        // Puede llegar la respuesta a una lectura anterior a un aviso de
        // servicios cambiados: solo vale la de las características vigentes
        if caracteristica === caracInfo {
            if let error {
                errorEnDeviceInfo(error)
                return
            }
            guard let bytes, let info = DeviceInfo.decodificar(bytes) else {
                estado = .sinServicio
                anotar("DEVICE_INFO no válida: \(hex(bytes ?? []))")
                return
            }
            self.info = info
            anotar("DEVICE_INFO: tipo \(info.tipo), firmware \(version(info.firmware))")
            listo()
        } else if caracteristica === caracStatus {
            if let error {
                anotar("Error en STATUS: \(error.localizedDescription)")
                return
            }
            guard let bytes, let status = MensajeStatus.decodificar(bytes) else {
                anotar("STATUS no válido: \(hex(bytes ?? []))")
                return
            }
            if !primerStatusAnotado {
                primerStatusAnotado = true
                anotar("Primer STATUS de la placa: \(hex(bytes))")
            }
            if let eco = status.ecoMovil {
                ultimoEco = eco
                if ignorarLatencia {
                    ignorarLatencia = false
                } else if let hora = enviados.removeValue(forKey: eco) {
                    latenciaMs = Int(Date().timeIntervalSince(hora) * 1000)
                }
                // Confirmado. Con «pide reenvío» el eco puede ser el 0 de «aún
                // no he recibido nada» (§9): no confirma
                if !status.pideReenvio, eco == movilPorConfirmar {
                    movilPorConfirmar = nil
                }
            }
            if let eco = status.ecoNavText {
                ecoTexto = eco
            }
            if let eco = status.ecoTrazo {
                ecoTrazo = eco
            }
            // Mantenimiento también al recibir STATUS (§10): en segundo plano el
            // temporizador puede no dispararse, y cada aviso de la placa
            // despierta a la app. mantener() solo manda lo que toca, así que
            // el STATUS que contesta a cada escritura no provoca otra. Si la
            // placa pide reenvío, todo, como mucho cada 0,5 s
            guard mantenimiento != nil else { return }
            let ahora = Date()
            if status.pideReenvio,
               ultimoReenvioPedido.map({ ahora.timeIntervalSince($0) >= Self.reenvioPedidoMinimo }) ?? true {
                ultimoReenvioPedido = ahora
                mantener(todo: true)
            } else {
                mantener()
            }
        }
    }

    private func errorEnDeviceInfo(_ error: Error) {
        if esVinculoPerdido(error) {
            vinculoPerdido()
            return
        }
        let ns = error as NSError
        let faltaCifrado = ns.domain == CBATTErrorDomain
            && (ns.code == CBATTError.Code.insufficientAuthentication.rawValue
                || ns.code == CBATTError.Code.insufficientEncryption.rawValue)
        if faltaCifrado && reintentosLectura < 2 {
            // El emparejamiento puede llegar un poco después, por la petición
            // de cifrado que hace la placa
            reintentosLectura += 1
            anotar("DEVICE_INFO pide cifrado: se reintenta en 3 s (\(reintentosLectura)/2)")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.reintentarLectura()
            }
            return
        }
        estado = .sinEmparejar
        anotar("No se pudo cifrar ni emparejar: \(error.localizedDescription). Pulsa Reintentar")
    }

    private func reintentarLectura() {
        guard estado == .preparando, let periferico, let caracInfo else { return }
        periferico.readValue(for: caracInfo)
    }

    private func listo() {
        guard let periferico, let info else { return }
        guard caracStatus != nil || caracMovil != nil || caracTexto != nil else { return }
        if let caracStatus {
            ignorarLatencia = true
            periferico.setNotifyValue(true, for: caracStatus)
        }
        estado = .conectado
        let conMovil = info.capacidades.contains(.movil) && caracMovil != nil
        let conTexto = info.capacidades.contains(.navText) && caracTexto != nil
        let conTrazo = admiteTrazo
        if !conMovil {
            anotar("La placa no admite MOVIL")
        }
        if !conTexto {
            anotar("La placa no admite NAV_TEXT (texto de navegación)")
        }
        if !conTrazo {
            anotar("La placa no admite TRAZO (tramo de ruta)")
        }
        guard conMovil || conTexto || conTrazo else { return }
        mantenimiento?.invalidate()
        // Cada 0,5 s se mira qué toca mandar (mantener)
        let temporizador = Timer(timeInterval: Self.tic, repeats: true) { [weak self] _ in
            guard let self else { return }
            // El temporizador va en el bucle principal: ya está en el actor principal
            MainActor.assumeIsolated {
                self.mantener()
            }
        }
        // En los modos comunes: en el modo por defecto no se dispara mientras se
        // arrastra o se desplaza una lista, y con más de 5 s el cuadro daría el
        // dato por caducado (lo vio la revisión)
        RunLoop.main.add(temporizador, forMode: .common)
        mantenimiento = temporizador
        // Al conectar, el estado completo sin esperar a ningún cambio (§10)
        mantener(todo: true)
        if conMovil && !movilAlCambiar {
            anotar("La placa no admite MOVIL al cambiar: se repite cada 2 s")
        }
    }

    /// Lo que toca mandar ahora (§10), sin repetir lo que acaba de salir:
    /// - MOVIL, si ha cambiado la batería, si su eco no ha llegado en 2 s y, con
    ///   una placa sin «MOVIL al cambiar» (v0.5), cada 1,5-2 s;
    /// - el texto y el tramo, mientras los haya, cada 1,5-2 s; un tramo más
    ///   nuevo que el mandado, en cuanto pase 1 s desde el anterior (§7 ter).
    /// `todo`: al conectar y cuando la placa pide reenvío.
    private func mantener(todo: Bool = false) {
        let ahora = Date()
        func pasado(_ momento: Date?, _ segundos: TimeInterval) -> Bool {
            momento.map { ahora.timeIntervalSince($0) >= segundos } ?? true
        }
        leerBateria()
        let cambiada = movilEnviado.map { $0.estado != bateria.estado || $0.nivel != bateria.nivel } ?? true
        let sinEco = movilPorConfirmar != nil && pasado(ultimoMovil, Self.movilSinEco)
        let periodico = !movilAlCambiar && pasado(ultimoMovil, Self.repeticion)
        if todo || cambiada || sinEco || periodico {
            enviarMovil()
        }
        if textoCuadro != nil, todo || pasado(ultimoTexto, Self.repeticion) {
            enviarTexto()
        }
        if trazoActivo, todo || pasado(ultimoTrazo, Self.repeticion) || (trazoNuevo && pasado(ultimoTrazo, Self.trazoMinimo)) {
            enviarTrazo()
        }
    }

    /// La placa da MOVIL por bueno mientras dure la conexión (v0.5): se manda
    /// solo al cambiar (a petición del autor, 2026-10-09).
    private var movilAlCambiar: Bool {
        info?.capacidades.contains(.movilAlCambiar) == true
    }

    /// Cada cuánto se mira qué mandar; lo que se repite, a los 1,5 s (con el
    /// tic, cada 1,5-2 s: el mínimo de 2 s de §10 y lejos de los 5 de la
    /// caducidad); un tramo nuevo, como mucho uno por segundo (§7 ter); MOVIL
    /// sin eco, a los 2 s; y el reenvío que pide la placa, como mucho cada 0,5 s.
    private static let tic: TimeInterval = 0.5
    private static let repeticion: TimeInterval = 1.5
    private static let trazoMinimo: TimeInterval = 1
    private static let movilSinEco: TimeInterval = 2
    private static let reenvioPedidoMinimo: TimeInterval = 0.5

    // MARK: - Texto de navegación (NAV_TEXT, PROTOCOLO.md §7 bis)

    /// El de la ruta iniciada y el de prueba de la pestaña Placa. Manda el de la
    /// ruta si lo hay; si no, el de prueba.
    private var textoNavegacion: String?
    private var textoPrueba: String?

    /// Texto de la navegación (lo pone Navegacion): nil sin ruta.
    func ponerTextoNavegacion(_ texto: String?) {
        textoNavegacion = (texto?.isEmpty ?? true) ? nil : texto
        aplicarTexto()
    }

    /// Texto de prueba (pestaña Placa): nil lo borra.
    func ponerTextoPrueba(_ texto: String?) {
        textoPrueba = (texto?.isEmpty ?? true) ? nil : texto
        aplicarTexto()
    }

    /// Se manda al cambiar y, mientras lo haya, con el mantenimiento; si deja de
    /// haberlo, una vez un texto vacío para borrarlo.
    private func aplicarTexto() {
        let nuevo = textoNavegacion ?? textoPrueba
        guard nuevo != textoCuadro else { return }
        textoCuadro = nuevo
        enviarTexto()
    }

    private func enviarTexto() {
        guard estado == .conectado, let periferico, let caracTexto,
              info?.capacidades.contains(.navText) == true else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            textoPendiente = true
            return
        }
        textoPendiente = false
        let mensaje = MensajeNavText(secuencia: secuenciaTexto.siguiente(), texto: textoCuadro ?? "")
        let bytes = mensaje.codificar(maximo: periferico.maximumWriteValueLength(for: .withoutResponse))
        periferico.writeValue(Data(bytes), for: caracTexto, type: .withoutResponse)
        ultimoTexto = Date()
        if !primerTextoAnotado {
            primerTextoAnotado = true
            anotar("NAV_TEXT enviado (seq \(mensaje.secuencia), \(bytes.count) bytes)")
        }
    }

    // MARK: - Tramo de ruta (TRAZO, PROTOCOLO.md §7 ter)

    private var puntosTrazo: [PuntoPlano] = []
    private var giroTrazo: Int?

    /// Si la placa conectada admite TRAZO: si no, no hace falta calcularlo.
    var admiteTrazo: Bool {
        estado == .conectado && caracTrazo != nil && info?.capacidades.contains(.trazo) == true
    }

    /// Cuántos puntos caben en un TRAZO con la conexión actual (como mucho, 44).
    var puntosTrazoQueCaben: Int {
        guard let periferico, estado == .conectado else { return MensajeTrazo.maximoPuntos }
        return MensajeTrazo.puntosQueCaben(periferico.maximumWriteValueLength(for: .withoutResponse))
    }

    /// Tramo de ruta por delante (lo pone Navegacion en cada posición), en los
    /// ejes de la moto; nil sin tramo. Se manda al cambiar, como mucho una vez
    /// por segundo: lo que llegue antes queda guardado y sale en cuanto pase
    /// el segundo (mantener, cada 0,5 s); al dejar de haberlo, una vez sin
    /// tramo para borrarlo.
    func ponerTrazo(_ tramo: (puntos: [PuntoPlano], giro: Int?)?) {
        guard let tramo, tramo.puntos.count >= 2 else {
            guard trazoActivo else { return }
            trazoActivo = false
            trazoNuevo = false
            puntosTrazo = []
            giroTrazo = nil
            enviarTrazo()
            return
        }
        let nuevo = !trazoActivo
        puntosTrazo = tramo.puntos
        giroTrazo = tramo.giro
        if nuevo { trazoActivo = true }
        if nuevo || ultimoTrazo.map({ Date().timeIntervalSince($0) >= Self.trazoMinimo }) ?? true {
            enviarTrazo()
        } else {
            trazoNuevo = true
        }
    }

    private func enviarTrazo() {
        guard admiteTrazo, let periferico, let caracTrazo else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            trazoPendiente = true
            return
        }
        trazoPendiente = false
        let mensaje = MensajeTrazo(secuencia: secuenciaTrazo.siguiente(),
                                   puntos: trazoActivo ? puntosTrazo : [], giro: giroTrazo)
        let bytes = mensaje.codificar(maximo: periferico.maximumWriteValueLength(for: .withoutResponse))
        periferico.writeValue(Data(bytes), for: caracTrazo, type: .withoutResponse)
        ultimoTrazo = Date()
        trazoNuevo = false
        if !primerTrazoAnotado {
            primerTrazoAnotado = true
            // Sin los puntos: son la ruta que se sigue
            anotar("TRAZO enviado (seq \(mensaje.secuencia), \(bytes.count) bytes)")
        }
    }

    // MARK: - Envío

    private func enviarMovil() {
        leerBateria()
        // Solo si la placa anuncia MOVIL (§4)
        guard estado == .conectado, let periferico, let caracMovil,
              info?.capacidades.contains(.movil) == true else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            envioPendiente = true
            if !colaLlenaAnotada {
                colaLlenaAnotada = true
                anotar("Cola de envío llena: se espera a que iOS tenga hueco")
            }
            return
        }
        envioPendiente = false
        colaLlenaAnotada = false
        let mensaje = MensajeMovil(secuencia: secuencia.siguiente(), estado: bateria.estado, nivel: bateria.nivel)
        let datos = Data(mensaje.codificar())
        guard datos.count <= periferico.maximumWriteValueLength(for: .withoutResponse) else {
            anotar("MOVIL no cabe en el MTU actual")
            return
        }
        periferico.writeValue(datos, for: caracMovil, type: .withoutResponse)
        bateria = mensaje
        ultimaSecuencia = mensaje.secuencia
        ultimoMovil = Date()
        movilEnviado = mensaje
        movilPorConfirmar = mensaje.secuencia
        if !primerEnvioAnotado {
            primerEnvioAnotado = true
            anotar("MOVIL enviado (seq \(mensaje.secuencia): \(hex(mensaje.codificar())))")
        }
        let ahora = Date()
        enviados[mensaje.secuencia] = ahora
        enviados = enviados.filter { ahora.timeIntervalSince($0.value) < 10 }
    }

    private func listoParaEnviar() {
        if envioPendiente {
            enviarMovil()
        }
        if textoPendiente {
            enviarTexto()
        }
        if trazoPendiente {
            enviarTrazo()
        }
    }

    // MARK: - Ayudas

    /// Error 14 («Peer removed pairing information»): la placa ha borrado el
    /// vínculo y el iPhone lo conserva. Llega en el dominio de Core Bluetooth o
    /// en el de ATT, según el momento.
    private func esVinculoPerdido(_ error: Error?) -> Bool {
        guard let ns = error.map({ $0 as NSError }) else { return false }
        return ns.code == 14 && (ns.domain == CBErrorDomain || ns.domain == CBATTErrorDomain)
    }

    /// Mensajes para depurar, al registro del sistema (se ven con la app Consola
    /// del Mac). Hasta la 0.8.2 iban a una lista de la pestaña Placa, que el
    /// autor pidió quitar. No llevan datos personales (ni textos ni posiciones)
    private static let registro = Logger(subsystem: "io.github.luispr99.lprgauge", category: "BLE")

    private func anotar(_ texto: String) {
        Self.registro.info("\(texto, privacy: .public)")
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func version(_ partes: [UInt8]) -> String {
        partes.map { String($0) }.joined(separator: ".")
    }

    private func descripcion(_ estado: EstadoBateria) -> String {
        switch estado {
        case .desconocido: return "desconocido"
        case .sinCargar: return "sin cargar"
        case .cargando: return "cargando"
        case .cargada: return "cargada"
        }
    }

    private func estadoBluetooth(_ estadoCentral: CBManagerState) {
        switch estadoCentral {
        case .poweredOn:
            anotar("Bluetooth encendido")
            empezar()
        case .poweredOff:
            estado = .bluetoothApagado
            olvidarCaracteristicas()
            pararBusqueda()
            anotar("Bluetooth apagado")
        case .unauthorized:
            estado = .sinPermiso
            anotar("Sin permiso de Bluetooth")
        case .unsupported:
            estado = .noDisponible
        default:
            estado = .iniciando
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension EnlaceBLE: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let estadoCentral = central.state
        MainActor.assumeIsolated {
            self.estadoBluetooth(estadoCentral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let nombreAnunciado = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            self.encontrado(peripheral, nombreAnunciado: nombreAnunciado, rssi: rssi)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            self.conectado(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.perdido(peripheral, error: error, alConectar: true)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            self.perdido(peripheral, error: error, alConectar: false)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension EnlaceBLE: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            self.serviciosDescubiertos(peripheral, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // Llega cuando la placa indica Service Changed (PROTOCOLO.md §11)
        let invalidados = invalidatedServices.map { $0.uuid }
        MainActor.assumeIsolated {
            self.serviciosCambiados(peripheral, invalidados: invalidados)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            self.caracteristicasDescubiertas(peripheral, servicio: service, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let bytes = characteristic.value.map { [UInt8]($0) }
        MainActor.assumeIsolated {
            self.valorRecibido(characteristic, bytes: bytes, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let activas = characteristic.isNotifying
        let motivo = error?.localizedDescription
        MainActor.assumeIsolated {
            if let motivo {
                self.anotar("No se pudo activar STATUS: \(motivo)")
            } else {
                self.anotar("Avisos de STATUS: \(activas ? "activados" : "desactivados")")
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            self.listoParaEnviar()
        }
    }
}
