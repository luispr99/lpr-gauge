# Vectores de prueba del protocolo

Ejemplos de mensajes con sus bytes exactos, en hexadecimal y en el orden en que
viajan. Salen de [PROTOCOLO.md](../PROTOCOLO.md) (v0.6). Las pruebas de `Core`
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

| Caso | Bytes | Eco `NAV` | Eco `GPS` | Pide reenvío | Eco `MOVIL` | Eco `NAV_TEXT` | Eco `TRAZO` | Eco `CRUCES` |
|---|---|---|---|---|---|---|---|---|
| v0.2, recién arrancado | `01 00 00 01 00` | 0 | 0 | sí | 0 | sin dato | sin dato | sin dato |
| v0.2, tras recibir `MOVIL` 7 | `01 00 00 00 07` | 0 | 0 | no | 7 | sin dato | sin dato | sin dato |
| v0.1 (4 bytes) | `01 03 04 00` | 3 | 4 | no | sin dato | sin dato | sin dato | sin dato |
| v0.3 (6 bytes) | `01 00 00 00 07 99` | 0 | 0 | no | 7 | 153 | sin dato | sin dato |
| v0.4 (7 bytes) | `01 00 00 00 07 05 99` | 0 | 0 | no | 7 | 5 | 153 | sin dato |
| v0.6 (8 bytes) | `01 00 00 00 07 05 03 99` | 0 | 0 | no | 7 | 5 | 3 | 153 |
| v0.6 con un byte de más | `01 04 00 00 07 05 03 02 99` | 4 | 0 | no | 7 | 5 | 3 | 2 |

- Se descarta `01 00 00` (corto) y cualquier mensaje con versión distinta de 1.
- Hasta la v0.6, el caso de 8 bytes era «v0.4 con un byte de más» y el último
  byte se ignoraba; ahora es el eco de `CRUCES`.

## `NAV`

Siempre 17 bytes desde la v0.6: versión, secuencia, flags, maniobra,
modificador, distancia (`u16`), ángulo (`i16`), distancia restante en decenas
de metros, tiempo restante en minutos, hora de llegada en minutos desde la
medianoche y longitud del paso (todos `u16`).

| Caso | Bytes |
|---|---|
| Sin ruta, secuencia 0 (todo desconocido) | `01 00 00 00 00 FF FF FF 7F FF FF FF FF FF FF FF FF` |
| Secuencia 16, ruta activa, giro (2) a la derecha (90) a 350 m; quedan 12 340 m (1234 decenas) y 15 min; llegada a las 18:45 (1125); paso de 800 m | `01 10 01 02 00 5E 01 5A 00 D2 04 0F 00 65 04 20 03` |
| Secuencia 17, rotonda (3), tercera salida, a la izquierda (−90) a 120,4 m; 5004 m (500 decenas), 389 s (6 min), llegada a las 0:00, paso desconocido | `01 11 01 03 03 78 00 A6 FF F4 01 06 00 00 00 FF FF` |
| Secuencia 32, al llegar: sin ruta activa, bit de llegada y código 5 | `01 20 08 05 00 FF FF FF 7F FF FF FF FF FF FF FF FF` |
| Saturado: recto a 70 000 m, ángulo 200, 1 000 000 m, 10 000 000 s, llegada 1440, paso −5 m | `01 00 01 01 00 FE FF B4 00 FE FF FE FF FF FF 00 00` |

- Flags: ruta activa `01`, más recalculando `03`, más fuera de ruta `05`;
  llegada `08`.
- Las distancias y el tiempo se redondean y se saturan en 65 534 (`FE FF`); el
  ángulo, en ±180 (−400 va como −180, `4C FF`); una hora de llegada fuera de
  0-1439, o lo que no es finito, va como desconocido.
- Al decodificar: con 9 a 16 bytes, los campos de la v0.6 son desconocidos
  (`01 05 01 01 00 64 00 00 00`: recto a 100 m, ángulo 0); un código de
  maniobra que no está en la tabla (por ejemplo, 9) se lee como 0; se
  descartan `01 05 01 01 00 64 00 00` (corto) y la versión 2.
- Ángulo de las rotondas a partir de los grados recorridos dentro, circulando
  por la derecha: 90 → 90, 180 → 0, 270 → −90, 360 → −180, 0 → 180, 450 → 90;
  por la izquierda, 90 → −90 y 270 → 90.

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

## `TRAZO`

| Caso | Bytes |
|---|---|
| Sin tramo, secuencia 5 | `01 05 00 FF` |
| Secuencia 2, giro en el punto 1: (0, 0), (0, 100) y (−30, 150) | `01 02 01 01 00 00 00 00 00 00 64 00 E2 FF 96 00` |
| El mismo con escala 3 (1000 m) | `01 02 07 01 00 00 00 00 00 00 64 00 E2 FF 96 00` |

- Coordenadas en metros redondeados, `i16` *little-endian*; se saturan en
  ±32 767 (por ejemplo, (40 000, −40 000) va como `FF 7F 01 80`).
- Como mucho 44 puntos (180 bytes). Con 20 bytes por escritura caben 4; un giro
  que quede fuera va como 255.
- Escala en los bits 1-2 de los flags (v0.6): con tramo, 1 (250 m) da `03`, 2
  (500 m) `05` y 3 (1000 m) `07`; una escala mayor que 3 va como 3. Sin tramo
  los flags van a `00`, sin escala.
- Al decodificar, se descartan `01 05 00` (corto) y la versión 2. Con el bit 0
  a cero o menos de dos puntos, no hay tramo ni escala (`01 05 04 FF`: escala
  0). `01 02 05 01 00 00 00 00 00 00 64 00` es el tramo (0, 0), (0, 100) con el
  giro en el punto 1 y escala 2.

## `CRUCES`

| Caso | Bytes |
|---|---|
| Sin calles, secuencia 0, del `TRAZO` 0 | `01 00 00 00` |
| Secuencia 3, del `TRAZO` 7: dos calles en (0, 120), a la derecha (64) y a la izquierda (192), y una en (−15,4; 300,6) hacia atrás a la izquierda (200) | `01 03 07 03 00 00 78 00 40 00 00 78 00 C0 F1 FF 2D 01 C8` |

- Coordenadas como en `TRAZO` (se redondean y se saturan igual); la dirección,
  en 1/256 de vuelta.
- Como mucho 35 calles (179 bytes). Con 20 bytes por escritura caben 3; se
  recorta por el final, así que se quedan las de los cruces más cercanos.
- Al decodificar, se leen como mucho `n` calles y solo las que llegan enteras
  (`01 00 05 02 00 00 0A 00 40 01`: una calle, (0, 10) a la derecha); lo que
  sobra se ignora. Se descartan `01 03 07` (corto) y la versión 2.

## `DEVICE_INFO`

| Caso | Bytes | Tipo | Capacidades | Frecuencia | Firmware |
|---|---|---|---|---|---|
| Firmware de referencia 0.1.0 | `01 02 24 00 00 00 01 00` | 2 | `STATUS` + `MOVIL` (0x0024) | sin límite | 0.1.0 |
| Cuadro, primera integración LPR | `01 01 2C 00 00 00 01 00` | 1 | `STATUS` + `NAV_TEXT` + `MOVIL` (0x002C) | sin límite | 0.1.0 |
| Cuadro con el trazo y MOVIL al cambiar | `01 01 EC 00 00 00 02 00` | 1 | `STATUS` + `NAV_TEXT` + `MOVIL` + `TRAZO` + MOVIL al cambiar (0x00EC) | sin límite | 0.2.0 |
| Cuadro con `NAV` y `CRUCES` (ejemplo) | `01 01 ED 01 00 00 03 00` | 1 | `NAV` + `STATUS` + `NAV_TEXT` + `MOVIL` + `TRAZO` + MOVIL al cambiar + `CRUCES` (0x01ED) | sin límite | 0.3.0 |

- Se descarta cualquier mensaje de menos de 8 bytes.
