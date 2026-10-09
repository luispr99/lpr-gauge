# Vectores de prueba del protocolo

Ejemplos de mensajes con sus bytes exactos, en hexadecimal y en el orden en que
viajan. Salen de [PROTOCOLO.md](../PROTOCOLO.md) (v0.3). Las pruebas de `Core`
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

| Caso | Bytes | Eco `NAV` | Eco `GPS` | Pide reenvío | Eco `MOVIL` | Eco `NAV_TEXT` |
|---|---|---|---|---|---|---|
| v0.2, recién arrancado | `01 00 00 01 00` | 0 | 0 | sí | 0 | sin dato |
| v0.2, tras recibir `MOVIL` 7 | `01 00 00 00 07` | 0 | 0 | no | 7 | sin dato |
| v0.1 (4 bytes) | `01 03 04 00` | 3 | 4 | no | sin dato | sin dato |
| v0.3 (6 bytes) | `01 00 00 00 07 99` | 0 | 0 | no | 7 | 153 |
| v0.3 con un byte de más | `01 00 00 00 07 05 99` | 0 | 0 | no | 7 | 5 |

- Se descarta `01 00 00` (corto) y cualquier mensaje con versión distinta de 1.

## `NAV_TEXT`

| Caso | Secuencia | Texto | Bytes |
|---|---|---|---|
| Texto corto | 3 | «Hola» | `01 03 48 6F 6C 61` |
| Sin texto | 0 | (vacío) | `01 00` |
| Dos líneas | 1 | «350 m», salto, «Gira» | `01 01 33 35 30 20 6D 0A 47 69 72 61` |
| Con eñe y tilde | 9 | «Calle Peñón» | `01 09 43 61 6C 6C 65 20 50 65 C3 B1 C3 B3 6E` |
| Cortado a 6 bytes | 0 | «aññ» → «añ» | `01 00 61 C3 B1` |

- Al cortar no se parte un carácter UTF-8. El máximo es 182 bytes, o lo que
  admita la conexión si es menos.
- Al decodificar, se descartan `01` (corto), `02 00 41` (versión desconocida) y
  `01 00 C3` (UTF-8 no válido).

## `DEVICE_INFO`

| Caso | Bytes | Tipo | Capacidades | Frecuencia | Firmware |
|---|---|---|---|---|---|
| Firmware de referencia 0.1.0 | `01 02 24 00 00 00 01 00` | 2 | `STATUS` + `MOVIL` (0x0024) | sin límite | 0.1.0 |
| Cuadro, primera integración LPR | `01 01 2C 00 00 00 01 00` | 1 | `STATUS` + `NAV_TEXT` + `MOVIL` (0x002C) | sin límite | 0.1.0 |

- Se descarta cualquier mensaje de menos de 8 bytes.
