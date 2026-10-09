# Protocolo BLE móvil → cuadro

> **Estado: borrador v0.13 (2026-10-10), sin validar.** Los puntos marcados
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
| `NAV_TEXT` | `f4640006-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta (el cuadro acepta también con respuesta) | cifrado | ≤ 182 B (sección 7 bis) |
| `CONFIG` | `f4640007-813a-45b8-8ca8-f5f9e18c21d1` | reservado | — | — |
| `MOVIL` | `f4640008-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 20 B |
| `TRAZO` | `f4640009-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 180 B (sección 7 ter) |
| `CRUCES` | `f464000a-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 179 B (sección 7 quater) |
| `RUTAS` | `f464000b-813a-45b8-8ca8-f5f9e18c21d1` | escritura sin respuesta | cifrado | ≤ 161 B (sección 7 quinquies, v0.13) |

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
  app consulta `maximumWriteValueLength(for:)` en tiempo de ejecución. Las
  excepciones son `NAV_TEXT` (sección 7 bis), `TRAZO` (sección 7 ter) y
  `CRUCES` (sección 7 quater), que se ajustan al MTU de la conexión, y `NAV`
  desde la v0.10 (25 bytes con el resumen del viaje; 31 con el «y luego» de la
  v0.11; de 32 a 48 con los carriles de la v0.12): la app manda los campos que
  quepan en lo que admita la conexión, de 17, 25, 31 o de 32 a 48 bytes (estos,
  solo con el bit 11 de capacidades).

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
| 2-3 | capacidades | u16 | Bit 0 `NAV`, bit 1 `GPS`, bit 2 `STATUS`, bit 3 `NAV_TEXT`, bit 4 `CONFIG`, bit 5 `MOVIL`, bit 6 `TRAZO`, bit 7 `MOVIL` al cambiar (sección 7), bit 8 `CRUCES`, bit 9 anillos: dibuja los anillos de las rotondas de `CRUCES` (sección 7 quater, v0.8), bit 10 movimiento: acepta `TRAZO` con la posición en la ruta y los puntos de detrás, y mueve el dibujo él solo entre mensajes (sección 7 ter, v0.9), bit 11 carriles: acepta `NAV` con los carriles y los dibuja (sección 5, v0.12), bit 12 rutas: enseña las últimas rutas de `RUTAS` y pide empezar una con `STATUS` (secciones 7 quinquies y 9, v0.13). |
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
| 9-10 | distancia restante | u16 | `0xFFFF` | Hasta el destino, en decenas de metros; satura en 65 534 (añadido en la v0.6). |
| 11-12 | tiempo restante | u16 | `0xFFFF` | Hasta el destino, en minutos, redondeado (v0.6). |
| 13-14 | llegada | u16 | `0xFFFF` | Hora de llegada prevista, en minutos desde la medianoche, con la hora local del móvil: 0-1439 (v0.6). |
| 15-16 | longitud del paso | u16 | `0xFFFF` | Metros del paso actual entero, de la maniobra anterior a la siguiente; satura en 65 534 (v0.6). Con la distancia, da el avance hacia la maniobra. |
| 17-20 | tiempo de viaje | u32 | `0xFFFFFFFF` | Segundos desde que se inició la ruta, paradas incluidas; los recálculos no lo reinician (v0.10). |
| 21-24 | distancia recorrida | u32 | `0xFFFFFFFF` | Metros recorridos desde que se inició la ruta, sumando las posiciones del GPS (v0.10). |
| 25 | luego: maniobra | u8 | 0 | La maniobra que va después de la siguiente (código de la sección 8); 0 si no hay (v0.11). |
| 26 | luego: modificador | u8 | 0 | Como el byte 4, para esa maniobra (v0.11). |
| 27-28 | luego: ángulo | i16 | `0x7FFF` | Como los bytes 7-8, para esa maniobra (v0.11). |
| 29-30 | luego: distancia | u16 | `0xFFFF` | Metros entre la siguiente maniobra y esa; satura en 65 534 (v0.11). |
| 31 | carriles | u8 | 0 | Cuántos carriles van detrás, de 0 a 8; 0 si no hay que enseñarlos (v0.12). |
| 32… | flechas de cada carril | u8 × n | — | Un byte por carril, de izquierda a derecha: las flechas pintadas en él, un bit por dirección (abajo). 0: sin flechas (v0.12). |
| 32+n… | flechas válidas de cada carril | u8 × n | — | Un byte por carril, en el mismo orden: las de sus flechas que sirven para la maniobra; 0 si el carril no vale (v0.12). |

- Longitud mínima: 9 bytes. Los campos de la v0.6 están si el mensaje tiene 17
  bytes o más; los de la v0.10, si tiene 25 o más; los de la v0.11, si tiene
  31 o más; si no, son desconocidos. Los carriles (v0.12) están si tiene 32
  bytes o más y caben todos (32 + 2n); si no, no hay.
- **Carriles (v0.12, a petición del autor el 2026-10-10, con un recuadro
  arriba en el mapa):** la app manda los del aviso que se ve de Valhalla
  (`bannerInstructions[].sub`, tipo `lane`; en Ferrostar, `laneInfo`). Valhalla
  solo los pone en el aviso de los últimos metros antes de algunas maniobras
  (400 m en una salida de autovía, comprobado el 2026-10-10 con
  valhalla1.openstreetmap.de), y dependen de que estén marcados en
  OpenStreetMap: el dispositivo los enseña mientras lleguen. Bits de cada
  dirección: 0 recto, 1 ligera a la derecha, 2 derecha, 3 fuerte a la
  derecha, 4 cambio de sentido, 5 ligera a la izquierda, 6 izquierda, 7 fuerte
  a la izquierda. La flecha válida es la dirección activa del carril; si el
  carril vale y no la trae, todas las suyas. Más de 8 carriles, o recalculando,
  fuera de ruta o al llegar: 0. Solo con el bit 11 de capacidades: si no, la
  app manda 31 bytes como mucho.
- **«Y luego» (v0.11, a petición del autor el 2026-10-09):** la app manda la
  maniobra que va después de la siguiente y la distancia entre las dos, con
  la misma regla de códigos y ángulos. Si las dos están a 150 m o menos
  (supuesto a ajustar), el cuadro la enseña en pequeño junto a la grande,
  para no perder la segunda de dos giros seguidos. Sin ella (última
  maniobra), código 0.
- **Resumen del viaje (v0.10, a petición del autor el 2026-10-09: «Cuando
  termina la ruta estaría bien que saliesen datos como tiempo de trayecto,
  kilometros totales y velocidad media»):** la app manda el tiempo de viaje y
  la distancia recorrida en todos los `NAV` con ruta. Al llegar (bit 3), el
  cuadro los enseña con la velocidad media (distancia entre tiempo). La
  distancia es la del GPS, no la de la ruta, así que cuenta los desvíos. Un
  dispositivo anterior a la v0.10 los ignora (sección 3).
- Sin ruta activa, la app manda `NAV` con el bit 0 a cero y el cuadro deja de
  mostrar la flecha.
- **Al llegar** (v0.6, a petición del autor: la bandera al terminar), la app
  sigue mandando `NAV` con los bits 0 y 3 a uno, el código 5 (llegada) y
  distancia 0, hasta que se termina la ruta; entonces, uno con el bit 0 a cero.
  El cuadro enseña una bandera a cuadros grande y «Has llegado».
- El **ángulo** permite dibujar la flecha aunque el código sea genérico (sección
  8). Desde la v0.6 la app lo saca del modificador de la maniobra con valores
  nominales: recto 0, ligero ±45, normal ±90, cerrado ±135 y cambio de sentido
  ±180 (el signo, el lado). En rotondas es la dirección de la salida respecto a
  la de entrada; con circulación por la derecha, 180 menos los grados que se
  recorren dentro (90 recorridos: +90, a la derecha; 180: 0; 270: -90).
- El **cuadro decide cómo mostrar la distancia** (por ejemplo, «200 m» o
  «1,2 km»). La app manda siempre metros.
- **Ritmo (v0.6):** como `TRAZO`: al cambiar, como mucho una vez por segundo, y
  repetido a los 1,5-2 s mientras haya ruta. Al acabar la ruta, uno con el bit 0
  a cero. Caduca a los 5 s.

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
- **Implementado en la v0.7 (2026-10-09)**, para un indicador de calidad del
  GPS en el cuadro (a petición del autor). iOS no da los satélites ni la
  señal: la calidad es la precisión horizontal que estima iOS. La posición
  (latitud y longitud) no se manda.
- **Ritmo:** como `TRAZO`: con cada posición, como mucho una por segundo, y
  repetido a los 1,5-2 s mientras haya alguna. La edad se calcula al mandar,
  así que si dejan de llegar posiciones (un túnel) va creciendo. Caduca a
  los 5 s.
- **Indicador del cuadro** (umbrales del autor de la app, supuestos a ajustar
  en la moto): bueno con 10 m o menos; regular, de 10 a 30; malo, con más de
  30; sin GPS (alerta roja) sin mensaje vigente, sin fix o con la posición de
  hace más de 5 s. Mientras no ha llegado ningún `GPS` en la conexión, el
  cuadro no enseña nada: así no da una alarma falsa con una app que no lo
  manda (anterior a la v0.7) ni justo al reconectar.

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
- **Al cambiar (v0.5, a petición del autor el 2026-10-09):** si el dispositivo
  anuncia el bit 7 de capacidades, da `MOVIL` por bueno mientras dure la
  conexión, sin caducidad. La app lo manda entonces solo al conectar, cuando
  cambia el estado o el nivel, cuando `STATUS` pide reenvío y, si en 2 s no
  llega su eco en `STATUS` (sin el bit de pide reenvío), otra vez. El
  dispositivo lo olvida al desconectar y cuando la app deja de recibir los
  avisos de `STATUS`. Sin el bit 7, como antes: cada 2 s y caduca a los 5 s.

## 7 bis. `NAV_TEXT` (escritura sin respuesta): texto de navegación

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | secuencia | u8 | |
| 2… | texto | UTF-8 | Sin terminador. Puede llevar saltos de línea (0x0A). Vacío: no hay texto que mostrar. |

- Longitud mínima: 2 bytes (texto vacío).
- Añadido en la v0.3 (2026-10-09), para la primera prueba de la cara de
  navegación del cuadro. Por ahora el texto es la indicación completa (por
  ejemplo, «350 m» y en otra línea «Gira a la derecha en Calle Mayor»).
- **Tamaño:** como mucho 182 bytes (2 + 180 de texto) y nunca más de lo que
  admita la conexión: la app consulta `maximumWriteValueLength(for:
  .withoutResponse)`, que con el MTU mínimo (23) son 20 bytes, 18 de texto. Si no
  cabe, la app corta el texto sin partir un carácter UTF-8.
- **Ritmo:** la app lo manda al cambiar y, mientras haya texto, como mínimo cada
  2 s. Al dejar de haber texto manda uno vacío. El cuadro lo da por caducado a
  los 5 s sin recibir `NAV_TEXT` y deja de mostrarlo (sección 10).
- **Caracteres:** el cuadro muestra los que tenga su fuente; los demás los cambia
  por su letra base (por ejemplo, «à» por «a») o los quita.

## 7 ter. `TRAZO` (escritura sin respuesta): tramo de ruta por delante

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | secuencia | u8 | |
| 2 | flags | u8 | Bit 0: hay tramo. A cero, el dispositivo deja de dibujarlo (fuera de ruta, recalculando o sin ruta). Bits 1-2 (v0.6): escala, los metros desde la moto hasta el borde de arriba del dibujo: 0 la ajusta el dispositivo al tramo (como en la v0.4), 1 = 250 m, 2 = 500 m, 3 = 1000 m. |
| 3 | giro | u8 | Índice, en la lista de puntos, del próximo giro; 255 si no está en el tramo. |
| 4… | puntos | (i16, i16) × n | Metros desde la moto, con el sentido de la marcha hacia arriba: x a la derecha e y hacia delante. El primero es la posición de la moto sobre la ruta, (0, 0). |

- Longitud mínima: 4 bytes. Con el bit 0 a uno hacen falta al menos dos puntos;
  si no, es como si estuviera a cero.
- Añadido en la v0.4 (2026-10-09), para dibujar en el cuadro el tramo siguiente
  de la ruta al estilo de los navegadores minimalistas.
- **Tamaño:** como mucho 44 puntos (180 bytes) y nunca más de lo que admita la
  conexión (`maximumWriteValueLength(for: .withoutResponse)`; con el MTU mínimo,
  4 puntos). La app simplifica el tramo para que quepa.
- **Qué tramo:** la app manda la ruta desde la posición de la moto hasta unos
  metros por delante que decide ella. El sentido de la marcha es el rumbo de la
  ruta unos metros por delante, no el del GPS.
- **Escala por niveles (v0.6, elegida por el autor el 2026-10-09).** Antes, el
  tramo se acortaba al acercarse al giro y el dispositivo ajustaba la escala:
  el dibujo se acercaba y parecía que faltaba más.
  - La app elige el nivel según lo que falte para la maniobra: más de 500 m,
    1000 m; de 500 a 200 m, 500 m; menos de 200 m, 250 m.
  - Durante una misma maniobra el nivel solo baja, así que hay como mucho dos
    saltos. Entre saltos, el giro baja hacia la moto sin cambiar de escala.
  - Con la maniobra siguiente, se elige de nuevo.
  - La app manda 1,25 veces los metros del nivel, para que el tramo llegue
    hasta arriba.
- **Ritmo:** la app lo manda al cambiar, como mucho una vez por segundo (uno
  que llegue antes sale en cuanto pasa el segundo), y lo repite a los 1,5-2 s
  mientras haya tramo. Al dejar de haberlo manda uno con el
  bit 0 a cero. El dispositivo lo da por caducado a los 5 s.

### Con movimiento (v0.9, bit 10 de capacidades)

Para que el dibujo vaya suave (a petición del autor el 2026-10-09: «se siente a
trompicones»), el dispositivo mueve él solo la moto por el tramo entre un
mensaje y otro, con la velocidad del GPS, y cuando llega el siguiente corrige
poco a poco la diferencia. Para eso necesita saber dónde está la moto en la
ruta y tener tramo de sobra. Además dibuja en gris oscuro el camino que ya se
ha hecho. Solo si el dispositivo anuncia el bit 10; si no, la app manda el
formato de arriba.

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | secuencia | u8 | |
| 2 | flags | u8 | Como arriba, con el bit 3 a uno: formato con movimiento. |
| 3 | giro | u8 | Índice del próximo giro en la lista entera de puntos (los de detrás incluidos); 255 si no está. |
| 4-7 | recorrido | u32 | Decímetros de ruta desde su inicio hasta la moto (el punto `atrás`). Con una ruta nueva (o recalculada) vuelve a empezar. |
| 8 | atrás | u8 | Cuántos puntos van por detrás de la moto, de 0 a 10. |
| 9… | puntos | (i16, i16) × n | Primero los de detrás, del más lejano al más cercano; después la moto, (0, 0), en el índice `atrás`; después los de delante. Ejes y unidades como arriba. |

- Longitud mínima: 9 bytes. Como mucho 42 puntos (177 bytes); la app
  simplifica para que quepan, dejando primero sitio a los de delante.
- **Delante:** la app manda 1,25 veces los metros del nivel más 100 m de
  margen, para que el dispositivo pueda seguir avanzando unos segundos sin
  quedarse sin tramo.
- **Detrás:** hasta 150 m de la ruta ya recorrida (como mucho 10 puntos).
- **Qué hace el dispositivo:**
  - Entre mensajes avanza la moto por la línea de puntos a la velocidad del
    último `GPS` (bit 2 y campo de velocidad); sin ella, con la que sale del
    recorrido entre los dos últimos `TRAZO`. Como mucho 2 s después del
    último mensaje y nunca más allá del último punto.
  - El sentido de la marcha lo saca de la misma forma que la app: el rumbo
    de la cuerda hasta 25 m por delante, sin pasar del giro (a menos de 3 m
    del giro, el del último segmento antes de él). El giro del dibujo y los
    cambios de escala los suaviza.
  - Con un `TRAZO` nuevo, la diferencia entre donde creía que iba la moto y
    donde dice el recorrido nuevo (en metros a lo largo de la ruta) se
    reparte en medio segundo. Si es de más de 50 m, o el recorrido baja más
    de 20 m (ruta nueva o recalculada), salta sin animar.
  - Los cruces y los anillos de `CRUCES` van en los ejes de su `TRAZO` (la
    moto en el punto `atrás`) y se mueven con él.
- **Ritmo:** como arriba.

## 7 quater. `CRUCES` (escritura sin respuesta): calles que salen del tramo

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | secuencia | u8 | |
| 2 | trazo | u8 | Secuencia del `TRAZO` al que acompaña: el dispositivo solo los dibuja con ese tramo. |
| 3 | n | u8 | Número de calles, de 0 a 35. |
| 4… | calles | (i16, i16, u8) × n | Por cada calle, el cruce en metros, en los mismos ejes que `TRAZO` (x a la derecha, y hacia delante, la moto en (0, 0)), y su dirección en 1/256 de vuelta, en sentido horario desde «hacia delante»: 0 delante, 64 derecha, 128 atrás, 192 izquierda. |
| 4 + 5n | m | u8 | Opcional (v0.8): número de anillos, de 0 a 4. Si el mensaje acaba tras las calles, no hay anillos. |
| 5 + 5n… | anillos | (i16, i16, u8) × m | Por cada anillo de rotonda, su centro en metros, en los ejes de `TRAZO` y *little-endian*, como las calles, y su radio en metros, de 1 a 255, redondeado. |

- Longitud mínima: 4 bytes. Como mucho 35 calles (179 bytes) y nunca más de lo
  que admita la conexión.
- **Tamaño con anillos (v0.8):** el mensaje entero no pasa de 179 bytes (el
  cuadro recorta ahí): 4 + 5n + 1 + 5m ≤ 179. Con anillos caben menos calles
  (con 4 anillos, 30). Los anillos van primero: si no cabe todo, se recortan
  las calles más lejanas. Si no cabe ni un anillo, el mensaje acaba tras las
  calles.
- **Al leer:** el receptor lee como mucho `n` calles y solo las que llegan
  enteras. Si han llegado las `n` y el mensaje sigue, el byte siguiente es
  `m`: lee como mucho 4 anillos y solo los que llegan enteros. Un dispositivo
  anterior a la v0.8 lee las `n` calles e ignora lo demás (sección 3).
- Añadido en la v0.6 (2026-10-09), a petición del autor, para distinguir
  carreteras en el dibujo, como en la imagen de Beeline que pasó. El
  dispositivo dibuja un trozo corto de cada calle, desde el cruce hacia su
  dirección.
- **De dónde sale:** Valhalla, con formato OSRM, da en cada paso los cruces
  (`intersections`): su posición y los rumbos de todas las calles que salen de
  él (`bearings`), con la de llegada (`in`) y la de salida (`out`). Las calles
  que se dibujan son las demás. Comprobado con una consulta a
  valhalla1.openstreetmap.de el 2026-10-09.
- **Cuáles:** los cruces que quedan sobre el tramo de `TRAZO`, los más cercanos
  a la moto primero.
- **Sin rayas dobles (app 0.12.0):** Valhalla da una calle por cada vía de
  OpenStreetMap del nodo, también las aceras, los pasos de peatones, los
  carriles bici y la otra calzada de las avenidas. La app:
  - quita las calles de un cruce si tiene dos o más y por ninguna se puede
    entrar (`entry` a `false` en todas); una sola de no entrar (una calle de
    un sentido que llega a la ruta) se queda;
  - de cada grupo de calles casi paralelas (a 30 m o menos a lo largo de la
    ruta y a 30° o menos de rumbo) manda una: la primera por la que se puede
    entrar o, si no hay, la primera. Antes de recortar por tamaño.
  - Los umbrales son supuestos, sacados de 3 rutas reales (docs/DECISIONES.md).
- **Solo carreteras (v0.10, a petición del autor: «solo quiero
  carreteras»):** con los atributos de `/trace_attributes` de la ruta (el
  `use` de cada arista que cruza, casada con la calle por el nodo y el rumbo),
  la app quita las calles de garajes, pasillos de aparcamiento, callejones,
  pistas, caminos, carriles bici, aceras, escaleras y similares; se quedan las
  de `use` road, ramp, turn_channel, living_street, service_road y culdesac.
  Mientras no hay atributos (al empezar o tras un recálculo, hasta que
  llegan), se mandan como antes.
- **Anillos de las rotondas (v0.8):** en la respuesta solo viene el arco de la
  rotonda que recorre la ruta (del primer cruce del paso de la rotonda,
  `roundabout` o `rotary`, al primero del paso siguiente). La app le ajusta
  un círculo y solo lo manda si se ajusta bien (5 puntos o más, 40° o más de
  giro visto desde el centro, error cuadrático medio de 0,07 m o menos y un
  radio de 5 a 80 m; supuestos a ajustar en la moto). Solo los manda si el
  dispositivo anuncia el bit 9 de capacidades, y entonces, en los cruces de
  esas rotondas:
  - quita las calles que forman más de 90° con la radial hacia fuera (son el
    propio anillo, que ya se dibuja entero);
  - junta en una los brazos con isleta: dos calles seguidas de cruces
    distintos, una de salida de la rotonda (`entry` a `true`) y la siguiente
    de entrada (`entry` a `false`), a 90° o menos vistas desde el centro, que
    se cortan por fuera a menos de 100 m o son casi paralelas (menos de 15°) y
    a menos de 30 m. La calle que queda va en el anillo, a medio camino entre
    los dos cruces, con el rumbo medio.
  - Van los anillos que la ruta empieza a recorrer dentro del tramo y los que
    ha dejado hace poco (hasta 20 m antes del principio de la ventana del
    tramo, para que no desaparezcan dentro de la rotonda), en el orden de la
    ruta, como mucho 4.
- **Qué dibuja el dispositivo con el bit 9:** cada anillo, entero, como un
  círculo de ese centro y ese radio. Un radio de 0 no debería llegar (la app
  manda de 1 a 255).
- **Ritmo:** la app lo manda justo después de cada `TRAZO` con tramo, con la
  secuencia de ese `TRAZO`. Tras un `TRAZO` sin tramo no se manda: los cruces
  caducan con su `TRAZO`.

## 7 quinquies. `RUTAS` (escritura sin respuesta): últimas rutas para empezar desde el dispositivo

A petición del autor (2026-10-10): sin ruta, el dispositivo enseña las tres
últimas rutas de la app y, al tocar una, pide a la app que la empiece. Solo
con el bit 12 de capacidades.

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | secuencia | u8 | Cambia con cada `RUTAS` distinto (de lista o de estado). La orden de `STATUS` la lleva para decir de qué lista es la ruta tocada. |
| 2 | estado de la orden | u8 | 0 ninguna en curso (o ya atendida); 1 calculando la ruta; 2 rechazada: la app no está en primer plano y no puede empezar a guiar; 3 no se pudo (sin ruta, error o lista que ya no está). |
| 3 | eco de la orden | u8 | Contador (`STATUS`, byte 8) de la última orden que la app ha atendido; 0 ninguna. |
| 4 | rutas | u8 | Cuántas van detrás, de 0 a 3. |
| 5… | por ruta | — | Tipo (u8: 0 la más rápida, 1 la de más curvas, 2 por tierra), distancia (u16, decenas de metros; `0xFFFF` desconocida; satura en 65 534), tiempo (u16, minutos; `0xFFFF`), curvas (u16; `0xFFFF`), peaje y autopista (u16 cada uno, decenas de metros; 0 ninguno; `0xFFFF` no se sabe), largo del nombre (u8, de 0 a 40) y el nombre (UTF-8). |

- Las rutas, de la más reciente a la más antigua, con lo que medía la ruta
  propuesta la última vez que se inició (la app vuelve a calcularla desde
  donde esté), también el peaje y la autopista que la app enseña en su
  tarjeta (a petición del autor). El dispositivo no puede cambiar sus
  opciones.
- La app corta los nombres sin partir un carácter para que el mensaje quepa en
  lo que admita la conexión; si aun así no cabe, manda menos rutas.
- La app lo manda al estar lista la conexión, al cambiar la lista o el estado
  de la orden y con el reenvío completo. El dispositivo lo olvida al
  desconectarse.
- **La orden** va en `STATUS` (sección 9, bytes 8-11): al tocar una ruta, el
  dispositivo sube el contador y notifica `STATUS` con el código 1 (empezar),
  la secuencia del `RUTAS` que enseñaba y la posición de la ruta. Tocarla otra
  vez manda el código 2 (cancelar). La app atiende cada contador una vez:
  - con la app en primer plano, carga la ruta como en su pestaña «Rutas» y la
    empieza en cuanto la tiene (estado 1 y, al empezar a guiar, 0; si no
    puede, 3);
  - si no está en primer plano, estado 2: iOS no deja empezar a usar el GPS en
    segundo plano con el permiso «Mientras se usa la app» (la app lo activa al
    pulsar «Iniciar», en primer plano).
- Si en 5 s no llega un `RUTAS` con el eco de su orden, el dispositivo la da
  por perdida (supuesto).

## 8. Códigos de maniobra

Definidos en la v0.6 (2026-10-09). Tabla propia y corta: la forma de la flecha
la da el ángulo de `NAV` (sección 5). Ya no se intenta seguir los códigos
0-30 de *Komoot BLE Connect*.

| Código | Maniobra | Ferrostar (tipo y modificador, al estilo OSRM) |
|---|---|---|
| 0 | desconocida (sin flecha) | sin maniobra |
| 1 | recto | modificador «straight» o sin modificador, salvo los de abajo |
| 2 | giro (el ángulo dice a qué lado y cuánto) | modificadores «slight»/«sharp»/normal a derecha o izquierda; también bifurcaciones, incorporaciones, rampas y finales de vía |
| 3 | rotonda (modificador: número de salida; ángulo: dirección de salida) | tipos «roundabout», «rotary», «roundabout turn», «exit roundabout» y «exit rotary» |
| 4 | cambio de sentido (el signo del ángulo, el lado) | modificador «uturn» |
| 5 | llegada | tipo «arrive» |
| 6 | salida (inicio de la ruta) | tipo «depart» |

## 9. `STATUS` (lectura y notificación)

| Byte | Campo | Tipo | Descripción |
|---|---|---|---|
| 0 | versión | u8 | 1 |
| 1 | eco `NAV` | u8 | Última secuencia de `NAV` recibida. |
| 2 | eco `GPS` | u8 | Última secuencia de `GPS` recibida. |
| 3 | flags | u8 | Bit 0 pide reenvío completo (por ejemplo, tras reiniciarse). |
| 4 | eco `MOVIL` | u8 | Última secuencia de `MOVIL` recibida (añadido en la v0.2). |
| 5 | eco `NAV_TEXT` | u8 | Última secuencia de `NAV_TEXT` recibida (añadido en la v0.3). |
| 6 | eco `TRAZO` | u8 | Última secuencia de `TRAZO` recibida (añadido en la v0.4). |
| 7 | eco `CRUCES` | u8 | Última secuencia de `CRUCES` recibida (añadido en la v0.6). |
| 8 | orden: contador | u8 | Sube con cada orden de ruta (sección 7 quinquies); 0 ninguna desde la conexión; tras 255, 1 (v0.13). |
| 9 | orden: código | u8 | 1 empezar la ruta, 2 cancelar (v0.13). |
| 10 | orden: lista | u8 | Secuencia del `RUTAS` que enseñaba el dispositivo (v0.13). |
| 11 | orden: ruta | u8 | Posición de la ruta en esa lista, desde 0 (v0.13). |

- Longitud mínima: 4 bytes. Un `STATUS` de 4 bytes viene de un dispositivo
  anterior a la v0.2 y no trae eco de `MOVIL`; uno de 5, de uno anterior a la
  v0.3, sin eco de `NAV_TEXT`; uno de 6, de uno anterior a la v0.4, sin eco de
  `TRAZO`; uno de 7, de uno anterior a la v0.6, sin eco de `CRUCES`; uno de
  menos de 12, sin orden de ruta.
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
  (mantenimiento), aunque no cambie nada. `NAV_TEXT` y `TRAZO`, igual mientras
  haya texto o tramo (secciones 7 bis y 7 ter); `NAV` y `TRAZO`, como mucho
  una vez por segundo; `CRUCES`, con cada `TRAZO`. Excepción: `MOVIL` con un
  dispositivo que anuncia el bit 7, solo al cambiar (sección 7).
- La app mira cada 0,5 s qué toca mandar y repite cada característica a los
  1,5 s de su último envío, cada una por su cuenta: así no salen en ráfagas.
- La app mira también qué toca al recibir cada `STATUS`, y lo manda todo cuando
  el `STATUS` pide reenvío (como mucho cada 0,5 s). Es para el **segundo
  plano** (y la pantalla bloqueada): los avisos BLE despiertan a la app aunque
  iOS la haya suspendido y su temporizador no se dispare; con el `STATUS`
  periódico del dispositivo (cada 2 s) basta.
- El cuadro da por **caducado** un dato si pasan más de **5 s** sin recibir su
  característica (decidido el 2026-10-08), salvo `MOVIL` con el bit 7 (v0.5),
  que vale mientras dure la conexión. Entonces muestra el mismo aviso que sin
  GPS.
- **Edad del fix:** el GPS puede estar caducado aunque los mensajes lleguen.
- **Al conectar,** la app lee `DEVICE_INFO`, se suscribe a `STATUS` y manda el
  estado completo sin esperar a ningún cambio.

## 11. Servicios que cambian: *Service Changed*

- iOS guarda en caché los servicios GATT de los dispositivos con los que está
  emparejado. Si el firmware cambia sus servicios (por ejemplo, al pasar del
  sketch del cuadro al de referencia, o al añadir este servicio al cuadro), el
  iPhone puede seguir viendo los antiguos.
- El dispositivo debe **indicar *Service Changed*** (característica 0x2A05 del
  servicio 0x1801) cuando se cifra el enlace con un móvil **que ya estaba
  emparejado** al conectar. Con NimBLE se hace con
  `ble_svc_gatt_changed(0x0001, 0xFFFF)`.
- **Con un emparejamiento nuevo no se indica:** el móvil acaba de leer los
  servicios actuales. En la prueba del 2026-10-08 el aviso llegó a mitad de la
  preparación de la app y la dejó sin terminar.
- La app vuelve a descubrir los servicios cuando iOS le avisa de que han cambiado
  el servicio LPR (`peripheral(_:didModifyServices:)`). Si la preparación no
  termina en 10 s, corta la conexión y vuelve a conectar.
- Si aun así no aparecen, se borra el emparejamiento en el iPhone (Ajustes >
  Bluetooth > el dispositivo > Omitir este dispositivo). La librería BLE del core
  3.3.8 acepta el emparejamiento nuevo y borra el vínculo antiguo
  (`BLEServer.cpp`, evento `BLE_GAP_EVENT_REPEAT_PAIRING`).

## 12. Pendiente

- Parámetros de conexión que pida el cuadro. En el planteamiento inicial:
  intervalo de 30-60 ms, latencia 4 y *timeout* de 4 s, a medir con el eco de
  `STATUS`.
- `CONFIG` (unidades…), cuando se pida.

## 13. Cambios

- **v0.13 (2026-10-10):** `RUTAS` (sección 7 quinquies) con las tres últimas
  rutas de la app, y orden de ruta en los bytes 8-11 de `STATUS` (sección 9),
  con el bit 12 de capacidades. La versión del formato sigue siendo 1.
- **v0.12 (2026-10-10):** `NAV` con los carriles antes de la maniobra
  (sección 5), de 32 a 48 bytes, y bit 11 de capacidades. La versión del
  formato sigue siendo 1.
- **v0.11 (2026-10-09):** `NAV` con la maniobra que va después de la
  siguiente y la distancia entre las dos («y luego», sección 5), 31 bytes. La
  versión del formato sigue siendo 1.
- **v0.10 (2026-10-09):** `NAV` con el tiempo de viaje y la distancia
  recorrida (sección 5), para el resumen al llegar. En `CRUCES`, la app solo
  manda calles de carretera (sección 7 quater). La versión del formato sigue
  siendo 1.
- **v0.9 (2026-10-09):** `TRAZO` con movimiento (sección 7 ter, bit 10 de
  capacidades): recorrido de la moto en la ruta, puntos de detrás y 100 m más
  de tramo, para que el dispositivo mueva el dibujo él solo entre mensajes y
  pinte el camino hecho. Sin el bit 10, como antes. La versión del formato
  sigue siendo 1. Es la fase 1; la fase 2 (la ruta entera en el dispositivo)
  vendrá aparte.
- **v0.8 (2026-10-09):** bloque opcional de anillos de rotondas al final de
  `CRUCES` (sección 7 quater): 1 byte con cuántos (0 a 4) y, por anillo, el
  centro (i16, i16) y el radio (u8), sin pasar de 179 bytes en total; bit 9 de
  capacidades (0x0200, el dispositivo dibuja los anillos). La app solo manda
  el bloque si el dispositivo anuncia el bit 9; los anteriores lo ignorarían
  igualmente. Un cuadro 0.4.0 con todo anuncia 0x03EF. La versión del formato
  sigue siendo 1.
- **v0.7 (2026-10-09):** `GPS` implementado (sección 6), para el indicador de
  calidad del cuadro; el cuadro anuncia el bit 1 de capacidades. La versión
  del formato sigue siendo 1.
- **v0.6 (2026-10-09):** para la cara de navegación nueva del cuadro (pedida
  por el autor con una imagen de Beeline): `NAV` completo, con la tabla de
  maniobras (sección 8), la distancia y el tiempo restantes, la hora de
  llegada y la longitud del paso (sección 5); escala por niveles en los bits
  1-2 de los flags de `TRAZO` (sección 7 ter); característica `CRUCES`
  (sección 7 quater, bit 8 de capacidades); eco de `CRUCES` en el byte 7 de
  `STATUS`. La versión del formato sigue siendo 1.
- **v0.5 (2026-10-09):** bit 7 de capacidades, `MOVIL` al cambiar: con él, la
  app manda `MOVIL` solo cuando cambia (con confirmación por el eco) y el
  dispositivo lo da por bueno mientras dure la conexión (sección 7). Antes,
  para todos: cada 2 s y caducidad de 5 s, que sigue sin el bit. Ritmo del
  mantenimiento por característica (sección 10). La versión del formato sigue
  siendo 1.
- **v0.4 (2026-10-09):** característica `TRAZO` (sección 7 ter), bit 6 de
  capacidades, eco de `TRAZO` en el byte 6 de `STATUS` y mantenimiento al
  recibir `STATUS` en segundo plano (sección 10). La versión del formato sigue
  siendo 1.
- **v0.3 (2026-10-09):** característica `NAV_TEXT` (sección 7 bis), la única que
  puede pasar de 20 bytes; eco de `NAV_TEXT` en el byte 5 de `STATUS`. El
  cuadro integra el servicio LPR (tipo 1, capacidades `STATUS`, `NAV_TEXT` y
  `MOVIL`). La versión del formato sigue siendo 1.
- **v0.2 (2026-10-08):** característica `MOVIL` (estado de la batería del móvil),
  bit 5 de capacidades, eco de `MOVIL` en el byte 4 de `STATUS`, `STATUS` también
  legible, `DEVICE_INFO` cifrada y sección 11 (*Service Changed*). La versión del
  formato de los mensajes sigue siendo 1: todo se añade al final.
- **v0.1 (2026-10-08):** primer borrador.
