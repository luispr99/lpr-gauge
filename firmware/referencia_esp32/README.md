# Firmware de referencia (ESP32-S3)

Periférico BLE con el servicio LPR de [PROTOCOLO.md](../../docs/PROTOCOLO.md)
(v0.2). Recibe `MOVIL` (estado de la batería del iPhone), lo escribe por el
monitor serie y contesta con `STATUS`. No usa la pantalla.

**Sin compilar:** lo compila el autor en el IDE de Arduino. No se usa
arduino-cli.

## Cargarlo

1. Abrir `referencia_esp32.ino` en el IDE de Arduino, con el core esp32 3.3.8 y
   la placa ESP32-S3 del cuadro.
2. Compilar y subir. **Mientras esté cargado, el cuadro no funciona;** después
   hay que volver a cargar su sketch.
3. Abrir el monitor serie a 115200 baudios. Debe salir:
   `[REF] Firmware de referencia LPR, protocolo v0.2` y
   `[REF] Anunciándose. Esperando al iPhone...`.

## Probarlo con la app

1. En el iPhone, Ajustes > Bluetooth > «CL500» > **Omitir este dispositivo**, para
   que olvide los servicios del sketch del cuadro (PROTOCOLO.md §11). Después,
   la placa aparecerá como «LPR Gauge».
2. Abrir la app. La primera vez pide permiso de Bluetooth y, al conectar, iOS
   muestra «Solicitud de enlace Bluetooth»: aceptar.
3. En el monitor serie deben salir, por este orden:
   - `Conectado`;
   - `Enlace cifrado`;
   - `Suscripción a STATUS: sí`;
   - una línea `MOVIL seq …` cada 2 s, con el estado de la batería.
4. Enchufar y desenchufar el iPhone: la línea siguiente debe decir «cargando» o
   «sin cargar» casi al momento.
5. En la app, «Eco de la placa» debe seguir a «Última secuencia», y la latencia
   debe aparecer en milisegundos.

## Mensajes por serie

| Mensaje | Qué significa |
|---|---|
| `Conectado (handle …, sin cifrar)` | El iPhone se ha conectado; el cifrado llega después. |
| `Enlace cifrado` | Emparejamiento o vínculo guardado correcto. |
| `El cifrado ha fallado` | Se rechazó el emparejamiento en el iPhone. |
| `MOVIL seq N: batería …` | Mensaje recibido y descodificado. |
| `MOVIL descartado` | Mensaje corto, de otra versión o con un estado desconocido. |
| `Sin datos del móvil desde hace 5 s` | Caducidad (PROTOCOLO.md §10). |
