import CoreBluetooth
import Foundation
import UIKit
import LPRCore

/// Enlace BLE con el cuadro o con el firmware de referencia (docs/PROTOCOLO.md,
/// v0.2). Prueba del enlace: manda `MOVIL` (estado de la batería del iPhone) y
/// lee `STATUS`. De momento solo en primer plano: sin modo de fondo ni
/// restauración de estado.
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
    /// Registro en memoria para depurar sin Xcode (no sale del iPhone).
    @Published private(set) var registro: [String] = []

    private var central: CBCentralManager?
    private var periferico: CBPeripheral?
    private var caracInfo: CBCharacteristic?
    private var caracStatus: CBCharacteristic?
    private var caracMovil: CBCharacteristic?
    private var secuencia = Secuencia()
    /// Hora de envío de cada secuencia pendiente de eco, para la latencia.
    private var enviados: [UInt8: Date] = [:]
    /// El primer STATUS tras suscribirse puede traer el eco 0 de «aún no he
    /// recibido nada» (PROTOCOLO.md §9): no sirve para medir la latencia.
    private var ignorarLatencia = true
    private var envioPendiente = false
    private var reintentosLectura = 0
    private var inicioBusqueda: Date?
    private var pistaBusquedaDada = false
    private var mantenimiento: Timer?
    private var busqueda: Timer?

    private let uuidServicio = CBUUID(string: Protocolo.UUIDs.servicio)
    private let uuidInfo = CBUUID(string: Protocolo.UUIDs.deviceInfo)
    private let uuidStatus = CBUUID(string: Protocolo.UUIDs.status)
    private let uuidMovil = CBUUID(string: Protocolo.UUIDs.movil)

    private static let formatoHora: DateFormatter = {
        let formato = DateFormatter()
        formato.dateFormat = "HH:mm:ss"
        return formato
    }()

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
        enviarMovil()
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
        bateria = MensajeMovil(secuencia: bateria.secuencia, estado: estado, nivel: nivel)
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
        info = nil
        mantenimiento?.invalidate()
        mantenimiento = nil
        enviados.removeAll()
        envioPendiente = false
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
        periferico.discoverCharacteristics([uuidInfo, uuidStatus, uuidMovil], for: servicio)
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
            if let eco = status.ecoMovil {
                ultimoEco = eco
                if ignorarLatencia {
                    ignorarLatencia = false
                } else if let hora = enviados.removeValue(forKey: eco) {
                    latenciaMs = Int(Date().timeIntervalSince(hora) * 1000)
                }
            }
            if status.pideReenvio {
                enviarMovil()
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
        guard caracStatus != nil || caracMovil != nil else { return }
        if let caracStatus {
            ignorarLatencia = true
            periferico.setNotifyValue(true, for: caracStatus)
        }
        estado = .conectado
        guard info.capacidades.contains(.movil), caracMovil != nil else {
            anotar("La placa no admite MOVIL")
            return
        }
        enviarMovil()
        mantenimiento?.invalidate()
        mantenimiento = Timer.scheduledTimer(withTimeInterval: TimeInterval(Protocolo.mantenimientoSegundos),
                                             repeats: true) { [weak self] _ in
            guard let self else { return }
            // El temporizador va en el bucle principal: ya está en el actor principal
            MainActor.assumeIsolated {
                self.enviarMovil()
            }
        }
    }

    // MARK: - Envío

    private func enviarMovil() {
        leerBateria()
        guard estado == .conectado, let periferico, let caracMovil else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            envioPendiente = true
            return
        }
        envioPendiente = false
        let mensaje = MensajeMovil(secuencia: secuencia.siguiente(), estado: bateria.estado, nivel: bateria.nivel)
        let datos = Data(mensaje.codificar())
        guard datos.count <= periferico.maximumWriteValueLength(for: .withoutResponse) else {
            anotar("MOVIL no cabe en el MTU actual")
            return
        }
        periferico.writeValue(datos, for: caracMovil, type: .withoutResponse)
        bateria = mensaje
        ultimaSecuencia = mensaje.secuencia
        let ahora = Date()
        enviados[mensaje.secuencia] = ahora
        enviados = enviados.filter { ahora.timeIntervalSince($0.value) < 10 }
    }

    private func listoParaEnviar() {
        if envioPendiente {
            enviarMovil()
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

    private func anotar(_ texto: String) {
        registro.append("\(Self.formatoHora.string(from: Date()))  \(texto)")
        if registro.count > 100 {
            registro.removeFirst(registro.count - 100)
        }
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
        MainActor.assumeIsolated {
            // Llega cuando la placa indica Service Changed (PROTOCOLO.md §11)
            self.anotar("La placa ha cambiado sus servicios: se vuelven a buscar")
            self.olvidarCaracteristicas()
            self.estado = .preparando
            peripheral.discoverServices([self.uuidServicio])
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
