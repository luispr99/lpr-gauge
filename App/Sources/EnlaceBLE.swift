import CoreBluetooth
import CoreLocation
import Foundation
import os
import UIKit
import LPRCore

/// Enlace BLE con el cuadro o con el firmware de referencia (docs/PROTOCOLO.md,
/// v0.11). Manda `MOVIL` (estado de la batería del iPhone; con el cuadro, solo al
/// cambiar), `NAV_TEXT` (texto de la navegación), `NAV` (siguiente maniobra;
/// desde la v0.10, el resumen del viaje, y desde la v0.11, el «y luego»),
/// `TRAZO` (tramo de ruta por delante; con una placa que lo admite, con
/// movimiento, v0.9) y, tras cada `TRAZO`, `CRUCES` (calles
/// que salen del tramo), y lee `STATUS`. En segundo plano sigue con el modo
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
    /// Si se está mandando la siguiente maniobra (NAV), y el último eco de la
    /// placa.
    @Published private(set) var navActivo = false
    @Published private(set) var ecoNav: UInt8?
    /// El último eco de CRUCES de la placa (van con cada TRAZO).
    @Published private(set) var ecoCruces: UInt8?
    /// El último eco de GPS de la placa (v0.7).
    @Published private(set) var ecoGPS: UInt8?

    private var central: CBCentralManager?
    private var periferico: CBPeripheral?
    private var caracInfo: CBCharacteristic?
    private var caracStatus: CBCharacteristic?
    private var caracMovil: CBCharacteristic?
    private var caracTexto: CBCharacteristic?
    private var caracTrazo: CBCharacteristic?
    private var caracNav: CBCharacteristic?
    private var caracCruces: CBCharacteristic?
    private var caracGPS: CBCharacteristic?
    private var caracRutas: CBCharacteristic?
    private var secuencia = Secuencia()
    /// Cada característica lleva su secuencia (PROTOCOLO.md §3).
    private var secuenciaTexto = Secuencia()
    private var secuenciaTrazo = Secuencia()
    private var secuenciaNav = Secuencia()
    private var secuenciaCruces = Secuencia()
    private var secuenciaGPS = Secuencia()
    private var secuenciaRutas = Secuencia()
    private var textoPendiente = false
    private var rutasPendiente = false
    /// Las rutas que enseña el cuadro (v0.13, §7 quinquies) y el estado de su
    /// orden; las listas mandadas, por su secuencia, para saber cuál tocó.
    private var rutasCuadro: [RutaGuardada] = []
    private var estadoOrden = EstadoOrdenRuta.ninguna
    private var ecoOrden: UInt8 = 0
    /// La ruta calculada para confirmar en el cuadro (estado 4, v0.14).
    private var propuestaCuadro: PropuestaRuta?
    private var listasMandadas: [UInt8: [RutaGuardada]] = [:]
    /// El contador de la última orden atendida (STATUS, byte 8).
    private var ultimaOrden: UInt8 = 0
    /// Lo llama con cada orden de ruta nueva del cuadro y la ruta a la que se
    /// refiere (nil si su lista ya no se conoce).
    var alRecibirOrden: (@MainActor (OrdenRuta, RutaGuardada?) -> Void)?
    /// Lo llama al perder la conexión con la placa (0.21.0).
    var alDesconectar: (@MainActor () -> Void)?
    private var trazoPendiente = false
    private var navPendiente = false
    private var crucesPendiente = false
    private var gpsPendiente = false
    private var primerTextoAnotado = false
    private var primerTrazoAnotado = false
    private var primerNavAnotado = false
    private var primerCrucesAnotado = false
    private var primerGPSAnotado = false
    /// Cuándo se mandó por última vez cada característica: el mantenimiento
    /// (§10) repite cada una cuando le toca, no todas a la vez, para que no
    /// salgan en ráfagas (lo vio la revisión de la 0.9.0).
    private var ultimoMovil: Date?
    private var ultimoTexto: Date?
    private var ultimoTrazo: Date?
    private var ultimoNav: Date?
    private var ultimoGPS: Date?
    /// La última posición del GPS (ponerPosicion) y si es más nueva que la
    /// última mandada. La edad se calcula al mandar: así, si dejan de llegar
    /// posiciones (un túnel), el mantenimiento la manda cada vez más vieja y
    /// el cuadro lo ve.
    private var posicionGPS: CLLocation?
    private var gpsNuevo = false
    /// Hay un tramo más nuevo que el último mandado (llegó antes de 1 s).
    private var trazoNuevo = false
    /// Hay una maniobra (NAV) distinta de la última mandada (llegó antes de 1 s).
    private var navNuevo = false
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
    private let uuidNav = CBUUID(string: Protocolo.UUIDs.nav)
    private let uuidCruces = CBUUID(string: Protocolo.UUIDs.cruces)
    private let uuidGPS = CBUUID(string: Protocolo.UUIDs.gps)
    private let uuidRutas = CBUUID(string: Protocolo.UUIDs.rutas)

    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(bateriaCambiada),
                                               name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(bateriaCambiada),
                                               name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        leerBateria()
        // Con restauración de estado (0.19.0): si iOS cierra la app para
        // liberar memoria, la vuelve a abrir en segundo plano cuando la placa
        // escribe o avisa (no si se cierra a mano desde el selector de apps)
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "lpr-gauge-central"])
    }

    /// Una línea en el registro de la pestaña «Placa» desde otra parte de la
    /// app (la navegación, con las órdenes del cuadro).
    func anotarDesdeFuera(_ texto: String) {
        anotar(texto)
        // Y a la vista, en «Placa» (0.21.2): el registro del sistema solo se
        // lee desde un Mac. Las 20 últimas, con la hora; sin posiciones
        let hora = Date().formatted(date: .omitted, time: .standard)
        eventosUbicacion.insert("\(hora) · \(texto)", at: 0)
        if eventosUbicacion.count > 20 { eventosUbicacion.removeLast() }
        if texto.hasPrefix("Permiso de ubicación: ") {
            permisoUbicacion = String(texto.dropFirst("Permiso de ubicación: ".count))
        }
    }

    /// Lo último que ha pasado con el GPS y las órdenes del cuadro, de lo más
    /// reciente a lo más antiguo, y el permiso de ubicación (para «Placa»).
    @Published private(set) var eventosUbicacion: [String] = []
    @Published private(set) var permisoUbicacion: String?

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
        if !alConectar {
            alDesconectar?()
        }
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
        caracNav = nil
        caracCruces = nil
        caracGPS = nil
        caracRutas = nil
        rutasPendiente = false
        estadoOrden = .ninguna
        ecoOrden = 0
        propuestaCuadro = nil
        listasMandadas.removeAll()
        ultimaOrden = 0
        info = nil
        mantenimiento?.invalidate()
        mantenimiento = nil
        ultimoMovil = nil
        ultimoTexto = nil
        ultimoTrazo = nil
        ultimoNav = nil
        ultimoGPS = nil
        gpsNuevo = false
        trazoNuevo = false
        navNuevo = false
        crucesDelTrazo = nil
        movilEnviado = nil
        movilPorConfirmar = nil
        ultimoReenvioPedido = nil
        enviados.removeAll()
        envioPendiente = false
        textoPendiente = false
        trazoPendiente = false
        navPendiente = false
        crucesPendiente = false
        gpsPendiente = false
        primerTextoAnotado = false
        primerTrazoAnotado = false
        primerNavAnotado = false
        primerCrucesAnotado = false
        primerGPSAnotado = false
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
        periferico.discoverCharacteristics([uuidInfo, uuidStatus, uuidMovil, uuidTexto, uuidTrazo, uuidNav, uuidCruces,
                                            uuidGPS, uuidRutas],
                                           for: servicio)
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
            case uuidNav: caracNav = caracteristica
            case uuidCruces: caracCruces = caracteristica
            case uuidGPS: caracGPS = caracteristica
            case uuidRutas: caracRutas = caracteristica
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
            if let eco = status.ecoCruces {
                ecoCruces = eco
            }
            // Orden de ruta (v0.13): cada contador nuevo, una vez
            if admiteRutas, let orden = status.orden, orden.contador != 0, orden.contador != ultimaOrden {
                ultimaOrden = orden.contador
                let lista = listasMandadas[orden.lista]
                let ruta = lista.flatMap { Int(orden.ruta) < $0.count ? $0[Int(orden.ruta)] : nil }
                let que = orden.codigo == .cancelar ? "cancelar" : orden.codigo == .empezar ? "empezar"
                    : orden.codigo == .terminar ? "terminar" : "calcular"
                anotarDesdeFuera("Orden de ruta del cuadro: \(que) la \(Int(orden.ruta) + 1)ª")
                alRecibirOrden?(orden, ruta)
            }
            // El eco de NAV va siempre (byte 1); solo vale si la placa lo admite.
            // El de GPS, igual (byte 2)
            if admiteNav {
                ecoNav = status.ecoNav
            }
            if admiteGPS {
                ecoGPS = status.ecoGPS
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
        guard caracStatus != nil || caracMovil != nil || caracTexto != nil || caracTrazo != nil || caracNav != nil
                || caracGPS != nil
        else { return }
        if let caracStatus {
            ignorarLatencia = true
            periferico.setNotifyValue(true, for: caracStatus)
        }
        estado = .conectado
        let conMovil = info.capacidades.contains(.movil) && caracMovil != nil
        let conTexto = info.capacidades.contains(.navText) && caracTexto != nil
        let conTrazo = admiteTrazo
        let conNav = admiteNav
        let conGPS = admiteGPS
        if !conMovil {
            anotar("La placa no admite MOVIL")
        }
        if !conTexto {
            anotar("La placa no admite NAV_TEXT (texto de navegación)")
        }
        if !conTrazo {
            anotar("La placa no admite TRAZO (tramo de ruta)")
        } else if !admiteCruces {
            anotar("La placa no admite CRUCES (calles del tramo)")
        } else if !admiteAnillos {
            anotar("La placa no dibuja los anillos de las rotondas (CRUCES v0.8)")
        }
        if conTrazo && !admiteMovimiento {
            anotar("La placa no mueve el tramo ella sola (TRAZO v0.9): formato de siempre")
        }
        if !conNav {
            anotar("La placa no admite NAV (siguiente maniobra)")
        }
        if !conGPS {
            anotar("La placa no admite GPS")
        }
        guard conMovil || conTexto || conTrazo || conNav || conGPS else { return }
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
        // Al conectar, el estado completo sin esperar a ningún cambio (§10).
        // Cuenta como el reenvío pedido: el STATUS de la suscripción llega con
        // «pide reenvío» antes de que la placa procese esto, y si no se
        // mandaría todo dos veces (lo vio la revisión de la 0.9.1)
        ultimoReenvioPedido = Date()
        mantener(todo: true)
        if conMovil && !movilAlCambiar {
            anotar("La placa no admite MOVIL al cambiar: se repite cada 2 s")
        }
    }

    /// Lo que toca mandar ahora (§10), sin repetir lo que acaba de salir:
    /// - MOVIL, si ha cambiado la batería, si su eco no ha llegado en 2 s y, con
    ///   una placa sin «MOVIL al cambiar» (v0.5), cada 1,5-2 s;
    /// - el texto, la maniobra y el tramo, mientras los haya, cada 1,5-2 s; una
    ///   maniobra o un tramo más nuevos que los mandados, en cuanto pase 1 s
    ///   desde el anterior (§5 y §7 ter). CRUCES sale con cada TRAZO.
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
        if navActivo, todo || pasado(ultimoNav, Self.repeticion) || (navNuevo && pasado(ultimoNav, Self.cambioMinimo)) {
            enviarNav()
        }
        if trazoActivo, todo || pasado(ultimoTrazo, Self.repeticion) || (trazoNuevo && pasado(ultimoTrazo, Self.cambioMinimo)) {
            enviarTrazo()
        }
        // GPS (§6, v0.7): mientras haya alguna posición, como el tramo
        if posicionGPS != nil, todo || pasado(ultimoGPS, Self.repeticion) || (gpsNuevo && pasado(ultimoGPS, Self.cambioMinimo)) {
            enviarGPS()
        }
        // RUTAS (v0.13): al conectar y con el reenvío; si no, al cambiar
        if todo {
            enviarRutas()
        }
    }

    // MARK: - Rutas del cuadro (PROTOCOLO.md §7 quinquies, v0.13)

    /// Si la placa enseña las rutas con sus opciones y confirma la propuesta
    /// (bit 13, v0.14; con solo el bit 12, de la v0.13, no se manda RUTAS).
    var admiteRutas: Bool {
        estado == .conectado && caracRutas != nil && caracStatus != nil
            && info?.capacidades.contains(.rutasConfirmar) == true
    }

    /// Las rutas que enseña el cuadro (HistorialRutas.paraElCuadro).
    func ponerRutas(_ rutas: [RutaGuardada]) {
        rutasCuadro = Array(rutas.prefix(MensajeRutas.maximoRutas))
        enviarRutas()
    }

    /// En qué está la orden `eco` del cuadro (Navegacion).
    func ponerEstadoOrden(_ estado: EstadoOrdenRuta, eco: UInt8, propuesta: PropuestaRuta? = nil) {
        estadoOrden = estado
        ecoOrden = eco
        propuestaCuadro = estado == .propuesta ? propuesta : nil
        enviarRutas()
    }

    private func enviarRutas() {
        guard admiteRutas, let periferico, let caracRutas else { return }
        guard periferico.canSendWriteWithoutResponse else {
            rutasPendiente = true
            return
        }
        rutasPendiente = false
        let numero = secuenciaRutas.siguiente()
        let mensaje = MensajeRutas(secuencia: numero, estado: estadoOrden, ecoOrden: ecoOrden,
                                   rutas: rutasCuadro.map(RutaCuadro.init), propuesta: propuestaCuadro)
        let bytes = mensaje.codificar(maximo: periferico.maximumWriteValueLength(for: .withoutResponse))
        // Las de esta secuencia, para la orden; solo las últimas, que son las
        // que puede estar enseñando el cuadro
        listasMandadas[numero] = Array(rutasCuadro.prefix(Int(bytes[4])))
        if listasMandadas.count > 16 {
            listasMandadas = listasMandadas.filter { UInt8(truncatingIfNeeded: numero &- $0.key) < 16 }
        }
        periferico.writeValue(Data(bytes), for: caracRutas, type: .withoutResponse)
    }

    // MARK: - GPS (PROTOCOLO.md §6, v0.7)

    /// Si la placa conectada admite GPS: el indicador de calidad del cuadro.
    var admiteGPS: Bool {
        estado == .conectado && caracGPS != nil && info?.capacidades.contains(.gps) == true
    }

    /// Cada posición del GPS (la pone Navegacion, también con la simulación:
    /// el indicador es del GPS de verdad). Sale como mucho una por segundo;
    /// las de entre medias, con la siguiente.
    func ponerPosicion(_ posicion: CLLocation) {
        posicionGPS = posicion
        if ultimoGPS.map({ Date().timeIntervalSince($0) >= Self.cambioMinimo }) ?? true {
            enviarGPS()
        } else {
            gpsNuevo = true
        }
    }

    private func enviarGPS() {
        guard admiteGPS, let periferico, let caracGPS, let posicion = posicionGPS else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            gpsPendiente = true
            return
        }
        gpsPendiente = false
        // Lo que iOS da como negativo es «sin dato» (CLLocation)
        let mensaje = MensajeGPS(
            secuencia: secuenciaGPS.siguiente(),
            edad: max(0, Date().timeIntervalSince(posicion.timestamp)),
            altitud: posicion.verticalAccuracy > 0 ? posicion.altitude : nil,
            precisionVertical: posicion.verticalAccuracy > 0 ? posicion.verticalAccuracy : nil,
            velocidad: posicion.speed >= 0 ? posicion.speed : nil,
            rumbo: posicion.course >= 0 ? posicion.course : nil,
            precisionHorizontal: posicion.horizontalAccuracy >= 0 ? posicion.horizontalAccuracy : nil,
            enSegundoPlano: UIApplication.shared.applicationState != .active
        )
        let bytes = mensaje.codificar()
        guard bytes.count <= periferico.maximumWriteValueLength(for: .withoutResponse) else {
            anotar("GPS no cabe en el MTU actual")
            return
        }
        periferico.writeValue(Data(bytes), for: caracGPS, type: .withoutResponse)
        ultimoGPS = Date()
        gpsNuevo = false
        if !primerGPSAnotado {
            primerGPSAnotado = true
            // Sin la posición: no se manda (§6) ni se escribe
            anotar("GPS enviado (seq \(mensaje.secuencia), \(bytes.count) bytes)")
        }
    }

    /// La placa da MOVIL por bueno mientras dure la conexión (v0.5): se manda
    /// solo al cambiar (a petición del autor, 2026-10-09).
    private var movilAlCambiar: Bool {
        info?.capacidades.contains(.movilAlCambiar) == true
    }

    /// Cada cuánto se mira qué mandar; lo que se repite, a los 1,5 s (con el
    /// tic, cada 1,5-2 s: el mínimo de 2 s de §10 y lejos de los 5 de la
    /// caducidad); un tramo o una maniobra nuevos, como mucho uno por segundo
    /// (§5 y §7 ter); MOVIL sin eco, a los 2 s; y el reenvío que pide la placa,
    /// como mucho cada 0,5 s.
    private static let tic: TimeInterval = 0.5
    private static let repeticion: TimeInterval = 1.5
    private static let cambioMinimo: TimeInterval = 1
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

    // MARK: - Siguiente maniobra (NAV, PROTOCOLO.md §5)

    /// La última maniobra puesta por Navegacion (la secuencia la pone el enlace
    /// al mandarla).
    private var navActual = MensajeNav(secuencia: 0, banderas: [])

    /// Si la placa conectada admite NAV.
    var admiteNav: Bool {
        estado == .conectado && caracNav != nil && info?.capacidades.contains(.nav) == true
    }

    /// Siguiente maniobra (la pone Navegacion en cada posición); nil o sin
    /// «ruta activa», no hay ruta. Como TRAZO (§5, v0.6): se manda al
    /// cambiar, como mucho una vez por segundo (lo que llegue antes queda
    /// guardado y sale en cuanto pase el segundo, con mantener), y se repite
    /// mientras haya ruta; al dejar de haberla, una vez con el bit 0 a cero
    /// (con el de llegada, si lo trae).
    func ponerNav(_ nav: MensajeNav?) {
        guard var nav, nav.banderas.contains(.rutaActiva) else {
            guard navActivo else { return }
            navActivo = false
            navNuevo = false
            navActual = nav ?? MensajeNav(secuencia: 0, banderas: [])
            navActual.secuencia = 0
            enviarNav()
            return
        }
        nav.secuencia = 0
        let nuevo = !navActivo
        // Cambio, solo si cambian los bytes: los Double (distancias, tiempo)
        // cambian en décimas con cada posición aunque se manden igual (lo vio
        // la revisión de la 0.10.0). Sin el resumen del viaje (v0.10): el
        // tiempo de viaje cambia cada segundo y NAV saldría siempre una vez
        // por segundo; va con la repetición (y, al llegar, con el cambio de
        // banderas). Por eso se guarda aunque no cambie nada más. El «y luego»
        // (v0.11) sí cuenta: solo cambia al cambiar de paso
        let cambia = nuevo || nav.codificarSinResumen() != navActual.codificarSinResumen()
        navActual = nav
        guard cambia else { return }
        if nuevo { navActivo = true }
        if nuevo || ultimoNav.map({ Date().timeIntervalSince($0) >= Self.cambioMinimo }) ?? true {
            enviarNav()
        } else {
            navNuevo = true
        }
    }

    private func enviarNav() {
        guard admiteNav, let periferico, let caracNav else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            navPendiente = true
            return
        }
        navPendiente = false
        var mensaje = navActual
        mensaje.secuencia = secuenciaNav.siguiente()
        // Con los carriles (v0.12), si la placa los admite, de 32 a 48 bytes;
        // sin ellos, con el «y luego» (v0.11), 31; si la conexión no los
        // admite, los 25 de la v0.10 o los 17 de la v0.6 (§2)
        let maximo = periferico.maximumWriteValueLength(for: .withoutResponse)
        let bytes = mensaje.codificar(maximo: admiteCarriles ? maximo : min(maximo, MensajeNav.longitudConLuego))
        guard bytes.count <= maximo else {
            anotar("NAV no cabe en el MTU actual")
            return
        }
        periferico.writeValue(Data(bytes), for: caracNav, type: .withoutResponse)
        ultimoNav = Date()
        navNuevo = false
        if !primerNavAnotado {
            primerNavAnotado = true
            // Sin el contenido, como el resto
            anotar("NAV enviado (seq \(mensaje.secuencia), \(bytes.count) bytes)")
        }
    }

    // MARK: - Tramo de ruta (TRAZO, PROTOCOLO.md §7 ter) y cruces (CRUCES, §7 quater)

    private var puntosTrazo: [PuntoPlano] = []
    private var giroTrazo: Int?
    /// Nivel de escala (v0.6): 0 la ajusta la placa; 1-3, 250, 500 y 1000 m.
    private var escalaTrazo: UInt8 = 0
    /// Con movimiento (v0.9): cuántos de `puntosTrazo` van por detrás de la
    /// moto y los metros de ruta desde su inicio hasta la moto; nil, el
    /// formato de siempre.
    private var atrasTrazo = 0
    private var recorridoTrazo: Double?
    /// Calles de los cruces del último tramo puesto, en sus mismos ejes.
    private var callesTrazo: [CalleCruce] = []
    /// Anillos de las rotondas del último tramo puesto (v0.8), en sus mismos
    /// ejes.
    private var anillosTrazo: [AnilloCruce] = []
    /// Las calles y los anillos del último TRAZO mandado y su secuencia:
    /// CRUCES sale justo después con ella. Se guardan aparte porque, si iOS no
    /// tiene hueco, CRUCES sale más tarde y entretanto puede llegar otro tramo.
    private var crucesDelTrazo: (trazo: UInt8, calles: [CalleCruce], anillos: [AnilloCruce])?

    /// Si la placa conectada admite TRAZO: si no, no hace falta calcularlo.
    var admiteTrazo: Bool {
        estado == .conectado && caracTrazo != nil && info?.capacidades.contains(.trazo) == true
    }

    /// Si la placa conectada admite CRUCES (siempre con TRAZO): si no, no hace
    /// falta buscarlos.
    var admiteCruces: Bool {
        admiteTrazo && caracCruces != nil && info?.capacidades.contains(.cruces) == true
    }

    /// Si la placa conectada dibuja los anillos de las rotondas (bit 9, v0.8;
    /// siempre con CRUCES): si no, no se mandan y las calles van sin quitar
    /// las del anillo.
    var admiteAnillos: Bool {
        admiteCruces && info?.capacidades.contains(.anillos) == true
    }

    /// Si la placa conectada acepta NAV con los carriles y los dibuja (bit 11,
    /// v0.12): si no, NAV va sin ellos.
    var admiteCarriles: Bool {
        admiteNav && info?.capacidades.contains(.carriles) == true
    }

    /// Si la placa conectada acepta TRAZO con movimiento (bit 10, v0.9; siempre
    /// con TRAZO): mueve el dibujo ella sola entre mensajes. Si no, el formato
    /// de siempre.
    var admiteMovimiento: Bool {
        admiteTrazo && info?.capacidades.contains(.movimiento) == true
    }

    /// Cuántos puntos caben en un TRAZO con la conexión actual (como mucho, 44;
    /// con movimiento, 42, con los de detrás incluidos).
    var puntosTrazoQueCaben: Int {
        guard let periferico, estado == .conectado else { return MensajeTrazo.maximoPuntos }
        return MensajeTrazo.puntosQueCaben(periferico.maximumWriteValueLength(for: .withoutResponse),
                                           movimiento: admiteMovimiento)
    }

    /// Cuántas calles caben en un CRUCES con la conexión actual (como mucho,
    /// 35) si lleva esos anillos detrás (v0.8: los anillos van primero; con
    /// 0, sin bloque de anillos).
    func callesCrucesQueCaben(anillos: Int) -> Int {
        guard let periferico, estado == .conectado else {
            return MensajeCruces.callesQueCaben(MensajeCruces.longitudMaxima, anillos: anillos)
        }
        return MensajeCruces.callesQueCaben(periferico.maximumWriteValueLength(for: .withoutResponse), anillos: anillos)
    }

    /// Tramo de ruta por delante (lo pone Navegacion en cada posición), en los
    /// ejes de la moto, con su nivel de escala, las calles de sus cruces y los
    /// anillos de sus rotondas (solo se mandan si la placa los admite); nil
    /// sin tramo. Se manda al cambiar, como mucho una vez por segundo: lo que
    /// llegue antes queda guardado y sale en cuanto pase el segundo (mantener,
    /// cada 0,5 s); al dejar de haberlo, una vez sin tramo para borrarlo.
    /// Con movimiento (v0.9): `atras`, cuántos puntos van por detrás de la
    /// moto (los primeros de `puntos`), y `recorrido`, los metros de ruta desde
    /// su inicio hasta la moto. Solo se manda así si la placa lo admite
    /// (admiteMovimiento); si no, o sin recorrido, el formato de siempre, sin
    /// los de detrás.
    func ponerTrazo(_ tramo: (puntos: [PuntoPlano], giro: Int?)?, escala: UInt8 = 0, calles: [CalleCruce] = [],
                    anillos: [AnilloCruce] = [], atras: Int = 0, recorrido: Double? = nil) {
        guard let tramo, tramo.puntos.count >= 2 else {
            guard trazoActivo else { return }
            trazoActivo = false
            trazoNuevo = false
            puntosTrazo = []
            giroTrazo = nil
            escalaTrazo = 0
            atrasTrazo = 0
            recorridoTrazo = nil
            callesTrazo = []
            anillosTrazo = []
            enviarTrazo()
            return
        }
        let nuevo = !trazoActivo
        puntosTrazo = tramo.puntos
        giroTrazo = tramo.giro
        escalaTrazo = escala
        atrasTrazo = min(max(0, atras), tramo.puntos.count - 1)
        recorridoTrazo = recorrido
        callesTrazo = calles
        anillosTrazo = anillos
        if nuevo { trazoActivo = true }
        if nuevo || ultimoTrazo.map({ Date().timeIntervalSince($0) >= Self.cambioMinimo }) ?? true {
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
        // Con movimiento (v0.9), si la placa lo admite y hay recorrido. Si no,
        // el formato de siempre, que empieza en la moto: sin los de detrás (por
        // si el tramo se calculó con otra placa conectada)
        let conMovimiento = trazoActivo && admiteMovimiento && recorridoTrazo != nil
        var puntos = trazoActivo ? puntosTrazo : []
        var giro = giroTrazo
        if trazoActivo && !conMovimiento && atrasTrazo > 0 {
            let atras = atrasTrazo
            puntos = Array(puntos.dropFirst(atras))
            giro = giro.flatMap { g -> Int? in g >= atras ? g - atras : nil }
        }
        let mensaje = MensajeTrazo(secuencia: secuenciaTrazo.siguiente(), puntos: puntos, giro: giro,
                                   escala: escalaTrazo, movimiento: conMovimiento,
                                   recorrido: recorridoTrazo ?? 0, atras: conMovimiento ? atrasTrazo : 0)
        let bytes = mensaje.codificar(maximo: periferico.maximumWriteValueLength(for: .withoutResponse))
        periferico.writeValue(Data(bytes), for: caracTrazo, type: .withoutResponse)
        ultimoTrazo = Date()
        trazoNuevo = false
        if !primerTrazoAnotado {
            primerTrazoAnotado = true
            // Sin los puntos ni el recorrido: son la ruta que se sigue
            anotar("TRAZO enviado (seq \(mensaje.secuencia), \(bytes.count) bytes\(conMovimiento ? ", con movimiento" : ""))")
        }
        // Justo después, sus cruces, con su secuencia (§7 quater). Sin tramo no
        // hacen falta: la placa no dibuja los de otro tramo
        if trazoActivo && admiteCruces {
            // Los anillos, solo si la placa anuncia el bit 9 (v0.8)
            crucesDelTrazo = (trazo: mensaje.secuencia, calles: callesTrazo,
                              anillos: admiteAnillos ? anillosTrazo : [])
            enviarCruces()
        } else {
            crucesDelTrazo = nil
            crucesPendiente = false
        }
    }

    private func enviarCruces() {
        guard admiteCruces, let periferico, let caracCruces, let crucesDelTrazo else { return }
        guard periferico.canSendWriteWithoutResponse else {
            // Se manda en cuanto iOS avise de que hay hueco (peripheralIsReady)
            crucesPendiente = true
            return
        }
        crucesPendiente = false
        self.crucesDelTrazo = nil
        let mensaje = MensajeCruces(secuencia: secuenciaCruces.siguiente(), trazo: crucesDelTrazo.trazo,
                                    calles: crucesDelTrazo.calles, anillos: crucesDelTrazo.anillos)
        let bytes = mensaje.codificar(maximo: periferico.maximumWriteValueLength(for: .withoutResponse))
        periferico.writeValue(Data(bytes), for: caracCruces, type: .withoutResponse)
        if !primerCrucesAnotado {
            primerCrucesAnotado = true
            // Sin las posiciones: solo cuántas calles y cuántos anillos
            let calles = Int(bytes[3])
            let anillos = bytes.count > 4 + 5 * calles ? Int(bytes[4 + 5 * calles]) : 0
            anotar("CRUCES enviado (seq \(mensaje.secuencia), \(calles) calles, \(anillos) anillos, \(bytes.count) bytes)")
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
        if navPendiente {
            enviarNav()
        }
        // Los cruces que esperaban van antes que un tramo nuevo: son del que
        // ya tiene la placa
        if gpsPendiente {
            enviarGPS()
        }
        if crucesPendiente {
            enviarCruces()
        }
        if trazoPendiente {
            enviarTrazo()
        }
        if rutasPendiente {
            enviarRutas()
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
    /// iOS ha vuelto a abrir la app por la placa (restauración de estado): se
    /// queda con el periférico; al encenderse el Bluetooth, empezar() lo
    /// encuentra conectado y lo prepara como siempre.
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let perifericos = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        MainActor.assumeIsolated {
            if let restaurado = perifericos.first {
                self.periferico = restaurado
                restaurado.delegate = self
                self.anotarDesdeFuera("iOS ha vuelto a abrir la app por la placa (restauración de Bluetooth)")
            }
        }
    }

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
