# Protocolo BLE móvil → cuadro

> **Estado: borrador v0.2 (2026-10-08), sin validar.** Los puntos marcados
> **[PENDIENTE]** faltan por completar. Mientras sea borrador, nada de lo que hay
> aquí es definitivo y puede cambiar sin mantener compatibilidad. Los cambios de
> cada versión están en la [sección 13](#13-cambios).

Este documento es la única fuente de verdad del protocolo, también para el
firmware del cuadro. El código sigue al documento, no al revés. Los ejemplos de
mensajes con sus bytes están en [vectores/mensajes.md](vectores/mensajes.md).

## 1. Papeles

- **El móvil es el central** BLE y **cada dispositivo (el cuadro) es un
  periférico** con un servidor GATT.
- La app escribe los datos en el periférico y el periférico le avisa de su estado
  por notificaciones.
- La app debe admitir varios periféricos a la vez (diseño para 2-4). A todos les
  manda los mismos mensajes con el mismo número de secuencia.
- El cuadro solo atiende a un móvil a la vez: la segunda conexión la corta.

## 2. Servicio y características

Todos los UUID comparten la base `f464xxxx-813a-45b8-8ca8-f5f9e18c21d1`
(aleatoria, generada el 2026-10-08).

| Nombre | UUID | Propiedades | Seguridad | Tamaño |
|---|---|---|---|---|
| Servicio `LPR` | `f4640001-813a-45b8-8ca8-f5f9e18c21d1` | — | — | — |
| `DEVICE_INFO` | `f4640002-813a-45b8-8ca8-f5f9e18c21d1` | lectura | cifrado | ≥ 8 B |
| `NAV` | `f4640003-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |
| `GPS` | `f4640004-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |
| `STATUS` | `f4640005-813a-45b8-8ca8-f5f9e18c21d1` | lectura y notificación | cifrado | ≤ 20 B |
| `NAV_TEXT` | `f4640006-813a-45b8-8ca8-f5f9e18c21d1` | reservado | — | — |
| `CONFIG` | `f4640007-813a-45b8-8ca8-f5f9e18c21d1` | reservado | — | — |
| `MOVIL` | `f4640008-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |

- **Anuncio:** el UUID del servicio va en el **paquete principal**, no en la
  respuesta de escaneo. iOS, en segundo plano, solo encuentra periféricos
  buscando por UUID de servicio. En el cuadro, este UUID sustituye al de prueba
  (`e136cd1e-…`), porque el paquete principal ya ocupa sus 31 bytes:
  flags 3 + potencia 3 + UUID 18 + nombre «CL500» 7.
- **Nombre:** la app no lo usa para encontrar el dispositivo, así que puede ir en
  la respuesta de escaneo. Tras el UUID solo quedan 5 bytes para el nombre en el
  paquete principal. Con un nombre más largo, como «LPR Gauge» en el firmware de
  referencia, la librería BLE del core 3.3.8 lo pasa entero a la respuesta de
  escaneo (`BLEAdvertising.cpp`).
- **Cifrado:** LE Secure Connections *Just Works*, con el vínculo guardado. El
  cuadro ya lo usa para ANCS, AMS y CTS en la misma conexión.
- **`DEVICE_INFO` también exige cifrado.** Es la primera petición con respuesta
  de la app. Si el enlace no está cifrado, el dispositivo la rechaza, e iOS cifra
  o empareja y la repite sola. Las escrituras sin respuesta no tienen respuesta,
  así que un rechazo no avisaría a iOS de que tiene que cifrar.
- **Mensajes de 20 bytes como máximo:** caben con el MTU mínimo (23). Aun así, la
  app consulta `maximumWriteValueLength(for:)` en tiempo de ejecución.

## 3. Reglas comunes de codificación

- **Enteros en *little-endian*.** Sin coma flotante.
- **Primer byte de cada mensaje: versión del formato.** Esta es la versión 1.
  - Los campos nuevos se añaden siempre **al final**, sin cambiar la versión.
  - El receptor lee los campos que conoce e **ignora los bytes que sobran**.
  - Si el mensaje es más corto que su longitud mínima o trae una versión que no
    conoce, el receptor **lo descarta entero**.
  - Un cambio incompatible sube la versión.
- **Valor «desconocido»:** cada campo tiene uno (ver tablas). Nunca se envía
  basura en un campo sin dato.
- **Secuencia:** `u8` independiente por característica. Se incrementa en cada
  escritura, reenvíos de mantenimiento incluidos, y da la vuelta de 255 a 0.

## 4. `DEVICE_INFO` (lectura)

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | Versión del protocolo del dispositivo: 1. |
| 1 | tipo | u8 | 1 = cuadro de moto; 2 = firmware de referencia (solo serie). |
| 2-3 | capacidades | u16 | Bit 0 `NAV`, bit 1 `GPS`, bit 2 `STATUS`, bit 3 `NAV_TEXT`, bit 4 `CONFIG`, bit 5 `MOVIL`. |
| 4 | frecuencia máxima | u8 | Mensajes por segundo y característica que acepta (0 = sin límite). |
| 5-7 | versión de firmware | u8 × 3 | Mayor, menor, parche. |

- Longitud mínima: 8 bytes.
- La app solo escribe en las características cuya capacidad anuncia el
  dispositivo.

## 5. `NAV` (escritura sin respuesta): siguiente maniobra

| Byte | Campo | Tipo | Desconocido | Descripción |
|---|---|---|---|---|
| 0 | versión | u8 | — | 1 |
| 1 | secuencia | u8 | — | |
| 2 | flags | u8 | — | Bit 0 ruta activa · bit 1 recalculando · bit 2 fuera de ruta · bit 3 llegada. |
| 3 | maniobra | u8 | 0 | Código de flecha (sección 8). |
| 4 | modificador | u8 | 0 | En rotondas, número de salida (1-n). |
| 5-6 | distancia | u16 | `0xFFFF` | Metros hasta la maniobra; satura en 65 534. |
| 7-8 | ángulo | i16 | `0x7FFF` | Ángulo de giro en grados, de -180 a 180, positivo a la derecha. |

- Longitud mínima: 9 bytes.
- Sin ruta activa, la app manda `NAV` con el bit 0 a cero y el cuadro deja de
  mostrar la flecha.
- El **ángulo** permite dibujar la flecha aunque el código sea genérico. Lo
  calcula la app a partir de la geometría de la ruta.
- El **cuadro decide cómo mostrar la distancia** (por ejemplo, «200 m» o
  «1,2 km»). La app manda siempre metros.

## 6. `GPS` (escritura sin respuesta): altitud y estado del GPS

| Byte | Campo | Tipo | Desconocido | Descripción |
|---|---|---|---|---|
| 0 | versión | u8 | — | 1 |
| 1 | secuencia | u8 | — | |
| 2 | flags | u8 | — | Bit 0 fix válido · bit 1 altitud válida · bit 2 velocidad válida · bit 3 rumbo válido · bit 4 app en segundo plano. |
| 3 | edad del fix | u8 | 255 | En décimas de segundo; satura en 254. |
| 4-5 | altitud | i16 | `0x8000` | Metros sobre el nivel del mar. |
| 6 | precisión vertical | u8 | 255 | Metros; satura en 254. |
| 7-8 | velocidad | u16 | `0xFFFF` | Centésimas de m/s. |
| 9-10 | rumbo | u16 | `0xFFFF` | Centésimas de grado desde el norte verdadero, en sentido horario. |
| 11 | precisión horizontal | u8 | 255 | Metros; satura en 254. |

- Longitud mínima: 12 bytes.
- **Velocidad y rumbo** no se muestran por ahora. Van porque la app ya los tiene
  y dejan sitio a ideas pendientes del cuadro, como el indicador de marcha. Sus
  unidades imitan la característica estándar *Location and Speed* (0x2A67).
- **Origen de la altitud** (decidido el 2026-10-08): barómetro del móvil
  combinado con el GPS si el sistema lo ofrece; si no, GPS. El campo es el mismo
  en los dos casos. La precisión vertical es la que dé esa fuente.

## 7. `MOVIL` (escritura sin respuesta): estado del móvil

| Byte | Campo | Tipo | Desconocido | Descripción |
|---|---|---|---|---|
| 0 | versión | u8 | — | 1 |
| 1 | secuencia | u8 | — | |
| 2 | estado de la batería | u8 | 0 | 0 desconocido · 1 sin cargar · 2 cargando · 3 cargada (enchufada y llena). |
| 3 | nivel de batería | u8 | 255 | Porcentaje, de 0 a 100. |

- Longitud mínima: 4 bytes.
- Añadido en la v0.2 (2026-10-08), como primera prueba del enlace con la placa.
- El cuadro ya lee el nivel de batería del iPhone por el servicio estándar
  0x180F. Aquí el nivel va también para los dispositivos que no lo lean, como el
  firmware de referencia.

## 8. Códigos de maniobra

**[PENDIENTE]** Ferrostar entrega cada maniobra como tipo y modificador al estilo
OSRM (ver `DECISIONES.md`, «Maniobras: lo comprobado»). La tabla se definirá a
partir de ellos. Queda por decidir si sigue siendo un superconjunto de los
códigos 0-30 de *Komoot BLE Connect*, como se planteó al principio.

## 9. `STATUS` (lectura y notificación)

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | eco `NAV` | u8 | Última secuencia de `NAV` recibida. |
| 2 | eco `GPS` | u8 | Última secuencia de `GPS` recibida. |
| 3 | flags | u8 | Bit 0 pide reenvío completo (por ejemplo, tras reiniciarse). |
| 4 | eco `MOVIL` | u8 | Última secuencia de `MOVIL` recibida (añadido en la v0.2). |

- Longitud mínima: 4 bytes. Un `STATUS` de 4 bytes viene de un dispositivo
  anterior a la v0.2 y no trae eco de `MOVIL`.
- Mientras no ha recibido nada de una característica, su eco vale 0.
- El dispositivo notifica `STATUS` al suscribirse la app, después de cada
  escritura recibida y, como mínimo, cada 2 s.
- **Latencia:** el eco permite a la app medir la latencia de ida y vuelta.
- **Reconexión:** según un ingeniero de Apple en el foro de desarrolladores
  (junio de 2026, no es documentación), la restauración de estado de Core
  Bluetooth la despierta la comunicación del accesorio. Las notificaciones
  periódicas sirven también para eso. **Sin probar.**

## 10. Ritmo y caducidad

- La app **no supone un ritmo fijo de GPS**: Apple no publica ni garantiza una
  frecuencia.
- La app manda `NAV`, `GPS` y `MOVIL` en cada cambio y, como mínimo, cada 2 s
  (mantenimiento), aunque no cambie nada.
- El cuadro da por **caducado** un dato si pasan más de **5 s** sin recibir su
  característica (decidido el 2026-10-08). Entonces muestra el mismo aviso que
  sin GPS.
- **Edad del fix:** el GPS puede estar caducado aunque los mensajes lleguen.
- **Al conectar,** la app lee `DEVICE_INFO`, se suscribe a `STATUS` y manda el
  estado completo sin esperar a ningún cambio.

## 11. Servicios que cambian: *Service Changed*

- iOS guarda en caché los servicios GATT de los dispositivos con los que está
  emparejado. Si el firmware cambia sus servicios (por ejemplo, al pasar del
  sketch del cuadro al de referencia, o al añadir este servicio al cuadro), el
  iPhone puede seguir viendo los antiguos.
- El dispositivo debe **indicar *Service Changed*** (característica 0x2A05 del
  servicio 0x1801) en cuanto el enlace con un móvil emparejado quede cifrado. Con
  NimBLE se hace con `ble_svc_gatt_changed(0x0001, 0xFFFF)`. Sin probar.
- La app vuelve a descubrir los servicios cuando iOS le avisa de que han cambiado
  (`peripheral(_:didModifyServices:)`).
- Si aun así no aparecen, se borra el emparejamiento en el iPhone (Ajustes >
  Bluetooth > el dispositivo > Omitir este dispositivo). La librería BLE del core
  3.3.8 acepta el emparejamiento nuevo y borra el vínculo antiguo
  (`BLEServer.cpp`, evento `BLE_GAP_EVENT_REPEAT_PAIRING`).

## 12. Pendiente

- Tabla de maniobras (sección 8).
- Parámetros de conexión que pida el cuadro. En el planteamiento inicial:
  intervalo de 30-60 ms, latencia 4 y *timeout* de 4 s, a medir con el eco de
  `STATUS`.
- `NAV_TEXT` (nombre de calle) y `CONFIG` (unidades…), cuando se pidan.

## 13. Cambios

- **v0.2 (2026-10-08):** característica `MOVIL` (estado de la batería del móvil),
  bit 5 de capacidades, eco de `MOVIL` en el byte 4 de `STATUS`, `STATUS` también
  legible, `DEVICE_INFO` cifrada y sección 11 (*Service Changed*). La versión del
  formato de los mensajes sigue siendo 1: todo se añade al final.
- **v0.1 (2026-10-08):** primer borrador.
