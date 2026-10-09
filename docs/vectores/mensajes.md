# Vectores de prueba del protocolo

Ejemplos de mensajes con sus bytes exactos, en hexadecimal y en el orden en que
viajan. Salen de [PROTOCOLO.md](../PROTOCOLO.md) (v0.13). Las pruebas de `Core`
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
- v0.13, con la orden de ruta (12 bytes): `01 10 00 00 03 04 05 06 05 01 09 02`
  es eco de `NAV` 16, de `MOVIL` 3, de `NAV_TEXT` 4, de `TRAZO` 5 y de `CRUCES`
  6, y la orden 5: empezar (1) la ruta 2 (la tercera) del `RUTAS` 9. Con menos
  de 12 bytes, sin orden; un código que no se conoce (por ejemplo, 7), sin
  código.

## `RUTAS` (v0.13)

Cabecera: versión, secuencia, estado de la orden, eco de la orden y número de
rutas. Por ruta: tipo, distancia (decenas de metros), tiempo (minutos),
curvas, peaje y autopista (decenas de metros), largo del nombre y nombre.

| Caso | Bytes |
|---|---|
| Secuencia 7, calculando (1), eco 3, dos rutas; la primera: de curvas (1), 58 km (5800 = `A8 16`), 65 min, 112 curvas, sin peaje, 12,34 km de autopista (1234 = `D2 04`), «Puerto» | `01 07 01 03 02 01 A8 16 41 00 70 00 00 00 D2 04 06 50 75 65 72 74 6F` y la segunda |
| Una ruta sin datos, «X» | `01 02 00 00 01 00 FF FF FF FF FF FF FF FF FF FF 01 58` |

- Los nombres, como mucho de 40 bytes, se cortan sin partir un carácter, todos
  al mismo largo, lo justo para caber en lo que admita la conexión; si sin
  nombre tampoco caben, van menos rutas.
- Se descarta un mensaje corto, de otra versión, con más de tres rutas, con una
  ruta cortada o con un nombre que no es UTF-8.

## `NAV`

31 bytes desde la v0.11: versión, secuencia, flags, maniobra, modificador,
distancia (`u16`), ángulo (`i16`), distancia restante en decenas de metros,
tiempo restante en minutos, hora de llegada en minutos desde la medianoche y
longitud del paso (todos `u16`); el resumen del viaje: tiempo de viaje en
segundos y distancia recorrida en metros (los dos `u32`, v0.10); y el «y
luego» (v0.11): maniobra y modificador (`u8`), ángulo (`i16`) y distancia
entre la siguiente maniobra y esa (`u16`). Si la conexión no admite 31
bytes, la app manda los 25 primeros, y si tampoco admite 25, los 17 primeros
(sección 2 del protocolo). `FF FF FF FF FF FF FF FF` en los bytes 17-24: el
resumen desconocido; `00 00 FF 7F FF FF` al final: sin maniobra luego.

Con los carriles (v0.12, solo si la placa tiene el bit 11 de capacidades):
32 + 2n bytes. Tras los 31, el número de carriles (0 a 8) y, por carril de
izquierda a derecha, sus flechas; después, por carril, las que valen (0 si
no vale). Bits: 0 recto, 1 ligera a la derecha, 2 derecha, 3 fuerte a la
derecha, 4 cambio de sentido, 5 ligera a la izquierda, 6 izquierda, 7 fuerte
a la izquierda.

| Caso | Bytes |
|---|---|
| Sin ruta, secuencia 0 (todo desconocido) | `01 00 00 00 00 FF FF FF 7F FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF 00 00 FF 7F FF FF` |
| Secuencia 16, ruta activa, giro (2) a la derecha (90) a 350 m; quedan 12 340 m (1234 decenas) y 15 min; llegada a las 18:45 (1125); paso de 800 m; resumen desconocido | `01 10 01 02 00 5E 01 5A 00 D2 04 0F 00 65 04 20 03 FF FF FF FF FF FF FF FF 00 00 FF 7F FF FF` |
| Secuencia 17, rotonda (3), tercera salida, a la izquierda (−90) a 120,4 m; 5004 m (500 decenas), 389 s (6 min), llegada a las 0:00, paso desconocido; resumen desconocido | `01 11 01 03 03 78 00 A6 FF F4 01 06 00 00 00 FF FF FF FF FF FF FF FF FF FF 00 00 FF 7F FF FF` |
| Secuencia 32, al llegar: sin ruta activa, bit de llegada y código 5 | `01 20 08 05 00 FF FF FF 7F FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF 00 00 FF 7F FF FF` |
| Secuencia 33, al llegar (v0.10): ruta activa y llegada (`09`), código 5, distancia 0; 1 h 23 min 45 s de viaje (5025 s) y 123 456 m recorridos (media: 88,4 km/h) | `01 21 09 05 00 00 00 FF 7F FF FF FF FF FF FF FF FF A1 13 00 00 40 E2 01 00 00 00 FF 7F FF FF` |
| Secuencia 18, ruta activa, giro (2) a la derecha (90) a 80 m; quedan 2000 m (200 decenas) y 4 min; llegada a las 10:00 (600); paso de 300 m; 754 s de viaje y 9000 m recorridos; y luego (v0.11): rotonda (3), segunda salida, ángulo −45, a 120 m de la siguiente | `01 12 01 02 00 50 00 5A 00 C8 00 04 00 58 02 2C 01 F2 02 00 00 28 23 00 00 03 02 D3 FF 78 00` |
| El de la secuencia 18 con carriles (v0.12): cuatro; recto, recto, recto o ligera a la derecha (vale la ligera) y ligera a la derecha (vale) | `01 12 01 02 00 50 00 5A 00 C8 00 04 00 58 02 2C 01 F2 02 00 00 28 23 00 00 03 02 D3 FF 78 00 04 01 01 03 02 00 00 02 02` |
| Saturado: recto a 70 000 m, ángulo 200, 1 000 000 m, 10 000 000 s, llegada 1440, paso −5 m, 5 000 000 000 s de viaje, −5 m recorridos | `01 00 01 01 00 FE FF B4 00 FE FF FE FF FF FF 00 00 FE FF FF FF 00 00 00 00 00 00 FF 7F FF FF` |

- Flags: ruta activa `01`, más recalculando `03`, más fuera de ruta `05`;
  llegada `08` (con ruta activa, `09`).
- Las distancias y el tiempo restante se redondean y se saturan en 65 534
  (`FE FF`); el ángulo, en ±180 (−400 va como −180, `4C FF`); una hora de
  llegada fuera de 0-1439, o lo que no es finito, va como desconocido. El
  tiempo de viaje y la distancia recorrida se redondean y se saturan en
  4 294 967 294 (`FE FF FF FF`); lo negativo va como 0 y lo que no es finito,
  como desconocido. El ángulo y la distancia del «y luego», igual que los de
  la siguiente maniobra: ángulo 200 y 70 000 m van como `B4 00 FE FF`.
- Con una conexión que admite de 25 a 30 bytes, el del «y luego» sale sin
  los 6 últimos (25 bytes); con una que no admite 25, el de la llegada sale
  como `01 21 09 05 00 00 00 FF 7F FF FF FF FF FF FF FF FF` (17 bytes).
- Carriles: si no caben en lo que admite la conexión (pero admite 32 o
  más), o son más de 8, el byte 31 va a `00` (32 bytes). Al decodificar, si
  el número pasa de 8 o faltan bytes para todos, no hay carriles.
- Al decodificar: con 9 a 16 bytes, los campos de la v0.6 son desconocidos
  (`01 05 01 01 00 64 00 00 00`: recto a 100 m, ángulo 0); con 17 a 24, los
  de la v0.10; con 25 a 30, los de la v0.11 (sin maniobra luego); un código
  de maniobra que no está en la tabla (por ejemplo, 9), también en el byte
  25, se lee como 0; se descartan `01 05 01 01 00 64 00 00` (corto) y la
  versión 2.
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

### `TRAZO` con movimiento (v0.9)

Solo para un dispositivo con el bit 10 de capacidades. Flags con el bit 3;
giro sobre la lista entera; recorrido en decímetros (`u32`); cuántos puntos
van detrás; y los puntos: los de detrás (del más lejano al más cercano), la
moto (0, 0) y los de delante.

| Caso | Bytes |
|---|---|
| Secuencia 3, escala 2, recorrido 1234,5 m (12 345 dm): detrás (0, −120) y (−5, −60); la moto; delante (0, 100), el giro (índice 3), y (−30, 150) | `01 03 0D 03 39 30 00 00 02 00 00 88 FF FB FF C4 FF 00 00 00 00 00 00 64 00 E2 FF 96 00` |
| Secuencia 0, al salir: escala 3, recorrido 0, nada detrás; la moto y el giro en (0, 250) | `01 00 0F 01 00 00 00 00 00 00 00 00 00 00 00 FA 00` |
| Secuencia 16, escala 1, sin giro, recorrido 123 456,7 m (1 234 567 dm): detrás (3, −40); la moto; delante (0, 312) | `01 10 0B FF 87 D6 12 00 01 03 00 D8 FF 00 00 00 00 00 00 38 01` |

- Flags con tramo y movimiento: escala 0 `09`, 1 `0B`, 2 `0D`, 3 `0F`.
- El recorrido se redondea al decímetro (0,04 m va como 0 y 0,05 m como 1
  dm) y se satura en `FF FF FF FF` (429 496 729,5 m o más); negativo, o lo
  que no es finito, va como 0.
- Como mucho 42 puntos (177 bytes) y 10 por detrás. Si no caben, se dejan
  primero los de delante: con 20 bytes por escritura caben 2 puntos y el
  primer caso va como `01 03 0D 01 39 30 00 00 00 00 00 00 00 00 00 64 00` (la
  moto y el primero de delante; el giro pasa al índice 1); con 25 bytes, 4
  puntos, con el de detrás más cercano (−5, −60). Con más de 10 por detrás se
  quitan los más lejanos. Un giro que queda fuera va como 255.
- Sin tramo, el mensaje sin tramo de siempre, de 4 bytes (`01 05 00 FF`),
  también si `atrás` deja la moto fuera de la lista o si queda un solo punto.
- Al decodificar: con el bit 3, se descarta un mensaje de menos de 9 bytes
  (`01 03 0D 03 39 30 00 00`); sin el bit 0 no hay tramo, pero se lee el
  recorrido (`01 05 08 FF 0A 00 00 00 00`: 1 m); un `atrás` de más de 10 o que
  deja la moto fuera de los puntos que han llegado se lee como sin tramo
  (`01 00 09 FF 00 00 00 00 02 00 00 00 00 00 00 64 00`). Sin el bit 3, el
  formato de arriba, sin cambios.

## `CRUCES`

| Caso | Bytes |
|---|---|
| Sin calles, secuencia 0, del `TRAZO` 0 | `01 00 00 00` |
| Secuencia 3, del `TRAZO` 7: dos calles en (0, 120), a la derecha (64) y a la izquierda (192), y una en (−15,4; 300,6) a la izquierda, algo hacia delante (200: 281°) | `01 03 07 03 00 00 78 00 40 00 00 78 00 C0 F1 FF 2D 01 C8` |
| v0.8, secuencia 3, del `TRAZO` 7: una calle en (0, 120) a la derecha y un anillo con el centro en (−20, 150) y 15,6 m de radio (16) | `01 03 07 01 00 00 78 00 40 01 EC FF 96 00 10` |
| v0.8, secuencia 0, del `TRAZO` 2: sin calles y un anillo en (0, 40) de 8 m | `01 00 02 00 01 00 00 28 00 08` |

- Coordenadas como en `TRAZO` (se redondean y se saturan igual); la dirección,
  en 1/256 de vuelta.
- Como mucho 35 calles (179 bytes). Con 20 bytes por escritura caben 3; se
  recorta por el final, así que se quedan las de los cruces más cercanos.
- Al decodificar, se leen como mucho `n` calles y solo las que llegan enteras
  (`01 00 05 02 00 00 0A 00 40 01`: una calle, (0, 10) a la derecha). Se
  descartan `01 03 07` (corto) y la versión 2.
- **Anillos (v0.8):** tras las `n` calles, un byte con cuántos (0 a 4) y 5 por
  anillo: centro (`i16`, `i16`) y radio (`u8`, redondeado y saturado entre 1
  y 255 m: 300 m va como `FF` y 0,2 m como `01`). Sin anillos, el mensaje
  acaba tras las calles, como antes. Solo se mandan si el dispositivo anuncia
  el bit 9 de capacidades.
- Con anillos, el mensaje entero tampoco pasa de 179 bytes y los anillos van
  primero: con 4 anillos caben 30 calles (175 bytes); con 1, 33 (175 bytes);
  con 20 bytes por escritura y un anillo, 2 calles (20 bytes). Si no cabe ni
  un anillo (9 bytes), el mensaje acaba tras las calles.
- Al decodificar los anillos: solo si han llegado las `n` calles y queda algo
  detrás; como mucho 4 (`01 00 05 00 09` y cinco anillos enteros: se leen 4),
  y solo los que llegan enteros (`01 00 05 00 01 EC FF 96 00`: ninguno). Un
  dispositivo anterior a la v0.8 lee las `n` calles e ignora el resto.

## `GPS`

| Caso | Bytes |
|---|---|
| Secuencia 3: posición de hace 0,4 s, altitud 712 m (precisión 6,2 m), 13,89 m/s, rumbo 271,5°, precisión horizontal 4,7 m | `01 03 0F 04 C8 02 06 6D 05 0E 6A 05` |
| Secuencia 0, sin posición, app en segundo plano | `01 00 10 FF 00 80 FF FF FF FF FF FF` |

- Se redondea: 0,4 s son 4 décimas, 6,2 m son 6 y 4,7 m son 5.
- La edad satura en 254 décimas (25,4 s) y las precisiones en 254 m; la
  altitud negativa va en complemento a dos (-12 m: `F4 FF`).
- Se descarta un mensaje de menos de 12 bytes.

## `DEVICE_INFO`

| Caso | Bytes | Tipo | Capacidades | Frecuencia | Firmware |
|---|---|---|---|---|---|
| Firmware de referencia 0.1.0 | `01 02 24 00 00 00 01 00` | 2 | `STATUS` + `MOVIL` (0x0024) | sin límite | 0.1.0 |
| Cuadro, primera integración LPR | `01 01 2C 00 00 00 01 00` | 1 | `STATUS` + `NAV_TEXT` + `MOVIL` (0x002C) | sin límite | 0.1.0 |
| Cuadro con el trazo y MOVIL al cambiar | `01 01 EC 00 00 00 02 00` | 1 | `STATUS` + `NAV_TEXT` + `MOVIL` + `TRAZO` + MOVIL al cambiar (0x00EC) | sin límite | 0.2.0 |
| Cuadro con `NAV`, `GPS` y `CRUCES` | `01 01 EF 01 00 00 03 00` | 1 | `NAV` + `GPS` + `STATUS` + `NAV_TEXT` + `MOVIL` + `TRAZO` + MOVIL al cambiar + `CRUCES` (0x01EF) | sin límite | 0.3.0 |
| Cuadro con todo, también los anillos (v0.8) | `01 01 EF 03 00 00 04 00` | 1 | las de 0.3.0 + anillos (0x03EF) | sin límite | 0.4.0 |
| Cuadro con todo, también el movimiento (v0.9) | `01 01 EF 07 00 00 05 00` | 1 | las de 0.4.0 + movimiento (0x07EF) | sin límite | 0.5.0 |
| Cuadro con los carriles (v0.12) | `01 01 EF 0F 00 00 06 00` | 1 | las de 0.5.0 + carriles (0x0FEF) | sin límite | 0.6.0 |
| Cuadro con las rutas (v0.13) | `01 01 EF 1F 00 00 07 00` | 1 | las de 0.6.0 + rutas (0x1FEF) | sin límite | 0.7.0 |

- Se descarta cualquier mensaje de menos de 8 bytes.
