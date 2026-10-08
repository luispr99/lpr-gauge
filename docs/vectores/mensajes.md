# Vectores de prueba del protocolo

Ejemplos de mensajes con sus bytes exactos, en hexadecimal y en el orden en que
viajan. Salen de [PROTOCOLO.md](../PROTOCOLO.md) (v0.2). Las pruebas de `Core`
(`Core/Tests/LPRCoreTests/MensajesTests.swift`) comprueban estos mismos bytes; el
firmware y la app de Android deberán pasar los mismos. Si cambia un vector,
cambian a la vez el documento, las pruebas y este fichero.

## `MOVIL`

| Caso | Secuencia | Estado | Nivel | Bytes |
|---|---|---|---|---|
| Cargando al 85 % | 7 | 2 cargando | 85 | `01 07 02 55` |
| Sin cargar al 100 % | 0 | 1 sin cargar | 100 | `01 00 01 64` |
| Cargada (enchufada y llena) | 42 | 3 cargada | 100 | `01 2A 03 64` |
| Todo desconocido | 255 | 0 desconocido | desconocido | `01 FF 00 FF` |

- Un nivel por encima de 100 se envía como 100.
- Al decodificar, se descartan `01 07 02` (corto), `02 07 02 55` (versión
  desconocida) y un estado mayor que 3. Un nivel por encima de 100 que no sea 255
  se lee como 100.

## `STATUS`

| Caso | Bytes | Eco `NAV` | Eco `GPS` | Pide reenvío | Eco `MOVIL` |
|---|---|---|---|---|---|
| v0.2, recién arrancado | `01 00 00 01 00` | 0 | 0 | sí | 0 |
| v0.2, tras recibir `MOVIL` 7 | `01 00 00 00 07` | 0 | 0 | no | 7 |
| v0.1 (4 bytes) | `01 03 04 00` | 3 | 4 | no | sin dato |
| v0.2 con un byte de más | `01 00 00 00 07 99` | 0 | 0 | no | 7 |

- Se descarta `01 00 00` (corto) y cualquier mensaje con versión distinta de 1.

## `DEVICE_INFO`

| Caso | Bytes | Tipo | Capacidades | Frecuencia | Firmware |
|---|---|---|---|---|---|
| Firmware de referencia 0.1.0 | `01 02 24 00 00 00 01 00` | 2 | `STATUS` + `MOVIL` (0x0024) | sin límite | 0.1.0 |

- Se descarta cualquier mensaje de menos de 8 bytes.
