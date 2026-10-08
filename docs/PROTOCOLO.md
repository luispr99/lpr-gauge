# Protocolo BLE móvil → cuadro

> **Estado: borrador v0.1 (2026-10-08), sin validar.** Los puntos marcados
> **[A DECIDIR]** esperan una decisión del autor. Mientras sea borrador, nada de
> lo que hay aquí es definitivo y puede cambiar sin mantener compatibilidad.

Este documento es la única fuente de verdad del protocolo, también para el
firmware del cuadro. El código sigue al documento, no al revés.

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
| `DEVICE_INFO` | `f4640002-813a-45b8-8ca8-f5f9e18c21d1` | lectura | ninguna | ≥ 8 B |
| `NAV` | `f4640003-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |
| `GPS` | `f4640004-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |
| `STATUS` | `f4640005-813a-45b8-8ca8-f5f9e18c21d1` | notificación | cifrado | ≤ 20 B |
| `NAV_TEXT` | `f4640006-813a-45b8-8ca8-f5f9e18c21d1` | reservado | — | — |
| `CONFIG` | `f4640007-813a-45b8-8ca8-f5f9e18c21d1` | reservado | — | — |

- **Anuncio:** el UUID del servicio va en el **paquete principal**, no en la
  respuesta de escaneo. iOS, en segundo plano, solo encuentra periféricos
  buscando por UUID de servicio. En el cuadro, este UUID sustituye al de prueba
  (`e136cd1e-…`), porque el paquete principal ya ocupa sus 31 bytes:
  flags 3 + potencia 3 + UUID 18 + nombre «CL500» 7.
- **Cifrado:** LE Secure Connections *Just Works*, con el vínculo guardado. El
  cuadro ya lo usa para ANCS, AMS y CTS en la misma conexión. Escribir en una
  característica que exige cifrado hace que iOS pida el emparejamiento si aún no
  lo hay.
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
| 2-3 | capacidades | u16 | Bit 0 `NAV`, bit 1 `GPS`, bit 2 `STATUS`, bit 3 `NAV_TEXT`, bit 4 `CONFIG`. |
| 4 | frecuencia máxima | u8 | Mensajes por segundo y característica que acepta (0 = sin límite). |
| 5-7 | versión de firmware | u8 × 3 | Mayor, menor, parche. |

## 5. `NAV` (escritura sin respuesta): siguiente maniobra

| Byte | Campo | Tipo | Desconocido | Descripción |
|---|---|---|---|---|
| 0 | versión | u8 | — | 1 |
| 1 | secuencia | u8 | — | |
| 2 | flags | u8 | — | Bit 0 ruta activa · bit 1 recalculando · bit 2 fuera de ruta · bit 3 llegada. |
| 3 | maniobra | u8 | 0 | Código de flecha (sección 7). |
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
- **[A DECIDIR]** Origen de la altitud: GPS o barómetro del móvil.

## 7. Códigos de maniobra

**[PENDIENTE]** La tabla será un superconjunto de los 31 códigos (0-30) del
protocolo *Komoot BLE Connect*, para reutilizar iconos y proyectos ESP32
públicos. Se rellenará cuando esté verificada esa especificación. Los códigos
propios empezarán en el 31.

## 8. `STATUS` (notificación)

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | eco `NAV` | u8 | Última secuencia de `NAV` recibida. |
| 2 | eco `GPS` | u8 | Última secuencia de `GPS` recibida. |
| 3 | flags | u8 | Bit 0 pide reenvío completo (por ejemplo, tras reiniciarse). |

- El dispositivo notifica `STATUS` al suscribirse la app, después de cada
  escritura recibida y, como mínimo, cada 2 s.
- **Latencia:** el eco permite a la app medir la latencia de ida y vuelta.
- **Reconexión:** según un ingeniero de Apple en el foro de desarrolladores
  (junio de 2026, no es documentación), la restauración de estado de Core
  Bluetooth la despierta la comunicación del accesorio. Las notificaciones
  periódicas sirven también para eso. **Sin probar.**

## 9. Ritmo y caducidad

- La app **no supone un ritmo fijo de GPS**: Apple no publica ni garantiza una
  frecuencia.
- La app manda `NAV` y `GPS` en cada cambio y, como mínimo, cada 2 s
  (mantenimiento), aunque no cambie nada.
- El cuadro da por **caducado** un dato si pasa más de **T** segundos sin
  recibir su característica. Entonces muestra el aviso de «sin GPS» o de «sin
  datos». **[A DECIDIR]** el valor de T; propuesta: 5 s.
- **Edad del fix:** el GPS puede estar caducado aunque los mensajes lleguen.
- **Al conectar,** la app lee `DEVICE_INFO`, se suscribe a `STATUS` y manda el
  estado completo sin esperar a ningún cambio.

## 10. Pendiente

- Tabla de maniobras (sección 7).
- Parámetros de conexión que pida el cuadro. En el planteamiento inicial:
  intervalo de 30-60 ms, latencia 4 y *timeout* de 4 s, a medir con el eco de
  `STATUS`.
- `NAV_TEXT` (nombre de calle) y `CONFIG` (unidades…), cuando se pidan.
