// Firmware de referencia del protocolo LPR (docs/PROTOCOLO.md, v0.2)
//
// SIN COMPILAR: se compila y se sube desde el IDE de Arduino, con el core
// esp32 3.3.8 y la placa ESP32-S3 (la del cuadro). No usar arduino-cli.
// Mientras está cargado, el cuadro no funciona; después hay que volver a
// cargar su sketch.
//
// Qué hace: es un periférico BLE con el servicio LPR. Recibe MOVIL (estado de
// la batería del iPhone), lo escribe por el monitor serie (115200 baudios) y
// contesta con STATUS (eco de la secuencia) por notificación. No usa la
// pantalla.
//
// Librería: la BLE del core (en el ESP32-S3 va sobre NimBLE), la misma que
// usa el cuadro (Movil_BLE.cpp), con LE Secure Connections Just Works y
// vínculo guardado en la NVS. Usa la dirección pública de la placa, la misma
// que el sketch del cuadro, así que conserva el emparejamiento que ya tenga
// el iPhone. Si el iPhone sigue viendo los servicios antiguos, ver la sección
// 11 del protocolo.
//
// Todos los callbacks corren en la tarea de NimBLE: solo copian datos y
// levantan avisos; el trabajo y la salida por serie se hacen en loop().

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "services/gatt/ble_svc_gatt.h"

// No cabe en el paquete de anuncio principal (solo quedan 5 bytes tras el UUID
// del servicio): la librería lo pasa entero a la respuesta de escaneo (§2)
#define NOMBRE               "LPR Gauge"
#define UUID_SERVICIO        "f4640001-813a-45b8-8ca8-f5f9e18c21d1"
#define UUID_DEVICE_INFO     "f4640002-813a-45b8-8ca8-f5f9e18c21d1"
#define UUID_STATUS          "f4640005-813a-45b8-8ca8-f5f9e18c21d1"
#define UUID_MOVIL           "f4640008-813a-45b8-8ca8-f5f9e18c21d1"

#define ANUNCIO_RAPIDO       32        // 20 ms, en unidades de 0,625 ms...
#define ANUNCIO_RAPIDO_MS    30000     // ...durante 30 s
#define ANUNCIO_LENTO        244       // y después 152,5 ms (como el cuadro)
#define REANUNCIO_MS         500       // tras desconectar, antes de volver a anunciarse
#define SEGURIDAD_MS         1000      // tras conectar, antes de pedir el cifrado
#define MANTENIMIENTO_MS     2000      // STATUS al menos cada 2 s (§9)
#define CADUCIDAD_MS         5000      // sin MOVIL durante 5 s: dato caducado (§10)
#define LATIDO_MS            10000     // sin conexión, una línea por serie cada 10 s

// DEVICE_INFO (§4): versión 1, tipo 2 (firmware de referencia), capacidades
// STATUS (bit 2) + MOVIL (bit 5) = 0x0024, sin límite de frecuencia,
// firmware 0.1.0. Es el vector de docs/vectores/mensajes.md.
static const uint8_t DEVICE_INFO[8] = { 1, 2, 0x24, 0x00, 0, 0, 1, 0 };

static BLEServer *         servidor  = NULL;
static BLECharacteristic * carStatus = NULL;

// ---- Estado de la conexión (lo tocan los callbacks de NimBLE)
static volatile uint16_t conexion           = BLE_HS_CONN_HANDLE_NONE;
static volatile bool     cifrado            = false;
static volatile bool     avisoConectado     = false;
static volatile bool     avisoDesconectado  = false;
static volatile bool     avisoCifrado       = false;
static volatile bool     avisoFalloCifrado  = false;
static volatile bool     avisoSuscripcion   = false;
static volatile bool     suscrito           = false;
static volatile uint32_t tConexion          = 0;
static volatile uint32_t tDesconexion       = 0;

// ---- Último MOVIL recibido (lo escribe onWrite y lo lee loop())
static portMUX_TYPE      muxMovil   = portMUX_INITIALIZER_UNLOCKED;
static uint8_t           movilBuf[20];
static volatile size_t   movilLen   = 0;
static volatile bool     movilNuevo = false;

// ---- Estado del protocolo (solo loop())
static uint8_t  ecoMovil       = 0;
static uint8_t  flagsStatus    = 0x01;   // bit 0: pide reenvío completo hasta recibir algo
static uint32_t tUltimoMovil   = 0;
static bool     caducado       = true;
static uint32_t tStatus        = 0;
static bool     seguridadPedida = false;
static bool     habiaVinculo   = false;   // al conectar, el iPhone ya estaba emparejado
static bool     reanuncioPendiente = false;
static bool     anuncioRapido  = false;
static uint32_t tAnuncio       = 0;
static uint32_t tLatido        = 0;

class ServidorCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer * s, ble_gap_conn_desc * desc) override {
        // Un solo móvil a la vez (§1): la segunda conexión se corta
        if (conexion != BLE_HS_CONN_HANDLE_NONE) {
            ble_gap_terminate(desc->conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            return;
        }
        conexion  = desc->conn_handle;
        cifrado   = desc->sec_state.encrypted;
        suscrito  = false;
        tConexion = millis();
        avisoConectado = true;
    }
    void onDisconnect(BLEServer * s, ble_gap_conn_desc * desc) override {
        if (desc->conn_handle != conexion) return;
        conexion = BLE_HS_CONN_HANDLE_NONE;
        cifrado  = false;
        suscrito = false;
        tDesconexion = millis();
        avisoDesconectado = true;
    }
};

// Llega al acabar un emparejamiento, bien o mal, y al cifrarse la conexión
// de un iPhone ya emparejado
class SeguridadCallbacks : public BLESecurityCallbacks {
    void onAuthenticationComplete(ble_gap_conn_desc * desc) override {
        if (desc == NULL || desc->conn_handle != conexion) return;
        if (!desc->sec_state.encrypted) {
            // Sin esto, la librería no deja volver a pedirlo hasta desconectar
            // (lo vio la revisión del sketch de prueba del cuadro)
            BLESecurity::resetSecurity();
            avisoFalloCifrado = true;
            return;
        }
        cifrado = true;
        avisoCifrado = true;
    }
};

class MovilCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic * c, ble_gap_conn_desc * desc) override {
        size_t n = c->getLength();
        if (n > sizeof(movilBuf)) n = sizeof(movilBuf);
        portENTER_CRITICAL(&muxMovil);
        memcpy(movilBuf, c->getData(), n);
        movilLen   = n;
        movilNuevo = true;
        portEXIT_CRITICAL(&muxMovil);
    }
};

class StatusCallbacks : public BLECharacteristicCallbacks {
    void onSubscribe(BLECharacteristic * c, ble_gap_conn_desc * desc, uint16_t subValue) override {
        suscrito = (subValue & 0x0001) != 0;
        avisoSuscripcion = true;
    }
};

void anunciarRapido() {
    BLEAdvertising * anuncio = BLEDevice::getAdvertising();
    anuncio->setMinInterval(ANUNCIO_RAPIDO);
    anuncio->setMaxInterval(ANUNCIO_RAPIDO);
    // start() en vez de BLEDevice::startAdvertising(), que descarta el resultado
    if (!anuncio->start()) Serial.println("[REF] ERROR: no arranca el anuncio");
    tAnuncio = millis();
    anuncioRapido = true;
}

void enviarStatus() {
    if (carStatus == NULL) return;
    // STATUS (§9): versión, eco NAV, eco GPS, flags, eco MOVIL
    uint8_t v[5] = { 1, 0, 0, flagsStatus, ecoMovil };
    carStatus->setValue(v, sizeof(v));
    // La librería solo notifica a quien esté suscrito y, como STATUS exige
    // cifrado, solo si el enlace está cifrado
    carStatus->notify();
    tStatus = millis();
}

void procesarMovil() {
    uint8_t m[20];
    size_t n;
    portENTER_CRITICAL(&muxMovil);
    n = movilLen;
    memcpy(m, movilBuf, n);
    movilNuevo = false;
    portEXIT_CRITICAL(&muxMovil);

    // Descarta lo corto, otra versión o un estado desconocido (§3 y §7)
    if (n < 4 || m[0] != 1 || m[2] > 3) {
        Serial.printf("[REF] MOVIL descartado (%u bytes, versión %u)\n", (unsigned)n, n > 0 ? m[0] : 0);
        return;
    }
    static const char * ESTADOS[4] = { "desconocido", "sin cargar", "cargando", "cargada" };
    if (m[3] == 255) {
        Serial.printf("[REF] MOVIL seq %u: batería %s, nivel desconocido\n", m[1], ESTADOS[m[2]]);
    } else {
        Serial.printf("[REF] MOVIL seq %u: batería %s, %u %%\n", m[1], ESTADOS[m[2]], m[3] > 100 ? 100 : m[3]);
    }
    ecoMovil = m[1];
    flagsStatus &= ~0x01;            // ya no hace falta pedir reenvío
    tUltimoMovil = millis();
    if (caducado) {
        caducado = false;
        Serial.println("[REF] Llegan datos del móvil");
    }
    enviarStatus();                  // eco inmediato, para medir la latencia (§9)
}

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println();
    Serial.println("[REF] Firmware de referencia LPR, protocolo v0.2");

    if (!BLEDevice::init(NOMBRE)) {
        Serial.println("[REF] ERROR: no arranca el Bluetooth");
        return;
    }
    // Just Works (la placa no tiene cómo mostrar ni teclear un código), con
    // vínculo guardado y LE Secure Connections. Después de init(), que pone
    // sus valores por defecto. Como en Movil_BLE.cpp del cuadro
    BLESecurity::setForceAuthentication(false);
    BLESecurity::setCapability(ESP_IO_CAP_NONE);
    BLESecurity::setAuthenticationMode(true, false, true);
    BLEDevice::setSecurityCallbacks(new SeguridadCallbacks());

    servidor = BLEDevice::createServer();
    servidor->setCallbacks(new ServidorCallbacks());

    BLEService * servicio = servidor->createService(UUID_SERVICIO);
    // DEVICE_INFO exige cifrado: así iOS cifra o empareja al leerla (§2)
    BLECharacteristic * info = servicio->createCharacteristic(
        UUID_DEVICE_INFO, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_READ_ENC);
    info->setValue((uint8_t *)DEVICE_INFO, sizeof(DEVICE_INFO));

    carStatus = servicio->createCharacteristic(
        UUID_STATUS, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_READ_ENC |
                     BLECharacteristic::PROPERTY_NOTIFY);
    uint8_t statusInicial[5] = { 1, 0, 0, flagsStatus, 0 };
    carStatus->setValue(statusInicial, sizeof(statusInicial));
    carStatus->setCallbacks(new StatusCallbacks());

    BLECharacteristic * movil = servicio->createCharacteristic(
        UUID_MOVIL, BLECharacteristic::PROPERTY_WRITE_NR | BLECharacteristic::PROPERTY_WRITE_ENC);
    movil->setCallbacks(new MovilCallbacks());
    servicio->start();

    // Anuncio (§2): flags 3 + potencia 3 + UUID 18 = 24 bytes en el paquete
    // principal; el nombre va en la respuesta de escaneo (setScanResponse)
    BLEAdvertising * anuncio = BLEDevice::getAdvertising();
    anuncio->addServiceUUID(UUID_SERVICIO);
    anuncio->setScanResponse(true);
    anuncio->addTxPower();
    anunciarRapido();
    Serial.println("[REF] Anunciándose. Esperando al iPhone...");
}

void loop() {
    // Las marcas de tiempo que se toman más tarde en esta misma vuelta pueden
    // ser posteriores a `ahora`: por eso todas las comparaciones son con signo,
    // (int32_t)(ahora - t), como en Movil_BLE.cpp del cuadro
    uint32_t ahora = millis();
    uint16_t c = conexion;

    if (avisoConectado) {
        avisoConectado = false;
        anuncioRapido = false;
        seguridadPedida = false;
        flagsStatus |= 0x01;          // conexión nueva: que la app mande todo
        // ¿Ya había vínculo con este iPhone? Se mira al conectar, antes de que
        // un emparejamiento nuevo lo cree (como en Movil_BLE.cpp del cuadro)
        habiaVinculo = false;
        struct ble_gap_conn_desc d;
        if (c != BLE_HS_CONN_HANDLE_NONE && ble_gap_conn_find(c, &d) == 0) {
            struct ble_store_key_sec k;
            struct ble_store_value_sec v;
            memset(&k, 0, sizeof(k));
            k.peer_addr = d.peer_id_addr;
            habiaVinculo = (ble_store_read_peer_sec(&k, &v) == 0);
        }
        Serial.printf("[REF] Conectado (handle %u, %s, %s)\n", c, cifrado ? "cifrado" : "sin cifrar",
                      habiaVinculo ? "ya emparejado" : "sin emparejar todavía");
    }
    if (avisoDesconectado) {
        avisoDesconectado = false;
        reanuncioPendiente = true;
        Serial.println("[REF] Desconectado");
    }
    if (avisoFalloCifrado) {
        avisoFalloCifrado = false;
        Serial.println("[REF] El cifrado ha fallado (¿emparejamiento rechazado en el iPhone?)");
    }
    if (avisoCifrado) {
        avisoCifrado = false;
        Serial.println("[REF] Enlace cifrado");
        if (habiaVinculo) {
            // Service Changed (§11): un iPhone ya emparejado puede recordar los
            // servicios de otro sketch (el del cuadro); que los vuelva a leer
            ble_svc_gatt_changed(0x0001, 0xFFFF);
            Serial.println("[REF] Aviso de servicios cambiados enviado al iPhone");
        } else {
            // Emparejamiento nuevo: el iPhone acaba de leer los servicios
            // actuales. Avisar ahora solo le haría repetir la búsqueda a mitad
            // de la preparación de la app (lo que pasó en la prueba del
            // 2026-10-08)
            Serial.println("[REF] Emparejamiento nuevo: no hace falta avisar de servicios cambiados");
        }
    }
    if (avisoSuscripcion) {
        avisoSuscripcion = false;
        Serial.printf("[REF] Suscripción a STATUS: %s\n", suscrito ? "sí" : "no");
        if (suscrito) enviarStatus();     // §9: STATUS al suscribirse
    }

    // Pedir el cifrado un poco después de conectar, si el iPhone no lo ha
    // hecho ya (con el vínculo guardado no sale ningún aviso en el iPhone)
    if (c != BLE_HS_CONN_HANDLE_NONE && !cifrado && !seguridadPedida &&
        (int32_t)(ahora - tConexion) >= (int32_t)SEGURIDAD_MS) {
        seguridadPedida = true;
        int rc = 0;
        if (!BLESecurity::startSecurity(c, &rc)) Serial.printf("[REF] ERROR al pedir el cifrado: %d\n", rc);
    }

    if (movilNuevo) procesarMovil();

    // STATUS de mantenimiento (§9)
    if (c != BLE_HS_CONN_HANDLE_NONE && cifrado && suscrito && (int32_t)(ahora - tStatus) >= (int32_t)MANTENIMIENTO_MS) {
        enviarStatus();
    }

    // Latido sin conexión: así se ve que el sketch está vivo aunque el monitor
    // serie se abra después del arranque y se pierdan las primeras líneas
    if (c == BLE_HS_CONN_HANDLE_NONE && (int32_t)(ahora - tLatido) >= (int32_t)LATIDO_MS) {
        tLatido = ahora;
        Serial.printf("[REF] Sin conexión; anunciándose como \"%s\" (%lu s desde el arranque)\n",
                      NOMBRE, (unsigned long)(ahora / 1000));
    }

    // Caducidad (§10)
    if (!caducado && (int32_t)(ahora - tUltimoMovil) > (int32_t)CADUCIDAD_MS) {
        caducado = true;
        Serial.println("[REF] Sin datos del móvil desde hace 5 s: dato caducado");
    }

    // Volver a anunciarse tras desconectar, y pasar al anuncio lento a los 30 s
    if (reanuncioPendiente && c == BLE_HS_CONN_HANDLE_NONE && (int32_t)(ahora - tDesconexion) >= (int32_t)REANUNCIO_MS) {
        reanuncioPendiente = false;
        anunciarRapido();
    }
    if (anuncioRapido && (int32_t)(ahora - tAnuncio) >= (int32_t)ANUNCIO_RAPIDO_MS) {
        anuncioRapido = false;
        BLEAdvertising * anuncio = BLEDevice::getAdvertising();
        if (anuncio->isAdvertising() && conexion == BLE_HS_CONN_HANDLE_NONE) {
            anuncio->stop();
            anuncio->setMinInterval(ANUNCIO_LENTO);
            anuncio->setMaxInterval(ANUNCIO_LENTO);
            if (!anuncio->start()) Serial.println("[REF] ERROR: no arranca el anuncio lento");
        }
    }

    delay(10);
}
