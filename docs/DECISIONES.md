# Decisiones

Cada decisión lleva fecha, motivo y, si se apoya en un dato externo, su fuente
y la fecha de consulta. Lo que falta por probar en el iPhone, en la moto o en la
placa está en [Pendiente de probar](#pendiente-de-probar). Las fuentes están al
final.

## Alcance

### 2026-10-08 · Proyecto personal, repositorio público y sin licencia

- Proyecto personal; quizá producto más adelante.
- Repositorio público (los runners macOS estándar de GitHub Actions son gratuitos
  en repositorios públicos [F1]).
- Sin fichero de licencia: todos los derechos reservados. Se puede abrir más
  adelante; lo publicado con licencia abierta no se puede retirar.

### 2026-10-08 · Plataformas

- Primero iPhone. El móvil de pruebas principal tiene iOS 27.
- Android más adelante.

### 2026-10-08 · Tecnología: Swift nativo en iPhone; Android nativo después

- **Planteamiento anterior, del mismo día:** que el mismo código sirviera para
  iPhone y Android, con una tecnología multiplataforma.
- **Decisión:** app de iPhone en Swift y SwiftUI. La de Android, cuando toque, en
  Kotlin. Las dos comparten el protocolo (`docs/PROTOCOLO.md`) y sus vectores de
  prueba, no el código.
- **Motivo:** en cualquier tecnología, lo que funciona con la pantalla bloqueada
  (GPS, metros y BLE) tiene que ser código nativo de cada sistema (ver
  [lo comprobado](#tecnología-lo-comprobado)). En Swift se usan todas las API de
  Apple y el SDK de Ferrostar para Swift sin capas intermedias. Lo que se
  duplicará en Android es pequeño, porque el guiado lo hace Ferrostar en los dos
  sistemas. Si molesta, esa parte se puede pasar más adelante a Kotlin
  Multiplatform.

### 2026-10-08 · Versión mínima de iOS: 17.0

- **Valor anterior:** iOS 16.0 (planteamiento inicial, para conservar el iPhone 8
  con iOS 16.7 como móvil de pruebas).
- **Decisión:** iOS 17.0. El iPhone 8 queda fuera: no admite iOS 17 [F2].
- **Motivo:** iOS 17 da, sin código duplicado para iOS 16,
  `CLLocationUpdate.liveUpdates`, `CLBackgroundActivitySession`,
  `CBConnectPeripheralOptionEnableAutoReconnect` y `@Observable` [F3].

### 2026-10-08 · Qué muestra el cuadro

- La flecha del siguiente giro y los metros que faltan, actualizándose mientras se
  circula. Las flechas son imprescindibles.
- La altitud: del barómetro del móvil combinado con el GPS, si el sistema lo
  ofrece; si no, del GPS. Pendiente de verificar la API en iOS y en Android.
- Sin GPS, un aviso; nada más por ahora. Si se corta la conexión Bluetooth, el
  mismo aviso (propuesto el 2026-10-08 y no corregido por el autor).
- **Caducidad:** el cuadro muestra el aviso si pasan **5 s** sin recibir datos.

### 2026-10-08 · Rutas y flechas: Valhalla con Ferrostar

- **Decisión anterior, del mismo día:** Apple Maps en iPhone y Google en Android.
- **Decisión:** Valhalla como motor de rutas y Ferrostar para el guiado, en
  iPhone y en Android, con la condición de que sea gratis.
- **Motivo:** las flechas son imprescindibles. Valhalla da el tipo de maniobra;
  Apple Maps solo da texto, y Google exige cuenta de facturación (ver
  [lo comprobado](#rutas-y-flechas-lo-comprobado)).
- **Coste:** Valhalla (MIT) y Ferrostar (BSD-3) son software libre. Para la prueba
  personal se usa el servidor público de FOSSGIS: gratuito, con uso razonable y
  como mucho una petición por segundo [F20]. Para un producto haría falta un
  servidor propio.

### 2026-10-09 · Búsqueda con Apple Maps y variantes de ruta

- **Decisión anterior, del mismo día:** búsqueda con Nominatim (ver más abajo).
- **Decisión:** a petición del autor, la búsqueda pasa a Apple Maps (MapKit):
  sugerencias mientras se escribe (`MKLocalSearchCompleter`) y posición del lugar
  elegido (`MKLocalSearch`). Es gratuito y sin clave, y no tiene la prohibición
  de autocompletar de Nominatim, que deja de usarse.
- **Rutas:** siguen siendo de Valhalla, porque Apple Maps no da el tipo de
  maniobra.
- **Condiciones (orientativo):** usar un resultado de Apple para pedir la ruta a
  otro servidor encaja con el uso personal del Xcode and Apple SDKs Agreement.
  Para un producto lo tendría que revisar una persona (DPLA, anexo 6 [F17]).
- **Mapa en la pantalla de búsqueda,** con la posición. Al elegir un destino se
  previsualizan las rutas antes de empezar.
- **Sustituido el mismo día** (ver la decisión siguiente): las tres variantes
  «Más rápida», «Por secundarias» y «Más corta», todas sin peajes, pasan a ser
  «la más rápida» y «la más divertida», con botones de preferencias.

### 2026-10-09 · Preferencias de ruta: «la más rápida» y «la más divertida»

- **Petición del autor:** botones «evitar peajes», «evitar autopistas» y «solo
  asfalto», y solo dos propuestas: «la más rápida», por tiempo de llegada, y «la
  más divertida», por número de curvas sin pasarse mucho de tiempo.
- **Botones,** que se guardan entre usos. Al cambiarlos con un destino elegido se
  vuelven a pedir las rutas. Opciones de la moto en Valhalla [F33]:
  - Evitar peajes (activado por defecto, como antes): `use_tolls = 0`.
  - Evitar autopistas: `use_highways = 0`.
  - Solo asfalto: `exclude_unpaved = true` (sin tramos sin asfaltar salvo al
    principio o al final) y `use_trails = 0` (evita pistas y firmes malos).
- **Son preferencias, no prohibiciones.** Según la documentación, `use_tolls` y
  `use_highways` a 0 no garantizan evitarlos si no hay otro camino. Las
  exclusiones estrictas (`exclude_tolls`, `exclude_highways`) son experimentales
  y el servidor las ignora si no tiene activado `allow_hard_exclusions` [F33];
  no se ha comprobado si el de FOSSGIS lo tiene, así que no se usan.
- **Candidatas:** dos peticiones a Valhalla, separadas 1,1 s por el límite de
  FOSSGIS [F20], cada una con `alternates = 2` (hasta tres rutas por petición;
  Ferrostar devuelve todas las de la respuesta [F34]):
  - la normal de la moto, con las preferencias;
  - otra que además evita autovías (`use_highways = 0`) y prefiere secundarias
    (`use_trails = 0,5`; con «solo asfalto» se queda en 0, porque hacia 1 también
    admite pistas) [F33].
- **Elección:**
  - La más rápida: la candidata que menos tarda (suma de la duración de sus
    pasos, según Valhalla).
  - La más divertida: la de más curvas entre las que no tardan más de un
    **25 %** sobre la más rápida; a igualdad, la de más grados por km y luego la
    más rápida. El 25 % es un supuesto, pendiente de ajustar con rutas reales
    (`Curvas.margenTiempo`, en LPRCore). Si sale la misma que la más rápida, se
    muestra una sola, con una nota.
- **Curvas:** Valhalla no las mide; las cuenta la app sobre el trazado
  (LPRCore, `Curvas.swift`, con pruebas en CI sobre geometrías inventadas):
  - cada paso de la ruta por separado, para que los giros en los cruces no
    cuenten; se saltan las rotondas (pasos de menos de 300 m con número de
    salida);
  - el trazado se remuestrea cada 25 m; un cambio de rumbo de menos de 4° por
    tramo se toma como recta o ruido, y una curva es una racha de giros en el
    mismo sentido que suma al menos 30°.
  - Los umbrales son supuestos razonables, no salen de ninguna fuente; están
    pendientes de comprobar con rutas reales.
- **Al recalcular por desvío** se usan las opciones de la petición de la que salió
  la ruta elegida, sin alternativas. La ruta nueva puede no ser la misma
  alternativa.
- **Corregido el mismo día** (ver la decisión siguiente, con el código de
  Valhalla [F37]):
  - En moto, Valhalla ignora `exclude_unpaved`: solo lo aplican los perfiles de
    coche, taxi, autobús y camión.
  - `use_trails` solo cambia la penalización de los firmes sin asfaltar; no lleva
    a carreteras secundarias, aunque la documentación lo diga.
  - Por tanto, «Solo asfalto» en la 0.6.0 equivalía casi a no marcarlo
    (`use_trails = 0` es el valor por defecto), y la petición «secundarias» con
    `use_trails = 0,5` quitaba la penalización a la tierra.

### 2026-10-09 · Rutas 0.7.0: firme y peajes de cada ruta, «Por tierra» y margen ajustable

- **Petición del autor:**
  - botones más grandes con iconos;
  - «Solo asfalto» siempre marcado, con icono de carretera;
  - indicar en cada ruta si lleva peaje o tierra;
  - una barra para el % de tiempo extra;
  - tarjetas de ruta más grandes;
  - corregir la raya, que en carreteras con muchas curvas se ve fuera de la
    carretera.
- **Respuestas del autor (2026-10-09):**
  - «Solo asfalto» va marcado cada vez que se abre la app y se puede desmarcar
    para un viaje (no se guarda).
  - Sin «Solo asfalto» se añade una tercera ruta, «Por tierra».
  - La barra va de 0 a 200 %, con un 25 % por defecto; el valor elegido se
    guarda. Valor anterior: 25 % fijo.
- **Apple Maps no sabe del firme.**
  - MapKit no tiene ningún dato de firme ni opción para evitar tierra. De la ruta
    entera solo da `hasTolls` y `hasHighways` (iOS 16), y para la petición
    `tollPreference` y `highwayPreference` [F35].
  - La app Mapas, según la guía del iPhone, solo permite evitar peajes y
    autopistas en coche [F36].
- **Lo que hace Valhalla** (código de la 3.9.1 y del commit c803bdc, el que dice
  ejecutar el servidor de FOSSGIS el 2026-10-09 [F37]):
  - El formato OSRM (el que usa Ferrostar) marca el peaje de cada paso, pero no
    trae nada del firme.
  - El formato propio de Valhalla (`"format": "json"`) marca en cada maniobra el
    peaje (`toll`) y si alguna parte va sin asfaltar (`rough`). Sin asfaltar es
    compactado, tierra, grava o senda. Un camino sin etiqueta de firme en OSM
    cuenta como asfaltado, salvo las pistas (`highway=track`), que cuentan como
    tierra.
  - En moto no hay forma de prohibir la tierra; solo de penalizarla.
    - `use_trails = 0` multiplica el coste de la tierra, aproximadamente: compactado ×1,8,
      tierra ×2,6, grava ×5 y senda ×9.
    - `use_tracks = 0` cuadruplica el coste de las pistas y añade 300 s al
      entrar en una.
    - `use_trails = 1` da una ligera ventaja a la tierra.
- **Decisión:**
  - Las rutas propuestas se piden en el formato propio de Valhalla.
  - Al pulsar «Iniciar» se repite la misma petición en formato OSRM para
    Ferrostar. El cuerpo lo genera Ferrostar en las dos, con el mismo origen;
    solo cambia el formato.
  - De la respuesta OSRM se toma la ruta de la misma posición, comprobando que
    coincidan la distancia y el tiempo (±0,2 % o 5 m/5 s). Si ninguna coincide
    (el servidor ha cargado datos nuevos o ha devuelto menos alternativas), no
    se empieza: se vuelven a calcular las propuestas y se avisa.
  - Tampoco se empieza si, con buena precisión del GPS (≤25 m), la posición se
    ha alejado de la ruta más de 40 m respecto al origen con el que se calculó
    (supuesto, por debajo de los 50 m a partir de los que Ferrostar marca
    desvío). Las rutas salen de la posición del momento de proponerlas. Se
    vuelven a calcular y se avisa. Se compara con el origen porque Valhalla
    ajusta la salida a la carretera más cercana: desde una casa o un
    aparcamiento lejos de la carretera la ruta empieza lejos, y eso no cuenta.
  - Comprobado el 2026-10-09 con puntos públicos (Madrid–Segovia): las dos
    respuestas dan las mismas tres rutas, en el mismo orden y con la misma
    distancia y tiempo, y una maniobra por paso.
  - Se descarta pedir el firme con `/trace_attributes`: costaría una petición
    más por ruta candidata.
  - Al recalcular por desvío, Ferrostar se queda con la primera ruta de la
    petición: si la elegida era una alternativa, puede cambiar.
- **Peticiones,** separadas 1,1 s, cada una con `alternates = 2`:
  - normal y secundarias (`use_highways = 0`); con «Evitar autopistas» son la
    misma y solo se pide una;
  - sin «Solo asfalto», además una de tierra: `use_highways = 0`,
    `use_trails = 1` y `use_tracks = 1`.
  - «Solo asfalto» pone `use_trails = 0` y `use_tracks = 0` en todas.
  - Al empezar se hace una petición más (la de formato OSRM).
- **Tierra en medio** (LPRCore, `RespuestaValhalla.swift`): la de las maniobras
  entre la primera y la última asfaltada. La tierra seguida desde la salida o
  hasta la llegada no cuenta, como en `exclude_unpaved`. Es una aproximación por
  maniobra: si la tierra va dentro de una maniobra de salida o de llegada larga,
  no se ve.
- **Elección** (LPRCore, `Eleccion.swift`):
  - La más rápida y la más divertida se eligen entre las rutas sin tierra en
    medio. Si todas la llevan, se elige entre todas y se avisa.
  - «Por tierra» es la de más metros de tierra en medio entre las que caben en
    el margen; la de salida y llegada no cuenta. Exige al menos 500 m, un
    supuesto pendiente de ajustar.
  - Una ruta con varios papeles sale una sola vez, con los nombres juntos.
  - La barra no pide rutas nuevas: vuelve a elegir entre las candidatas.
- **Avisos en cada ruta:** «Peaje» y «Sin asfaltar», con los km. Son un máximo,
  porque Valhalla marca la maniobra entera.
- **La raya del mapa:**
  - Va con uniones redondeadas. En SwiftUI, `StrokeStyle` usa por defecto
    uniones en pico con límite 10 [F38]: con 8 pt de ancho, en una curva cerrada
    el pico puede salir unos 40 pt.
  - En el mapa de búsqueda, además, se simplifica con Douglas-Peucker según el
    zoom, con una tolerancia de 2 puntos de pantalla (supuesto). Al alejarse va
    más recta y al acercarse sigue la carretera. La escala sale de la región
    visible, que es exacta con el mapa sin girar ni inclinar.
  - En el guiado no se simplifica: la cámara está siempre cerca (250–1500 m),
    donde tiene que seguir la carretera.
  - Las dos causas, los picos y el mapa base generalizado al alejarse, son
    hipótesis sin comprobar en el iPhone.
- **Iconos** (SF Symbols disponibles en iOS 17, según SFSafeSymbols 7.0.0 [F39],
  que es de terceros):
  - opciones: `eurosign.circle.fill` (peaje), `car.rear.road.lane` (autopista) y
    `road.lanes` (asfalto);
  - rutas: `hare.fill` (rápida), `road.lanes.curved.right` (divertida) y
    `mountain.2.fill` (tierra).
  - No hay ningún símbolo de tierra ni de grava.

### 2026-10-09 · Pantalla del mapa 0.7.2 (maqueta aprobada)

- **Petición del autor,** con dos maquetas antes de programar; aprobó la
  segunda con estos cambios:
  - Primera fase solo por carretera: se quita el botón «Solo asfalto», que
    queda siempre activado, y con él «Por tierra». El código de tierra se
    conserva para más adelante.
  - Mapa en el 60 % de arriba; el resto, sin desplazar, para las opciones o las
    rutas y los botones. Sin destino, solo las opciones, ocupando todo el
    hueco.
  - Opciones como botones grandes («Evitar peajes», «Evitar autovías»). Al
    activarse, el icono se tacha (una diagonal dibujada por la app, porque SF
    Symbols no trae el euro ni la carretera tachados) y el botón pasa a un tono
    claro.
  - Con destino, una fila «Opciones de ruta» que abre las opciones en el sitio
    de las rutas.
  - La barra de tiempo extra se llama «Tiempo extra alternativas». Es más
    corta, con botones − y + de 25 en 25 %, y sigue de 0 a 200 %.
  - «La más divertida» pasa a llamarse «Mayor cantidad de curvas».
  - Cancelar es una X roja e «Iniciar», un botón verde grande.
  - Al elegir una ruta, el mapa se encuadra en ella entera, aunque se haya
    movido.
- **Decisión de la app** (no estaba en la maqueta): la simulación del recorrido
  pasa a Ajustes (rueda dentada), porque no cabe en el panel.
- **0.7.3, a petición del autor:** cada ruta indica también si lleva autopista,
  con los km («Autopista 52 km»), junto a «Peaje» y «Sin asfaltar». Sale del
  campo `highway` de cada maniobra del formato propio de Valhalla, que marca las
  vías de clase autopista de OSM (`motorway`; en España, autopistas y
  autovías), sin contar los enlaces [F37]. Como los demás, los km son un
  máximo por maniobra.
- **0.8.1, a petición del autor:**
  - mapa en el 55 % (antes el 60 %);
  - «Opciones de ruta» es un botón que se queda pulsado, en un tono más
    oscuro, mientras las opciones están abiertas, y se cierra con otro toque
    (antes, «Listo»);
  - simulación a 50, 100 y 150 km/h (antes 36, 72 y 108), con pasos de
    50/3,6 m: el simulador de Ferrostar 0.57.0 avanza un paso cada 1 s
    dividido por el factor (`Location.swift`);
  - el cartel del guiado, con fondo negro (antes azul).
- **0.8.3, a petición del autor:**
  - la autopista se indica con un icono de información (azul); el peaje y la
    tierra siguen con el de advertencia (naranja);
  - se quita el registro de la pestaña Placa; los mensajes de depuración van al
    registro del sistema (`Logger`, se ven con la app Consola del Mac), sin
    datos personales.

### 2026-10-09 · Primeros datos en el cuadro: texto de navegación y carga (0.8.0)

- **Petición del autor:** que el cuadro muestre el icono de la batería del
  iPhone «cargando», sin aviso, y una cara nueva solo de navegación, sin
  peticiones OBD, con el texto que mande la app en el centro, «sin nada más»,
  para empezar a ver resultados.
- **Protocolo v0.3** (`PROTOCOLO.md`): `NAV_TEXT` (sección 7 bis), la única
  característica que puede pasar de 20 bytes, hasta 180 bytes de texto en
  UTF-8, y el eco de `NAV_TEXT` en el byte 5 de `STATUS`.
- **App:**
  - con una ruta iniciada, manda la distancia al giro y, en otra línea, la
    instrucción («350 m» / «Gira a la derecha en…»); al llegar, «Has llegado»;
    al terminar, un texto vacío;
  - en la pestaña Placa, un campo para mandar un texto de prueba sin ruta;
  - el texto se manda al cambiar y cada 2 s, y no se escribe en el registro de
    la app (puede llevar calles), solo su longitud.
- **Cuadro:** el autor pidió hacerlo desde esta sesión, aunque la integración
  se iba a hacer en la del cuadro. El código del cuadro no entra en este
  repositorio público; los cambios se describen en su `docs/CAMBIOS_CLAUDE.md`,
  sección 74. Resumen:
  - servicio LPR en lugar del de prueba, con `DEVICE_INFO` tipo 1,
    capacidades `STATUS` + `NAV_TEXT` + `MOVIL` y firmware 0.1.0;
  - el rayo verde sustituye al icono del móvil mientras el iPhone se carga;
  - la cara de navegación, que no pide nada por OBD. Por eso, mientras se
    está en ella, no suman el tiempo de conducción ni las horas de motor del
    cuadro.

### 2026-10-09 · Recorrido en el cuadro y guiado en segundo plano (0.9.0)

- **Petición del autor:** ver en el cuadro parte del recorrido, al estilo
  minimalista de Beeline, y que la navegación siga con el iPhone fuera de la app
  y la pantalla bloqueada. Para la cara eligió la disposición «B»: el tramo de
  ruta arriba y la distancia y la instrucción debajo.
- **Protocolo v0.4** (`PROTOCOLO.md`): `TRAZO` (sección 7 ter), el tramo de
  ruta por delante en metros, en los ejes de la moto, hasta 44 puntos; eco en el
  byte 6 de `STATUS`; mantenimiento también al recibir `STATUS` (sección 10).
- **Qué tramo** (`Core/Sources/LPRCore/Trazo.swift`):
  - desde la posición de la moto ajustada a la ruta (la de Ferrostar), por los
    pasos que quedan, hasta 150 m después del próximo giro, entre 250 y
    1000 m (supuesto a ajustar en la moto). Al acercarse al giro el tramo se
    acorta y el cuadro, que ajusta la escala, se acerca;
  - el sentido de la marcha es el rumbo de la ruta hasta 25 m por delante, no
    el del GPS, que salta parado y a poca velocidad;
  - se simplifica (Douglas-Peucker) hasta que quepa en la conexión;
  - fuera de ruta, recalculando o al llegar no hay tramo; el texto dice «Fuera
    de ruta» o «Recalculando la ruta…».
- **Segundo plano:**
  - modos `location` y `bluetooth-central` en el Info.plist. No son
    entitlements: valen con la cuenta gratuita [F6];
  - al pulsar «Iniciar» (en primer plano, como exige Core Location):
    `allowsBackgroundLocationUpdates`, el indicador azul y una
    `CLBackgroundActivitySession`, que mantiene el permiso «Al usarse la app»
    en segundo plano desde iOS 17 [F3] [F40]. Al terminar se quitan;
  - el texto y el tramo pasan de la navegación al enlace BLE directamente, sin
    pasar por las vistas de SwiftUI, que en segundo plano pueden no
    actualizarse;
  - con la app suspendida su temporizador no se dispara; los avisos de
    `STATUS` del cuadro sí la despiertan [F41], y con ellos se manda el
    mantenimiento.
- **Riesgos sin comprobar:** que Sideloadly conserve los modos al volver a
  firmar; los huecos sin posiciones en iOS 27 [F12]; si el usuario cierra la
  app deslizándola, iOS no la vuelve a lanzar [F13].
- **0.9.1, revisión de la 0.9.0 antes de probarla** (un agente para la app y
  otro para el cuadro, solo lectura). Cambios en la app:
  - **El tramo se paraba en el giro.** Se contaba la distancia entera del paso
    actual, no lo que queda, así que no se veía la carretera de salida. Ahora
    cuenta lo que queda: `Trazo.pasosNecesarios`, con pruebas.
  - **Cerca del giro el dibujo rotaba hacia la salida**, porque la cuerda de
    25 m cruzaba la maniobra. Ahora el rumbo sale solo del paso actual; a
    menos de 3 m del giro, del último segmento. Con prueba.
  - **Ritmo de envío.** Antes había ráfagas y un tramo nuevo solo cada 2 s.
    Ahora la app mira cada 0,5 s qué toca, repite cada característica por su
    cuenta a los 1,5 s y un tramo nuevo sale en cuanto pasa 1 s del anterior.
  - **Al llegar** se quita el segundo plano. Ferrostar no para el GPS, que
    seguía con el iPhone bloqueado.
- **MOVIL solo al cambiar (protocolo v0.5).** El autor no quiere que la
  batería se mande constantemente, solo cuando cambia el % o la carga.
  - Un cuadro que anuncia el bit 7 da MOVIL por bueno toda la conexión.
  - La app lo manda al conectar, al cambiar o si se pide reenvío, y lo repite
    si en 2 s no llega el eco: el eco de STATUS sirve de confirmación.
  - Sin el bit (el firmware de referencia) sigue cada 2 s.
- **Cobertura del móvil en el cuadro: no se incluye.** El autor la pidió el
  2026-10-09, con las 4 rayas del iPhone y enviada solo al cambiar una raya,
  y añadió: si no se puede obtener, no se incluye.
  - Investigación del 2026-10-09: un workflow con tres investigadores y tres
    escépticos, con fuentes.
  - Resultado: iOS no da a las apps la intensidad de la señal móvil, ni en
    primer plano ni en segundo [F42].
  - Lo público que más se parece no son rayas: `NWPath.linkQuality` (iOS 26)
    mide la calidad del enlace y Apple desaconseja usarla para decidir
    [F43]; MetricKit da informes como mucho una vez al día.
  - Los métodos no públicos (leer la barra de estado, funciones privadas de
    CoreTelephony) dejaron de funcionar en iOS 16 o necesitan entitlements
    que un Apple ID gratuito no puede firmar [F44].
  - Lo único fiable sería «sin servicio» o la tecnología (5G/4G), con
    `serviceCurrentRadioAccessTechnology` [F45]; no se ha pedido.
- **0.9.2, segunda revisión** (workflow con verificación adversarial), con
  dos fallos menores corregidos:
  - el punto del giro se perdía al simplificar un giro suave
    (`Trazo.simplificar` lo conserva; con prueba);
  - al conectar se mandaba todo dos veces.
- **Cuadro:** se describe en su `docs/CAMBIOS_CLAUDE.md`, secciones 75 y
  75 bis (el código no entra en este repositorio). Recibe `TRAZO` y lo dibuja
  con una línea de LVGL y un marcador de la moto; la distancia y la
  instrucción van debajo. El rayo verde va ahora encima del icono del móvil,
  que con la carga toma el color del tema.
- **0.9.3:** botón «Ocultar teclado» encima del teclado en todos los campos de
  texto (a petición del autor).
- **0.9.4, panel de rutas.** Diseño aprobado por el autor con vistas previas,
  el 2026-10-09:
  - Se quita el botón «Opciones de ruta». En su lugar van tres botones en
    cápsula en una misma línea, aunque haya que bajar la letra: «Evitar
    peajes», «Evitar autovías» y uno con un reloj y el tiempo extra.
  - Activados, van rellenos del color de la app; los de evitar llevan además
    el icono tachado.
  - El del reloj despliega la barra del tiempo extra, con destino en el sitio
    de las rutas.
  - Tarjetas de ruta: título; km, curvas y lo que tarda de más; y un aviso
    por línea, el peaje primero. Las líneas se reparten el alto.
  - El tiempo va en grande a la derecha, en el sitio de la antigua marca de
    elegida.

### 2026-10-09 · Cara de navegación nueva: flecha, escala por niveles y cruces (0.10.0)

- **Petición del autor:** una cara de navegación nueva en el cuadro, a partir
  de una imagen de Beeline: el texto en una franja negra, flechas de
  maniobra, la llegada, un arco con el avance hacia la maniobra, las calles de
  los cruces y el triángulo de la moto en rojo. Además, el dibujo se acercaba
  al llegar al giro y parecía que faltaba más: el autor eligió fijar la escala
  por niveles según lo que falte.
- **Protocolo v0.6** (`PROTOCOLO.md`; la versión del formato sigue siendo 1):
  - `NAV` completo (sección 5), con una tabla de maniobras propia y corta
    (sección 8): la forma de la flecha la da el ángulo, con valores nominales
    del modificador. Añade la distancia y el tiempo restantes, la hora de
    llegada y la longitud del paso actual;
  - escala por niveles en los bits 1-2 de los flags de `TRAZO` (sección 7
    ter): con más de 500 m hasta la maniobra, 1000 m; de 500 a 200 m, 500 m;
    con menos de 200 m, 250 m. Dentro de una maniobra solo baja, y la app
    manda 1,25 veces los metros del nivel;
  - `CRUCES` (sección 7 quater, bit 8 de capacidades): las calles que salen
    del tramo, justo después de cada `TRAZO` y con su secuencia; eco en el
    byte 7 de `STATUS`.
- **Comprobado el 2026-10-09:** Valhalla, en formato OSRM, da en cada paso
  sus cruces (`intersections`): la posición, los rumbos de todas las calles
  (`bearings`, enteros) y los índices de la de llegada (`in`) y la de salida
  (`out`). Las calles laterales son las demás. Se comprobó con consultas a
  valhalla1.openstreetmap.de, una de ellas con las opciones que pone
  Ferrostar 0.57.0 en su petición (`format: osrm` y sus `filters`); los pasos
  traen también `driving_side`. Según la documentación de Ferrostar 0.57.0,
  `roundaboutExitDegrees` son los grados que se recorren dentro de la
  rotonda, 180 para seguir recto.
- **App** (`Core` con pruebas, y la app):
  - `NAV`: el código y el ángulo salen del tipo y del modificador de
    Ferrostar (`Flechas`), con el lado de la circulación del paso de la
    maniobra (si no viene, por la derecha). En rotondas, el número de salida
    va en el modificador. La hora de llegada usa la hora local del iPhone,
    redondeada al minuto. Ritmo como `TRAZO`, y solo si cambian los bytes. Al
    llegar, con ruta activa y el bit de llegada, hasta pulsar «Terminar» (el
    cuadro enseña la bandera; a petición del autor); al terminar, uno sin ruta
    activa.
  - Escala: `Trazo.nivel`. Una maniobra nueva es otro paso actual: cambia el
    número de pasos que quedan o el punto del giro.
  - Cruces: Ferrostar no los conserva en sus rutas. La app decodifica también
    la respuesta OSRM (la de «Iniciar» y las de los recálculos, que pasan por
    `ClienteRutas`) y se queda con la ruta cuyo trazado coincide con el del
    guiado: el mismo número de puntos y todos a menos de 1 m. Cada cruce
    lleva su posición a lo largo de la ruta (de su `geometry_index`); solo
    cuentan los que caen por delante de la moto dentro del tramo de `TRAZO`
    (así no salen los ya pasados ni los de otra pasada por la misma calle) y a
    menos de 5 m de él, los más cercanos primero, hasta 35 calles o lo que
    quepa en la conexión.
  - **Texto junto a la flecha** (a petición del autor: «solo icono y calle /
    avenida / salida»): ya no la frase de la instrucción, que con calles sin
    nombre es «Gire a la derecha…», sino `Flechas.nombre`: la vía a la que se
    entra (el nombre del paso siguiente), «Salida 2» en rotondas, «Salida 23»
    en salidas numeradas y «Destino» al llegar; sin nombre, nada. Igual en el
    cartel del iPhone.
  - Pestaña Placa: filas de `NAV` y `CRUCES`. En el registro solo van
    secuencias, longitudes y el número de calles.
- **Supuestos, a ajustar en la moto:**
  - la tolerancia de 5 m de los cruces;
  - un código de maniobra desconocido se lee como 0;
  - sin tramo, los flags de `TRAZO` van a cero, sin escala.
- **Revisión** (workflow: tres implementadores y tres revisores, con un
  escéptico por hallazgo): nada grave; uno de gravedad media en el cuadro (la
  fila de la llegada perdía los km en viajes de más de una hora) y varios
  menores, corregidos (los cruces, el ritmo de `NAV`, la escala sin tramo, la
  llegada). Sin probar en el iPhone ni en la placa.
- **Panel de rutas** (a petición del autor, con vistas previas):
  - sin destino, el panel solo lleva la fila de botones (y la barra del
    tiempo, si se abre) y el mapa ocupa el resto; con destino, se despliega
    hacia arriba con las rutas, al 45 %;
  - si la de más curvas coincide con la más rápida, su tarjeta sale igual,
    apagada: «No hay coincidencia con +25 % de tiempo extra», en vez de una
    tarjeta grande sola.
- **0.10.1, km de autopista, peaje y sin asfaltar tramo a tramo** (a
  petición del autor, 2026-10-09):
  - El autor lo detectó con Segovia → Ávila → Talavera de la Reina, donde solo
    hay unos 10 km de autovía y la app daba 50.
  - Lo comprobé con Valhalla el mismo día. Por maniobras salían 44,3 km: la
    maniobra «Manténgase a la derecha para tomar la SG-20» mide 33,4 km,
    porque sigue unos 28 km por la N-110 sin indicación nueva, y se marca y se
    cuenta entera. Tramo a tramo (`/trace_attributes`), 10,2 km: SG-20 3,5 y
    AV-20 6,8.
  - La N-110 y la N-502 están en OpenStreetMap como `trunk` (nacionales), no
    como autopista: está bien que no cuenten.
  - **Ahora:** al proponer las rutas, la app pide para cada una que se ve sus
    atributos tramo a tramo (`ClienteValhalla.detalleVias`, `walk_or_snap`;
    con `edge_walk` la misma ruta fallaba). Suma autopista sin enlaces, peaje y
    sin asfaltar (LPRCore, `Atributos.swift`, con pruebas).
  - Son dos peticiones más por búsqueda, al mismo ritmo de una por segundo:
    los avisos salen un momento después que las rutas. Por debajo de 100 m no
    se avisa. Si la petición falla, se usan los de las maniobras con «hasta».
  - La elección de rutas no cambia: sigue con los datos de las maniobras.
- **0.11.0** (2026-10-09):
  - **GPS en el cuadro** (protocolo v0.7, a petición del autor). Un punto de
    color junto a «GPS», abajo en la franja negra; sin GPS, una alerta roja.
    - iOS no da los satélites: la calidad es la precisión horizontal. La app
      manda la característica `GPS` (§6, definida desde la v0.1), sin la
      posición.
    - Umbrales (supuestos): 10 y 30 m.
  - **Segunda revisión de la integración** (workflow con un escéptico por
    hallazgo):
    - Junto a la flecha salen otra vez las carreteras que solo tienen número
      (M-510, N-6). Ferrostar no da el `ref` de los pasos, así que sale de la
      respuesta OSRM (`RutaConCruces.vias`): «A-6, Autovía del Noroeste».
    - Dentro de la rotonda ya no se pierde «Salida N»: el número va en el paso
      actual.
    - La ventana de los cruces tiene 50 m de holgura por detrás.
    - Si la de más curvas es la más rápida pero hay otras dentro del margen,
      la tarjeta vacía dice «La más rápida es también la de más curvas».
- **Velocidad máxima de cada vía: de momento no** (decisión del autor,
  2026-10-09).
  - Lo comprobado: Ferrostar 0.57.0 ya la pide a Valhalla en cada ruta
    (`shape_attributes.speed_limit`) y la ofrece durante el guiado
    (`AnnotationPublisher.valhallaExtendedOSRM`). Sale de la etiqueta
    `maxspeed` de OpenStreetMap.
  - En Segovia → Ávila → Talavera, 110 de 187 km (59 %) tenían límite
    conocido; el resto, desconocido.
  - Si se retoma: decidir qué hacer con los tramos sin dato, y añadir un campo
    a `NAV` para el cuadro.
- **Cuadro:** se hace en su proyecto (el código no entra en este
  repositorio): `docs/CAMBIOS_CLAUDE.md`, sección 76.

### 2026-10-09 · Calles sin rayas dobles y rotondas enteras (0.12.0)

- **Petición del autor:** en la cara de navegación, las calles de todo el
  trayecto, pero sin rayas dobles; y las rotondas, enteras.
- **Causa de las rayas dobles (comprobada el 2026-10-09 con respuestas reales
  de Valhalla en formato OSRM):** en `bearings` viene una calle por cada vía
  de OpenStreetMap del nodo, también las aceras, los pasos de peatones, los
  carriles bici y la otra calzada de las avenidas, y la app las dibujaba
  todas. Las respuestas del estudio no entran en el repositorio (son datos de
  OpenStreetMap, con licencia ODbL, y el repositorio es público): las pruebas
  usan datos inventados.
- **Dos reglas, solo con lo que trae la respuesta** (`entry` de cada calle,
  su rumbo y su posición en la ruta):
  - regla 1, al leer la respuesta: si un cruce tiene dos calles laterales o
    más y por ninguna se puede entrar (`entry` a `false` en todas), se
    quitan (es el patrón de las aceras y los pasos de peatones). Con una sola
    (una calle de un sentido que llega a la ruta) se queda;
  - regla 2, al elegir las calles del tramo y antes de recortar por tamaño:
    de cada grupo de calles casi paralelas, a 30 m o menos a lo largo de la
    ruta y a 30° o menos de rumbo, se queda una, la primera por la que se
    puede entrar o, si no hay, la primera. El grupo se ancla en la primera
    que queda (no se encadenan).
  - Con 3 rutas reales (Madrid y Segovia), de 151, 142 y 122 calles se pasa
    a 78, 78 y 68. Se quedan el 95 % de las calles por las que se puede
    entrar, el 80 % de las de un sentido que llegan a la ruta y el 7 % de las
    peatonales, y no queda ninguna pareja doble. Para saber qué era cada
    calle se usaron los atributos de `/trace_attributes`; las reglas no los
    usan.
- **Rotondas enteras (protocolo v0.8):**
  - En la ruta solo viene el arco que se recorre. La app le ajusta un
    círculo (Kåsa como inicio y después Gauss-Newton geométrico amortiguado,
    como mucho 50 iteraciones). Comprobado: en 11 de 12 rotondas el círculo
    del arco coincide con el anillo de OpenStreetMap a menos de 1 m; en 41 de
    54 rotondas de 4 rutas pasa la regla de aceptación (5 puntos o más, 40° o
    más de giro, error cuadrático medio de 0,07 m o menos y radio de 5 a
    80 m).
  - Con un cuadro que dibuja los anillos, en los cruces de cada rotonda con
    anillo (los de su paso y el primero del siguiente) se quitan las calles
    que forman más de 90° con la radial hacia fuera: son el propio anillo
    (acertó en 91 de 92). Y los brazos con isleta (una calzada de salida
    seguida de una de entrada, a 90° o menos vistas desde el centro, que se
    cortan por fuera a menos de 100 m o son casi paralelas, menos de 15°, y a
    menos de 30 m) quedan en una calle, en el anillo a medio camino y con el
    rumbo medio.
  - `CRUCES` lleva tras las calles un bloque opcional con hasta 4 anillos
    (centro y radio) y el bit 9 de capacidades dice que el cuadro los dibuja
    (`PROTOCOLO.md` §7 quater). Sin pasar de 179 bytes: con anillos caben
    menos calles (con 4, 30). La app solo manda el bloque al cuadro que
    anuncia el bit 9.
  - Van los anillos que la ruta empieza a recorrer dentro de la ventana del
    tramo y los que ha dejado hace 20 m o menos (por detrás de la ventana),
    para que no desaparezcan dentro de la rotonda; en el orden de la ruta,
    como mucho 4.
- **La app 0.12.0 necesita el firmware del cuadro 0.4.0 para ver los
  anillos** (capacidades 0x03EF). Con un cuadro anterior, las reglas 1 y 2
  valen igual, pero las rotondas se dibujan como hasta ahora (con las calles
  del anillo y sin el bloque).
- **Supuestos, a ajustar en la moto:** los umbrales de las dos reglas (2
  calles; 30 m y 30°), los de aceptación del círculo, los de las rotondas
  (90°; 100 m; 15° y 30 m) y los 20 m por detrás de la ventana. Salen de
  pocas rutas, todas de Madrid y Segovia.
- **Decisiones de la implementación:**
  - los cruces para un cuadro con anillos se calculan una vez, al leer la
    respuesta (`RutaConCruces.crucesConAnillos`), y la app elige la lista
    según el cuadro conectado;
  - un cruce que fuera de dos rotondas seguidas se queda en la primera;
  - la calle de un brazo con isleta va en el anillo, a medio camino entre
    los dos cruces (como en el algoritmo del estudio), con el recorrido del
    primero.
- **Sin probar:** sin compilar en local (no hay Swift en Windows); las
  pruebas de `Core` corren en el CI. Sin probar en el iPhone ni en la moto.
- **0.12.1, tres arreglos de una revisión de la 0.12.0** (2026-10-09; el
  protocolo no cambia):
  - **Regla 2 una vez por ruta.** En la 0.12.0 se aplicaba tramo a tramo,
    después de quitar las calles que quedan detrás de la moto: al pasar la
    moto el ancla de un grupo, el grupo se rehacía y calles que seguían por
    delante aparecían y desaparecían (según la revisión, en las 3 rutas se
    llegaban a ver 83, 90 y 77 calles distintas en vez de 78, 78 y 68). Ahora
    se aplica al crear la ruta, por el recorrido de cada cruce (como el
    estudio), a los cruces de los dos cuadros (en el de anillos, después de
    las rotondas), y `Cruces.calles` solo elige y recorta. Los cruces sin
    recorrido se quedan como están y ya no se juntan en ningún sitio: Valhalla
    da `geometry_index` en las 840 intersecciones de las 6 respuestas del
    estudio, y sin él el cruce ya escapa a la ventana. Comprobado con un port
    a node de la lógica nueva y las 3 rutas: 78, 78 y 68 calles, y, con la
    moto avanzando de 2 en 2 m, ninguna calle de delante aparece ni
    desaparece.
  - **Paso b de las rotondas, que faltaba.** En los cruces de una rotonda con
    anillo, las calles de un mismo cruce a menos de 30° quedan en una, con el
    rumbo medio, antes de buscar los brazos con isleta (como
    `anillo/propuesta.js`). Por la que se puede entrar si se puede por
    alguna; el estudio dejaba la de la primera (supuesto: en el único caso
    real, las dos eran de entrar). En las 6 rutas solo junta una pareja:
    Cuatro Caminos, 229° y 251° → 240°.
  - **Sin anillo, con sus calles.** El mensaje lleva como mucho 4 anillos;
    si hay más en la ventana, las rotondas que no caben se dibujaban sin
    anillo y sin las calles del anillo. Ahora solo van sin ellas las rotondas
    cuyo anillo va en el mensaje (`Cruces.anillosConIndices`); en las demás,
    como para un cuadro sin anillos. Según la revisión, no pasa en 6 rutas
    reales, pero es posible.
    - La app guarda esos cruces mientras no cambian los anillos del mensaje.
      Rehacerlos es poco: en el port a node, menos de 2 ms por ruta (la mayor,
      316 calles); en el iPhone, sin medir.
  - **Sin probar:** sin compilar en local; las pruebas nuevas corren en el
    CI. Sin probar en el iPhone ni en la moto.

### 2026-10-09 · Trazo con movimiento, fase 1 de la suavidad (0.13.0)

- **Petición del autor:** el dibujo del cuadro «se siente a trompicones»:
  cambia una vez por segundo, con cada `TRAZO`.
- **Fase 1 (protocolo v0.9, `PROTOCOLO.md` §7 ter, «Con movimiento»):** el
  cuadro mueve él solo la moto por el tramo entre un mensaje y otro y corrige
  poco a poco al llegar el siguiente; para eso la app le dice dónde va la moto
  en la ruta y le da tramo de sobra. La fase 2 (la ruta entera en el cuadro)
  vendrá aparte.
- **Qué hace la app, solo con un cuadro que anuncia el bit 10 de
  capacidades** (si no, el `TRAZO` de siempre):
  - manda `TRAZO` con el bit 3 de los flags: el recorrido de la moto (metros
    de ruta desde su inicio, en decímetros, `u32`), cuántos puntos van detrás
    y la lista entera (detrás, la moto y delante); el giro cuenta los de
    detrás;
  - por delante, los metros del nivel de escala (1,25 veces) más 100 m;
  - por detrás, hasta 150 m de la ruta ya hecha, como mucho 10 puntos,
    simplificados como los de delante y en los mismos ejes (la moto en el
    origen y el sentido de la marcha hacia arriba);
  - como mucho 42 puntos y lo que admita la conexión (9 bytes de cabecera);
    los de delante tienen prioridad: si no cabe todo, los de detrás se
    simplifican más y, si aún no caben, se quedan los más cercanos;
  - `CRUCES` no cambia: las calles y los anillos van en los mismos ejes (la
    moto en el origen). La ventana en la que se buscan llega hasta el final
    del tramo que se manda, así que con movimiento llega 100 m más lejos.
- **De dónde sale lo ya hecho.** Ferrostar solo da los pasos que quedan. Los
  hechos salen de su ruta (`FerrostarCore.route`), que, según su código de la
  0.57.0 (consultado el 2026-10-09), cambia sola al recalcular si no hay
  delegado (la app no lo usa). Son los primeros de la ruta, por número (como
  la vía siguiente); la app comprueba que el paso actual de la ruta coincide
  con el primero de los que quedan y, si no (por ejemplo, justo al cambiar de
  ruta), manda ese `TRAZO` en el formato de siempre.
- **Recorrido:** la suma de las distancias de los pasos hechos más lo hecho
  del actual (su distancia menos lo que falta para la maniobra, entre 0 y su
  distancia). Viene a ser la longitud de la ruta menos lo que falta
  (`distanceRemaining`), sin mezclar la longitud de la ruta con la de los
  pasos. Con una ruta nueva o recalculada vuelve a empezar, porque es otra
  ruta.
- **La app 0.13.0 necesita el firmware del cuadro 0.5.0, con el bit 10
  (capacidades 0x07EF), para el movimiento.** Con un cuadro anterior, todo
  como en la 0.12.1. La pestaña Placa enseña si la placa lo admite
  («Movimiento suave»).
- **Supuestos de la implementación:**
  - sin tramo se manda el `TRAZO` sin tramo de siempre, de 4 bytes (`01 ss 00
    FF`), también a un cuadro con movimiento: lo entiende cualquiera;
  - al leer (las pruebas, y como referencia para el cuadro), un `atrás` de
    más de 10 o que deja la moto fuera de los puntos llegados se lee como sin
    tramo;
  - el recorrido no tiene valor de desconocido en el protocolo: se satura en
    `FF FF FF FF` y lo que no es finito va como 0;
  - que el recorrido de Ferrostar y la distancia a lo largo de los puntos
    casan lo bastante para que el cuadro corrija sin saltos: Ferrostar mide
    lo que falta del paso con otra fórmula (Haversine), y la diferencia con la
    proyección local de la app es del orden de un 0,1 % (sin medir en ruta).
- **Sin probar:** sin compilar en local (no hay Swift en Windows); las
  pruebas de `Core` corren en el CI. Sin probar en el iPhone ni en la moto, y
  sin un cuadro con el firmware 0.5.0.
- **Cuadro:** se hace en su proyecto (el código no entra en este
  repositorio).

### 2026-10-09 · Solo carreteras en los cruces y resumen del viaje (0.14.0)

- **Peticiones del autor (protocolo v0.10, `PROTOCOLO.md` §5, §7 quater y
  §13):** en la cara de navegación, «solo quiero carreteras»; y, al terminar
  la ruta, el tiempo de trayecto, los km totales y la velocidad media.
- **Solo carreteras en `CRUCES`.** La app ya pedía `/trace_attributes` de
  cada ruta propuesta para los km de autopista, peaje y tierra. Ahora la
  misma petición trae también el índice del trazado en que acaba cada arista
  (`edge.end_shape_index`) y, de su nodo final, el rumbo y el uso de las
  aristas que lo cruzan (`node.intersecting_edge.begin_heading` y `.use`).
  - Cada calle lateral de un cruce se casa con la arista del mismo nodo (el
    del `geometry_index` del cruce) de rumbo más parecido, si está a 4° o
    menos (como en el estudio de las rayas dobles). Se quedan las de `use`
    road, ramp, turn_channel, living_street, service_road y culdesac; fuera,
    garajes, pasillos de aparcamiento, callejones, pistas, caminos, carriles
    bici, aceras, pasos de peatones, escaleras y similares. Una calle que no
    casa con ninguna arista, o que casa con una sin uso, se queda; sin
    atributos, todo como en la 0.13.0.
  - El filtro va antes de las reglas 1 y 2 y de las rotondas. Para eso la
    regla 1 pasa de la lectura de la respuesta a `RutaConCruces` (con los
    mismos cruces de entrada, el resultado sin atributos es el mismo): así,
    de una calle de un sentido que llega a la ruta junto a una acera, las
    dos sin entrada, queda la calle en vez de ninguna.
  - Contado el 2026-10-09 con las 3 rutas del estudio (un port a node, en el
    directorio temporal; los datos de OpenStreetMap no entran en el
    repositorio): todas las calles laterales casan con una arista (142, 151 y
    122). Con el filtro y las reglas 1 y 2 quedan 76, 72 y 57 calles (con
    solo las reglas, 78, 78 y 68), todas de carretera; sin el filtro se
    colaban aceras, pasos de peatones, garajes, pasillos de aparcamiento,
    callejones y pistas.
  - **Cuándo.** Al empezar, con los atributos de la ruta propuesta del mismo
    trazado (mismo número de puntos, todos a menos de 1 m); si aún no han
    llegado, al llegar. Tras un recálculo (una ruta de Ferrostar que no es
    ninguna de las propuestas), la app pide `/trace_attributes` de la ruta
    nueva, con el mismo cliente y respetando el ritmo del servidor, y aplica
    el filtro cuando llega. Una sola petición por ruta: si falla, no se
    repite, y si falló la de la ruta propuesta, tampoco se pide otra. Hasta
    entonces, los cruces van como en la 0.13.0.
  - **Comprobación de los índices (supuesto).** Con `walk_or_snap`, si el
    recorrido de las aristas falla y Valhalla ajusta la forma al mapa, los
    índices serían de otra forma. La app solo aplica el filtro si la última
    arista acaba en el último punto del trazado (pasa en las 3 rutas del
    estudio); si no, los cruces se quedan como están.
  - Si dos aristas de la ruta acaban en el mismo índice (una de longitud 0),
    cuentan las aristas que cruzan de las dos (supuesto; en el estudio no
    pasa: el estudio se quedaba con las de la última).
  - Para el filtro no hace falta nada en el cuadro.
- **Resumen del viaje en `NAV`.** `NAV` pasa de 17 a 25 bytes: el tiempo de
  viaje en segundos y la distancia recorrida en metros (`u32`,
  `FF FF FF FF` si no se saben), en todos los `NAV` con ruta, también al
  llegar.
  - El tiempo cuenta desde «Iniciar», paradas incluidas; la distancia suma
    las posiciones del GPS consecutivas con una precisión horizontal de 50 m
    o menos, descartando los saltos imposibles (más de 70 m/s desde la última
    posición que contó, o en otro sitio en el mismo instante): la posición
    descartada no cuenta y la siguiente se mide desde la última buena. Los
    recálculos no lo reinician. Con la simulación, la distancia sale de las
    posiciones del simulador (las que ve Ferrostar), con la hora de cada
    estado; el GPS de verdad, en cambio, no se mueve.
  - Al llegar, el tiempo y la distancia se paran (decisión de la
    implementación: es el resumen del trayecto, no sigue contando mientras
    no se pulsa «Terminar»).
  - Si la conexión no admite 25 bytes, `NAV` sale con los 17 de la v0.6
    (`PROTOCOLO.md` §2). Para no mandar `NAV` cada segundo por el tiempo de
    viaje, que cambia cada segundo, el cambio se mira sin el resumen: el
    resumen va con la repetición (cada 1,5-2 s) y, al llegar, con el cambio
    de las banderas.
  - En la app, al llegar, la fila de abajo del guiado enseña «Recorrido»,
    «Tiempo» y «Media» (km/h) en vez de lo que queda y la altitud.
  - **El cuadro necesita un firmware que lea los campos de la v0.10 para
    enseñar el resumen.** Uno anterior los ignora (§3), siempre que acepte
    una escritura de 25 bytes en `NAV`: hasta la v0.9 la tabla de §2 decía
    20 bytes como máximo; sin comprobar en el cuadro.
- **Riesgos sin medir:** parado, el ruido del GPS suma metros (no se filtra
  más que por la precisión; Core Location sin `distanceFilter`); los
  umbrales de 50 m y 70 m/s son supuestos.
- **Sin probar:** sin compilar en local (no hay Swift en Windows); las
  pruebas de `Core` corren en el CI. Sin probar en el iPhone ni en la moto,
  sin una petición real con los atributos nuevos desde la app (sí con el
  estudio, que pedía los mismos y más) y sin un cuadro con el firmware
  nuevo.

### 2026-10-09 · «Y luego» en `NAV` (0.15.0)

- **Petición del autor (protocolo v0.11, `PROTOCOLO.md` §5 y §13):** no
  perder la segunda de dos giros seguidos. El cuadro enseña en pequeño,
  junto a la flecha grande, la maniobra que va después de la siguiente
  cuando las dos están a 150 m o menos (supuesto a ajustar).
- **`NAV` pasa de 25 a 31 bytes:** maniobra y modificador (`u8`), ángulo
  (`i16`) y distancia entre la siguiente maniobra y esa (`u16`), con los
  mismos códigos, ángulos y saturaciones que la siguiente. Sin maniobra
  luego: `00 00 FF 7F FF FF`. La app manda lo que quepa en lo que admita la
  conexión: 31, 25 o 17 bytes (§2).
- **De dónde sale.** Cada paso de Ferrostar trae las instrucciones de la
  maniobra del final del paso: la siguiente maniobra es la del final del
  paso actual (la instrucción que elige Ferrostar, como hasta ahora) y la de
  luego, la del final del paso siguiente. Comprobado el 2026-10-09 con una
  respuesta OSRM de Valhalla de los estudios (no entra en el repositorio):
  las instrucciones de cada paso describen la maniobra con la que empieza el
  siguiente, y el último paso, el de la llegada, mide 0 m y no trae ninguna.
  - De ese paso, la primera instrucción: la que se enseñaría al empezarlo
    (supuesto: las de un mismo paso describen la misma maniobra).
  - Las mismas reglas que la siguiente (`Flechas`): código, ángulo nominal,
    número de salida de la rotonda (del paso de después o, al salir de la
    rotonda, del mismo; la regla está ahora en `Flechas.salidaRotonda` y la
    usan las dos) y lado de la circulación. Si ese paso acaba en el
    destino, llegada (código 5).
  - La distancia es la longitud de ese paso (`RouteStep.distance`, la de
    Valhalla), en metros.
  - Sin maniobra luego (código 0 y lo demás desconocido): si no hay paso
    siguiente o no trae instrucción, si la de luego sale con código
    desconocido y, por decisión de la implementación, si la siguiente es
    desconocida o la llegada (después del destino no hay nada). Al llegar,
    tampoco.
  - La app la manda siempre que la haya; el umbral de 150 m lo aplica el
    cuadro.
- **Ritmo.** El enlace mira si `NAV` ha cambiado con los 31 bytes sin el
  resumen del viaje (`MensajeNav.codificarSinResumen`): el «y luego» cuenta,
  pero solo cambia al cambiar de paso, con la siguiente maniobra, así que
  `NAV` no sale cada segundo por él.
- **El cuadro necesita un firmware con el «y luego» para enseñarlo.** Uno
  anterior lo ignora (§3), siempre que acepte una escritura de 31 bytes en
  `NAV`; sin comprobar en el cuadro.
- **Sin probar:** sin compilar en local (no hay Swift en Windows); las
  pruebas de `Core` (codificación, decodificación y recorte a 25 y 17
  bytes) corren en el CI. La elección de la maniobra luego está en la app
  (usa los tipos de Ferrostar) y no tiene prueba automática. Sin probar en
  el iPhone ni en la moto, y sin un cuadro con el firmware nuevo.
- **Cuadro:** se hace en su proyecto (el código no entra en este
  repositorio).

### 2026-10-09 · Navegación: servidores, buscador y Ferrostar

- **Origen:** el autor propuso usar lo mismo que la web
  valhalla.openstreetmap.de. Es [valhalla/web-app](https://github.com/valhalla/web-app)
  (MIT); según su código (commit `439ea98`, revisado el 2026-10-09):
  - rutas del servidor Valhalla de FOSSGIS, `valhalla1.openstreetmap.de`, con la
    cabecera `X-Client-Id`;
  - búsqueda con Nominatim (`nominatim.openstreetmap.org/search`), al pulsar y no
    mientras se escribe.
- **Decisión:** la app usa los mismos dos servidores, con las direcciones
  configurables en Ajustes.
  - Rutas: perfil `motorcycle` (en beta), `use_tolls: 0` e instrucciones `es-ES`,
    los mismos parámetros que el enlace del autor.
  - Cada petición se identifica con `User-Agent` y `X-Client-Id`.
- **Condiciones** (orientativo; si llega a producto, debe revisarlo una persona):
  - FOSSGIS: uso razonable, como mucho una petición por segundo; no sirve como
    servicio de un producto [F20].
  - Nominatim, según su política [F32]: como mucho una petición por segundo para
    toda la app; prohibido autocompletar; identificar la app; atribución «©
    OpenStreetMap»; poder dejar de usarlo sin actualizar la app (por eso la
    dirección es configurable).
- **Privacidad:** el texto buscado, el punto de salida y el destino llegan a esos
  servidores y pueden quedar en sus registros. La alternativa, si algún día
  molesta, es un Valhalla propio.
- **Ferrostar 0.57.0**, versión fija (antes de la 1.0 su API cambia a menudo):
  - solo el producto `FerrostarCore`, sin mapa y con la voz silenciada;
  - proveedor de ubicación propio, con `pausesLocationUpdatesAutomatically =
    false` y la altitud del GPS;
  - configuración de avance de pasos y desvío de ruta tomada de la app de
    demostración de Ferrostar.

### 2026-10-08 · Nombre: «LPR Gauge»

- La app se llama «LPR Gauge», y el firmware de referencia se anuncia por
  Bluetooth con ese mismo nombre (antes, «CL500», como el cuadro).
- Se valoraron otros nombres más claros en español (LPR Manillar, LPR Driver…); el
  autor se queda con «LPR Gauge».
- El nombre visible se puede cambiar cuando se quiera sin tocar el *bundle ID*.
  Si llega a ser un producto, habrá que comprobar las marcas registradas
  (orientativo; debe revisarlo una persona).
- Cambiar el nombre Bluetooth del cuadro corresponde al proyecto del cuadro.

### 2026-10-08 · Firmware de referencia

- En la placa del propio cuadro (ESP32-S3), con un sketch aparte. Mientras está
  cargado, el cuadro no funciona y después hay que volver a cargar su sketch.
- Librería BLE: la del core arduino-esp32, la misma que usa el cuadro. En el
  ESP32-S3 va sobre NimBLE; en el ESP32 clásico, sobre Bluedroid
  (comprobado en el `sdkconfig` del core 3.3.8 instalado, 2026-10-08).
- **Probado en la placa (2026-10-08, según el autor):** el sketch
  `firmware/referencia_esp32` compila en el IDE de Arduino. Con LightBlue en el
  iPhone y el valor de prueba `01 07 02 55` escrito a mano:
  - la placa se anuncia como «LPR Gauge»;
  - conecta, cifra el enlace y envía *Service Changed*;
  - acepta y quita la suscripción a `STATUS`;
  - descodifica `MOVIL` («seq 7: batería cargando, 85 %»);
  - marca el dato como caducado a los 5 s sin mensajes.
- **Probado con la app 0.2.1 (2026-10-08, según el autor):** la app conecta con
  la placa, manda `MOVIL` cada 2 s y recibe el eco en `STATUS` con la misma
  secuencia. Latencia de ida y vuelta: unos 50 ms.
- **Sin explicar:** en un intento anterior, probablemente aún con el sketch
  previo, la app se quedó en «Cola de envío llena» (`canSendWriteWithoutResponse`
  a `false`) sin llegar a enviar. Si se repite, la salida prevista es escribir
  igualmente: según Apple, el mensaje solo se puede perder, y se repite cada 2 s.
- **Reconexión con el sketch actual (2026-10-08, registro de serie del autor):**
  - el iPhone ya emparejado conecta y cifra;
  - la placa indica *Service Changed* y la app se vuelve a preparar sola;
  - la suscripción a `STATUS` llega y `MOVIL` entra con las secuencias 0, 1… cada
    2 s;
  - ya no salta la caducidad falsa tras el primer mensaje.
- Pendiente: el cambio de carga al enchufar y desenchufar.
- **Monitor serie:** solo muestra algo si el puerto USB y la opción «USB CDC On
  Boot» casan (CH343 con Disabled; USB nativo con Enabled), como ya pasó en el
  cuadro.

## Privacidad

- Los registros de ruta (posiciones con hora) son datos personales. La app los
  exporta fuera del repositorio y `.gitignore` los excluye desde el primer commit.
- Ninguna posición real, salida de `idevicesyslog` ni informe de fallo va al
  repositorio, a issues, a los registros de CI ni a sus artefactos.
- Los datos de prueba usan coordenadas inventadas.

## Instalación en el iPhone

### 2026-10-08 · Apple ID gratuito, firmando con Sideloadly desde Windows

- **Límites de la cuenta gratuita** [F4]: los perfiles caducan a los 7 días; como
  máximo 3 apps por dispositivo, 3 dispositivos y 10 App IDs cada 7 días. Por eso
  hay un *bundle ID* fijo desde el primer día y ninguna extensión sin necesidad.
- **Segundo plano:** la cuenta gratuita admite la capacidad *Background modes*
  [F5]. `UIBackgroundModes` (`location`, `bluetooth-central`) es una clave del
  Info.plist, no un entitlement [F6].
- **Sideloadly:** hace falta la v0.70.1 o posterior, que corrige el inicio de
  sesión tras los cambios de Apple de septiembre de 2026 [F7]. En Windows exige
  iTunes e iCloud descargados de apple.com, no los de la Microsoft Store [F8].
- **Riesgo conocido:** desde agosto-septiembre de 2026 algunas cuentas gratuitas
  reciben el error 0xe8008024 («provisioning profile is banned»). AltStore lo
  reconoció el 2026-09-21 y recomienda usar un Apple ID secundario; la causa no
  se conoce [F9].
- **Apple ID:** se firma con un Apple ID secundario del autor, no con el principal
  (2026-10-08).
- **Cuenta de pago:** se decidirá después de la prueba de concepto. Nada de la
  prueba la necesita.

## Compilación

### 2026-10-08 · GitHub Actions con runners estándar

- Gratuitos e ilimitados en repositorios públicos; los *larger* (`-large`,
  `-xlarge`) se cobran siempre [F1]. Comprobado el 2026-10-08, antes del primer
  push.
- El SDK de iOS 27 solo está en la imagen `xcode-27`, en vista previa (puede haber
  colas y no tiene garantía). `macos-26` trae Xcode 26.6 con el SDK de iOS 26.5
  [F10]. La imagen se elige al crear el workflow.
- En un repositorio público, cualquier usuario con sesión en GitHub puede
  descargar los artefactos del workflow [F11]. El `.ipa` se guarda solo 7 días.

### 2026-10-08 · Fase 0: la app mínima

- **Estructura:** `Core/` es un paquete Swift sin frameworks de Apple, con el
  protocolo y sus pruebas. `App/` es la app SwiftUI. `project.yml` define el
  proyecto para XcodeGen, que lo genera en CI.
- ***Bundle ID* fijo:** `io.github.luispr99.lprgauge`. El nombre visible es «LPR
  Gauge».
- **Runner `macos-26` con Xcode 26.6 fijado** (SDK de iOS 26.5), no `xcode-27`.
  Motivo: `xcode-27` está en vista previa, con posibles colas y sin garantía
  [F10]. Que la app compilada con el SDK 26.5 funcione en iOS 27 es lo primero
  que se prueba en el iPhone.
- **Modo de lenguaje Swift 5** de momento. Sin compilador en el PC, cada error
  cuesta una vuelta por CI, y el modo Swift 6 da más avisos de concurrencia con
  Core Bluetooth. Se puede subir más adelante.
- **Pruebas de `Core`:** se ejecutan en CI (macOS). En Windows no hay Swift
  instalado; el workflow de Windows queda para más adelante.
- **Primera compilación en CI, correcta** (2026-10-08, ejecución 37831961338 del
  workflow `iOS`). Usó Xcode 26.6 (17F113), Swift 6.3.3 y el SDK de iOS 26.5;
  pasaron las 3 pruebas de `Core`. El `.ipa` sin firmar lleva el *bundle ID*
  fijo, `MinimumOSVersion` 17.0 y la versión 0.1.0.
- **Fase 0 terminada (2026-10-08).** La app compilada en CI con el SDK de iOS 26.5
  se instaló con Sideloadly y Apple ID secundario y se abre en el iPhone con iOS
  27, según el autor. Hizo falta confiar en el desarrollador (Ajustes > General >
  VPN y gestión de dispositivos) y activar el Modo desarrollador.

## Rutas y flechas: lo comprobado

Comprobado el 2026-10-08:

- **Apple Maps:**
  - `MKRoute.Step` da el texto de la instrucción (en el idioma del iPhone), la
    distancia del paso y su trazado. No hay ningún tipo de maniobra [F16].
  - No da guía en vivo: la cuenta atrás de metros, el paso a la siguiente
    instrucción y el recálculo los tiene que hacer la app. Los límites de uso no
    se publican (error `loadingThrottled`) [F16].
  - Falta probar que `MKDirections` responda en una app firmada con Apple ID
    gratuito: la nota de Apple al respecto es ambigua [F5].
  - Condiciones (orientativo; debe revisarlo una persona): para uso personal
    parece encajar. Para un producto, los acuerdos de Apple limitan el uso de sus
    datos de mapas fuera de la app y sin su mapa [F17].
- **Google Routes API:** da el tipo de maniobra, pero exige una cuenta de
  facturación con método de pago aunque no se supere el uso gratuito [F18]. Choca
  con «nada de pago, sin cuenta obligatoria».
- **Valhalla con Ferrostar:**
  - Valhalla (MIT) da el tipo de maniobra, tiene un modo moto (en beta) e
    instrucciones en español.
  - Ferrostar (BSD-3) hace el guiado en iOS y en Android [F19].
  - El servidor público de FOSSGIS admite un uso razonable, como mucho una
    petición por segundo [F20]. Para un producto haría falta un servidor propio.

## Tecnología: lo comprobado

Opciones estudiadas: React Native, Flutter, Kotlin Multiplatform y dos apps
nativas. Comprobado el 2026-10-08:

- React Native permite llamar a las API de Apple con módulos nativos en Swift
  (Expo Modules API, licencia MIT) [F14].
- React Native no tiene ningún mecanismo oficial para ejecutar JavaScript en
  segundo plano en iOS: Headless JS es solo de Android [F15]. Con React Native, lo
  que tiene que funcionar con la pantalla bloqueada (GPS, cálculo de metros y BLE)
  iría en código nativo de cada sistema, y solo se compartiría la interfaz.
- **Flutter:** también necesita una pieza nativa propia en cada sistema para el
  BLE en segundo plano. Desde la 3.41 usa el ciclo de vida por escenas, y el
  registro de plugins se aplaza hasta después del arranque de la app [F21]. La
  librería BLE más usada, flutter_blue_plus, exige licencia de pago para uso
  comercial y desde junio de 2026 envía datos de la app en cada build de Android
  [F22]: queda descartada.
- **Kotlin Multiplatform (KMP):**
  - Un solo lenguaje, Kotlin, para iOS y Android. KMP y Compose Multiplatform son
    estables en iOS [F23].
  - Desde Kotlin se usan directamente las API de Apple expuestas a Objective-C,
    como Core Bluetooth y Core Location [F24]. Así, la parte que debe funcionar
    con la pantalla bloqueada se puede escribir una sola vez y compilar a código
    nativo, sin depender de JavaScript ni de Dart en segundo plano.
  - Las API solo de Swift no se pueden llamar desde Kotlin [F24]. Ferrostar es una
    de ellas en iOS: se usaría desde Swift, detrás de una interfaz Kotlin.
  - Cada versión de Kotlin va ligada a una de Xcode: Kotlin 2.4.x con Xcode 26.4
    [F25]. Para Xcode 27 habrá que esperar a Kotlin 2.5 (previsto en diciembre de
    2026).
  - VS Code no sirve hoy para KMP: el servidor de lenguaje de Kotlin está en alfa
    y no admite proyectos multiplataforma [F26]. Hace falta IntelliJ IDEA o
    Android Studio.
- **Ferrostar** (navegación) tiene SDK estables para Swift y Kotlin. Para React
  Native no hay paquetes publicados, y para Flutter no hay nada oficial [F27].

## Altitud: lo comprobado

Comprobado el 2026-10-08:

- **Barómetro (altitud absoluta, `CMAltimeter`):**
  - Disponible desde iOS 15 y solo en iPhone 12 o posterior; hay que comprobarlo
    con `isAbsoluteAltitudeAvailable()`.
  - Da metros sobre el nivel del mar y una incertidumbre a 1σ.
  - Exige `NSMotionUsageDescription` y el permiso de Movimiento y forma física
    [F28].
  - Apple no documenta si sigue entregando datos con la app en segundo plano: hay
    que probarlo.
- **GPS (`CLLocation.altitude`):** metros sobre el nivel medio del mar (geoide
  EGM2008). Solo es válido si `verticalAccuracy` es mayor que 0 [F29].
- **Plan:** barómetro si está disponible y autorizado; si no, la altitud del GPS.
  Se envía en metros, con su incertidumbre como precisión vertical.
- **Riesgo para la moto:** `pausesLocationUpdatesAutomatically` vale `true` por
  defecto. Con permiso «Cuando se use», una pausa corta la ubicación hasta volver
  a abrir la app [F30]. El proveedor de ubicación de Ferrostar no la desactiva,
  así que hará falta uno propio.

## Maniobras: lo comprobado

Comprobado el 2026-10-08 en la documentación y en el código de Valhalla y
Ferrostar:

- **Formato:** Ferrostar pide a Valhalla las rutas en formato OSRM [F31]. La app
  recibe cada giro como un **tipo** (16 valores: giro, rotonda, bifurcación,
  incorporación, salida, llegada…) y un **modificador** (8 valores: recto, ligero,
  normal o cerrado a cada lado, y cambio de sentido). En rotondas recibe además el
  número de salida y los grados que se recorren.
- **Ángulo:** Ferrostar no da el ángulo de giro. Habría que calcularlo con la
  geometría de la ruta.
- **Altitud:** Ferrostar no transporta la altitud: la app la lee aparte.
- **Distancia:** la que queda hasta el giro está en
  `state.currentProgress.distanceToNextManeuver`, y el giro en
  `state.currentVisualInstruction.primaryContent`.
- **Pendiente de probar con una ruta real:** según el código, la instrucción del
  paso actual ya describe el próximo giro, y el número de salida de la rotonda va
  en el paso siguiente.

## Pendiente de probar

- Que, tras volver a firmar, la app conserve los modos en segundo plano y siga
  recibiendo GPS y enviando por BLE con la pantalla bloqueada. Probar sesiones
  largas: hay informes de huecos de varios minutos sin posiciones en iOS 27 [F12].
- Reconexión al reiniciar el cuadro. Si el usuario cierra la app deslizándola,
  iOS no la vuelve a lanzar [F13]: en las pruebas no hay que cerrarla así.
- Coexistencia de BLE, WiFi (OBD) y pantalla en la placa del cuadro, con el
  Bluetooth de la app en marcha. Se mide en el proyecto del cuadro.
- Rutas 0.7.0:
  - que al pulsar «Iniciar» la ruta OSRM coincida con la propuesta;
  - que la raya ya no se salga de la carretera;
  - los umbrales de curvas y de tierra (500 m) con rutas conocidas;
  - por qué a veces Valhalla devuelve menos alternativas de las pedidas
    (`alternates` es «como mucho»).
- Cara de navegación 0.10.0:
  - los saltos de escala (1000, 500 y 250 m) y que el giro baje sin que el
    dibujo se acerque;
  - que los cruces caigan sobre las calles, también tras un recálculo;
  - las flechas con rutas reales, sobre todo rotondas y cambios de sentido,
    y la hora de llegada.
- Calles y rotondas 0.12.0 (con el cuadro 0.4.0):
  - que no queden rayas dobles en ciudad ni se pierdan calles por las que se
    puede entrar;
  - que los anillos caigan sobre las rotondas y no desaparezcan dentro;
  - los umbrales de las reglas, del círculo y de los brazos con isleta.

## Fuentes (consultadas el 2026-10-08)

- [F1] GitHub, runners alojados y facturación:
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners ·
  https://docs.github.com/en/billing/concepts/product-billing/github-actions
- [F2] Apple, iPhone compatibles con iOS 17:
  https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-17-iphe3fa5df43/17.0/ios/17.0
- [F3] Apple, disponibilidad de las API:
  https://developer.apple.com/documentation/corelocation/cllocationupdate ·
  https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3 ·
  https://developer.apple.com/documentation/corebluetooth/cbconnectperipheraloptionenableautoreconnect ·
  https://developer.apple.com/documentation/observation
- [F4] Apple, cuenta de desarrollador:
  https://developer.apple.com/help/account/basics/about-your-developer-account
- [F5] Apple, capacidades por tipo de cuenta:
  https://developer.apple.com/help/account/reference/supported-capabilities-ios
- [F6] Apple, modos en segundo plano:
  https://developer.apple.com/documentation/xcode/configuring-background-execution-modes ·
  https://developer.apple.com/forums/thread/787026
- [F7] Sideloadly, changelog: https://sideloadly.io/changelog.html
- [F8] Sideloadly, requisitos: https://sideloadly.io/faq
- [F9] AltStore, aviso del 2026-09-21:
  https://bsky.app/profile/altstore.io/post/3mw2cbeyvn222 ·
  https://github.com/altstoreio/AltStore/issues/1775
- [F10] Imágenes de los runners:
  https://github.com/actions/runner-images ·
  https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md ·
  https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- [F11] GitHub, descarga de artefactos:
  https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts
- [F12] Foro de desarrolladores de Apple (informe de usuario, sin confirmar por
  Apple): https://developer.apple.com/forums/thread/844579
- [F13] Apple, TN3115:
  https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules
- [F14] Módulos nativos: https://docs.expo.dev/modules/overview/ ·
  https://reactnative.dev/docs/native-platform
- [F15] React Native, Headless JS: https://reactnative.dev/docs/headless-js-android
- [F16] Apple, MapKit:
  https://developer.apple.com/documentation/mapkit/mkroute/step ·
  https://developer.apple.com/documentation/mapkit/mkdirections
- [F17] Apple, acuerdos: DPLA, anexo 6,
  https://developer.apple.com/support/terms/apple-developer-program-license-agreement/ ·
  Xcode and Apple SDKs Agreement, §2.11, https://www.apple.com/legal/sla/docs/xcode.pdf
- [F18] Google Routes API:
  https://developers.google.com/maps/documentation/routes/reference/rest/v2/TopLevel/computeRoutes ·
  https://developers.google.com/maps/documentation/routes/usage-and-billing
- [F19] https://github.com/valhalla/valhalla · https://stadiamaps.github.io/ferrostar/
- [F20] FOSSGIS, condiciones de uso de sus servidores:
  https://fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/
- [F21] Flutter, ciclo de vida por escenas:
  https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- [F22] flutter_blue_plus, licencia y aviso de licencia en el build:
  https://raw.githubusercontent.com/chipweinberger/flutter_blue_plus/master/LICENSE.md ·
  https://github.com/chipweinberger/flutter_blue_plus/commit/70f061eb
- [F23] Kotlin Multiplatform, estabilidad por plataforma:
  https://kotlinlang.org/docs/multiplatform/supported-platforms.html
- [F24] Kotlin/Native, interoperabilidad con Objective-C:
  https://kotlinlang.org/docs/native-objc-interop.html
- [F25] Kotlin Multiplatform, compatibilidad de versiones:
  https://kotlinlang.org/docs/multiplatform/multiplatform-compatibility-guide.html
- [F26] Kotlin LSP: https://kotlinlang.org/docs/kotlin-lsp.html
- [F27] Ferrostar, plataformas: https://stadiamaps.github.io/ferrostar/ ·
  https://github.com/stadiamaps/ferrostar/issues/735
- [F28] Apple, Core Motion:
  https://developer.apple.com/documentation/coremotion/cmaltimeter ·
  https://developer.apple.com/documentation/coremotion/cmabsolutealtitudedata
- [F29] Apple, altitud de Core Location:
  https://developer.apple.com/documentation/corelocation/cllocation/altitude ·
  https://developer.apple.com/documentation/corelocation/cllocation/verticalaccuracy
- [F30] Apple:
  https://developer.apple.com/documentation/corelocation/cllocationmanager/pauseslocationupdatesautomatically ·
  Ferrostar, proveedor de ubicación:
  https://github.com/stadiamaps/ferrostar/blob/main/apple/Sources/FerrostarCore/Location.swift
- [F31] Ferrostar, modelo de maniobras y adaptador de Valhalla:
  https://github.com/stadiamaps/ferrostar/blob/main/common/ferrostar/src/models.rs ·
  https://github.com/stadiamaps/ferrostar/blob/main/common/ferrostar/src/routing_adapters/valhalla.rs ·
  Valhalla, referencia de la API: https://valhalla.github.io/valhalla/api/route/api-reference/
- [F32] Política de uso de Nominatim (OSMF):
  https://operations.osmfoundation.org/policies/nominatim/
- [F33] Valhalla, opciones de coste de la moto (rama master, consultada el
  2026-10-09):
  https://github.com/valhalla/valhalla/blob/master/docs/docs/api/route/api-reference.md
- [F34] Ferrostar 0.57.0, lectura de la respuesta (todas las rutas) y petición a
  Valhalla (consultadas el 2026-10-09):
  https://github.com/stadiamaps/ferrostar/blob/0.57.0/common/ferrostar/src/routing_adapters/osrm/mod.rs ·
  https://github.com/stadiamaps/ferrostar/blob/0.57.0/common/ferrostar/src/routing_adapters/valhalla.rs
- [F35] Apple, MapKit (consultado el 2026-10-09):
  https://developer.apple.com/documentation/mapkit/mkroute ·
  https://developer.apple.com/documentation/mapkit/mkroute/hastolls ·
  https://developer.apple.com/documentation/mapkit/mkdirections/request/tollpreference
- [F36] Apple, guía del iPhone, indicaciones en coche (iOS 27, consultada el
  2026-10-09):
  https://support.apple.com/guide/iphone/get-driving-directions-ipha84a94043/ios
- [F37] Valhalla, código fuente (tag 3.9.1, commit bafb699, y master c803bdc;
  consultado el 2026-10-09): src/sif/motorcyclecost.cc, src/sif/autocost.cc,
  src/tyr/route_serializer_osrm.cc, src/tyr/route_serializer_valhalla.cc,
  src/odin/maneuversbuilder.cc, valhalla/baldr/directededge.h,
  src/mjolnir/pbfgraphparser.cc ·
  https://github.com/valhalla/valhalla/tree/bafb69902220615a48307d5c790fb6c943802ba4 ·
  versión del servidor: https://valhalla1.openstreetmap.de/status
- [F38] Apple, trazos (consultado el 2026-10-09):
  https://developer.apple.com/documentation/swiftui/strokestyle ·
  https://developer.apple.com/documentation/mapkit/mkoverlaypathrenderer/linejoin ·
  https://developer.apple.com/documentation/mapkit/mapcontent/stroke(_:style:)
- [F39] SFSafeSymbols 7.0.0 (disponibilidad de SF Symbols, de terceros;
  consultado el 2026-10-09): https://github.com/SFSafeSymbols/SFSafeSymbols
- [F40] Apple, ubicación en segundo plano (consultado el 2026-10-09):
  https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background ·
  https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates ·
  WWDC23 «Discover streamlined location updates»:
  https://developer.apple.com/videos/play/wwdc2023/10180/
- [F42] Foro de desarrolladores de Apple, «iOS Network Signal Strength», Quinn
  (DTS), publicado el 2022-12-01 y revisado el 2026-06-18 (consultado el
  2026-10-09): https://developer.apple.com/forums/thread/721067
- [F43] Apple, `NWPath.LinkQuality` y MetricKit (consultados el 2026-10-09):
  https://developer.apple.com/documentation/network/nwpath/linkquality-swift.enum ·
  https://developer.apple.com/tutorials/data/documentation/metrickit.md
- [F44] Foro de desarrolladores de Apple, lectura de la barra de estado desde
  iOS 16 y entitlements (consultados el 2026-10-09):
  https://developer.apple.com/forums/thread/713035 ·
  https://developer.apple.com/forums/thread/726270 ·
  https://developer.apple.com/forums/thread/3628 ·
  https://developer.apple.com/forums/thread/757494
- [F45] Apple, `serviceCurrentRadioAccessTechnology` (consultado el
  2026-10-09):
  https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology
- [F41] Apple, Core Bluetooth en segundo plano (guía archivada; consultada el
  2026-10-09):
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html

### 2026-10-10 · Carriles en `NAV` (0.16.0)

- **Petición del autor (protocolo v0.12, `PROTOCOLO.md` §5 y §13):** los
  carriles antes de la maniobra, en un recuadro arriba en el mapa (eligió
  esa forma en una vista previa, frente a ponerlos en la franja de abajo).
- **De dónde salen.** Del aviso que se ve (`currentVisualInstruction`): su
  `subContent.laneInfo` de Ferrostar, que viene de los componentes `lane` del
  `sub` de `bannerInstructions` de Valhalla. Comprobado el 2026-10-10 con
  valhalla1.openstreetmap.de, perfil de moto, una ruta de prueba entre dos
  sitios públicos de Madrid por la A-6 (la respuesta no entra en el
  repositorio): de 14 pasos, solo el aviso de la salida de la autovía traía
  carriles, y solo en sus últimos 400 m. Así, el recuadro sale y se quita
  con el aviso, sin umbral propio. Dependen de que los carriles estén
  marcados en OpenStreetMap: muchas maniobras irán sin ellos.
- **`NAV` pasa a 32 + 2n bytes (n de 0 a 8):** número de carriles y, por
  carril, las flechas pintadas y las que valen (un bit por dirección).
  Ferrostar da la dirección activa del carril que vale; si no la da (o no es
  suya), valen todas las del carril (supuesto). Más de 8, recalculando,
  fuera de ruta o al llegar: ninguno.
- **Solo con el bit 11 de capacidades:** sin él, la app manda 31 bytes como
  mucho (`EnlaceBLE.admiteCarriles`). Si los carriles no caben en lo que
  admite la conexión, el byte de carriles va a 0.
- **Ritmo:** los carriles cuentan como cambio de `NAV`
  (`codificarSinResumen` lleva ahora todo); cambian con el aviso.
- **Sin probar:** sin compilar en local (no hay Swift en Windows); las
  pruebas de `Core` corren en el CI. La lectura de `laneInfo` está en la app
  y no tiene prueba automática. Sin probar en el iPhone ni en la moto.
- **Cuadro:** se hace en su proyecto (el código no entra en este
  repositorio).

### 2026-10-10 · Pestaña «Rutas» y distancias desde 950 m (0.17.0)

- **Petición del autor:** «añade una sección en la app que se llame rutas»
  para volver a cargar un destino al que ya se fue, «misma ruta
  preseleccionada y todo. que solo falte darle a iniciar».
- **Qué se guarda (`LPRCore/RutasGuardadas.swift`):** al empezar a guiar (no
  con el simulador), el destino (nombre, descripción y coordenadas), el tipo
  de ruta elegido, las preferencias (evitar peajes, evitar autopistas y el
  margen) y, para la lista, km, tiempo y curvas de la ruta propuesta. La misma
  ruta (destino a 100 m o menos, mismo tipo y preferencias) no se repite: sube
  arriba y cuenta una vez más. Como mucho 30 (supuesto). Se guarda en el
  iPhone (UserDefaults): no sale de él.
- **Al tocar una (`Navegacion.cargar`):** pone esas preferencias (cambian
  también las de la app, como si se tocaran a mano), marca el tipo de ruta,
  pone el destino y calcula las propuestas; la app vuelve a «Navegar» y solo
  falta «Iniciar». No mientras se guía.
- **Límite:** no se guarda el trazado. Las rutas se calculan desde la
  posición de ese momento: desde el mismo sitio, sale la misma ruta (Valhalla
  da lo mismo con los mismos datos y opciones; si el servidor actualiza los
  mapas, puede cambiar); desde otro, la del mismo tipo hasta el mismo destino.
  Repetir exactamente el trazado guardado (con puntos de paso) queda para más
  adelante si hace falta.
- **Distancias:** `Flechas.distancia` da en metros como mucho «950 m»; desde
  975 m, «1,0 km» (antes, de 975 a 999 salía «1000 m»), igual que el cuadro
  (su sección 88).
- **Sin probar:** sin compilar en local; las pruebas de `RutasGuardadas`
  corren en el CI. La pestaña y la carga no tienen prueba automática ni están
  probadas en el iPhone.

### 2026-10-10 · «Rutas»: se guarda al pulsar «Iniciar» (0.17.1)

- **El autor:** «No se guardan las rutas, acabo de simular una y no me sale.
  Deberian guardarse nada mas darle a iniciar, si se selecciona una ruta
  desde la pestaña de rutas entonces lo que hay que hacer es volver a ponerla
  arriba, no duplicarla».
- En la 0.17.0 se guardaba al empezar a guiar y no con el simulador. Ahora se
  guarda al pulsar «Iniciar» (`Navegacion.guardarRuta`), también simulando y
  aunque luego no llegue a empezar.
- La ruta cargada desde la lista se recuerda (`rutaCargada`, su id): al
  iniciarla, esa entrada sube arriba con la fecha nueva y una vez más, aunque
  se haya elegido otro tipo de ruta (`RutasGuardadas.anadir` busca primero
  por id). Se olvida al elegir otro destino o cancelar.

### 2026-10-10 · Rutas desde el cuadro y accesos directos (0.18.0)

- **Peticiones del autor:** sin ruta, que la cara de navegación del cuadro
  tenga «una lista con las ultimas rutas y sea tan sencillo como darle y que
  empiece desde la pantalla», sin cambiar opciones pero con su información;
  solo tres y sin desplazar («haré algo en el futuro»); con el peaje y la
  autovía «como en la app», guardados con la ruta; y en la pestaña «Rutas» una
  sección «Accesos directos» con tres huecos: esos son los del cuadro, y los
  libres se llenan con las más recientes.
- **Protocolo v0.13** (`PROTOCOLO.md` §7 quinquies y §9): `RUTAS` (app →
  cuadro) con las tres y el estado de la orden; la orden (cuadro → app) va en
  los bytes 8-11 de `STATUS`, que la app ya recibe por notificación, para no
  añadir otra suscripción. Bit 12 de capacidades.
- **La app** (`Navegacion.ordenDelCuadro`): con la app en primer plano, carga
  la ruta como desde «Rutas» y pulsa «Iniciar» sola en cuanto hay propuestas;
  contesta «calculando», y al empezar o al no poder. Si no está en primer
  plano, contesta «abre la app»: con el permiso «Mientras se usa la app», el
  guiado en segundo plano se activa en primer plano (`guiadoEnFondo`); la
  opción de mantenerlo activo mientras se está conectado al cuadro queda
  para probar más adelante (gasta batería y se ve el indicador de ubicación).
- **Peaje y autopista:** se guardan con cada ruta (los tramo a tramo si ya
  habían llegado; si no, los de las maniobras); las rutas guardadas antes se
  leen con 0. La lista los enseña como la tarjeta de «Navegar».
- **Accesos directos** (`RutasGuardadas.paraElCuadro`): tres huecos; el
  cuadro enseña los fijados en su orden y, en los libres, las más recientes
  que no sean ya acceso directo. Los fijados no se quitan por viejos al
  pasar de 30.
- **Sin probar:** sin compilar en local; las pruebas de `Core` corren en el
  CI. La pestaña, la orden y el inicio automático no tienen prueba automática
  ni están probados en el iPhone ni con el cuadro.

### 2026-10-10 · «Rutas»: accesos directos a mano y ruta nueva si cambia (0.18.1)

- **El autor:** «Los accesos directos los tienes que configurar desde la app.
  Si no hay nada configurado se cogen los 3 más recientes pero no se agregan
  automaticamente en esa lista, eso lo hace el usuario con un boton al lado
  de la tarjeta» (con vista previa antes de hacerlo); y «cuando elijas una
  ruta y cambies los parametros se considere una ruta nueva».
- La sección «Accesos directos» enseña solo los fijados; los huecos libres,
  «Hueco libre» (en el cuadro se siguen llenando con las más recientes, sin
  añadirlas a la lista). Al lado de cada ruta, un botón: fijar (en el primer
  hueco libre), quitar, o gris con los tres ocupados. Ya no se fija ni se
  quita deslizando; deslizar a la izquierda en «Recientes» sigue borrando.
  La lista sale siempre, también sin rutas (en la 0.18.0, sin rutas solo se
  veía el aviso vacío).
- Una ruta cargada desde «Rutas» e iniciada con otro tipo de ruta, peajes,
  autovías o margen se guarda como nueva (antes subía la misma). Sin cambios,
  sube la misma.

### 2026-10-10 · GPS solo con ruta y prueba de empezar desde el cuadro en segundo plano (0.19.0)

- **El autor:** que tocar una ruta en el cuadro funcione sin abrir la app
  («que de alguna manera el movil despierte la app y se ponga ya con el
  gps») y «que cuando termine una ruta, el gps deje de estar operativo hasta
  que se ponga otra ruta».
- **GPS solo con ruta:** la app ya no enciende el GPS al abrirse. Se enciende
  al calcular rutas (con destino) y espera hasta 10 s a una posición de 30 s
  o menos; se apaga al cancelar, al llegar y al terminar
  (\`ProveedorUbicacion.apagar\`). El mapa de «Navegar» sigue enseñando la
  posición con MapKit mientras está en pantalla (no es el GPS de la app).
- **Desde el cuadro con la app en segundo plano (prueba):** al llegar la
  orden, se pide tiempo a iOS (\`beginBackgroundTask\`), se carga la ruta y se
  intenta arrancar el GPS con \`CLServiceSession\` (iOS 18) y
  \`CLLocationUpdate.liveUpdates\` (iOS 17). Base: respuesta de un ingeniero de
  Apple en los foros de desarrolladores, junio de 2025
  (https://developer.apple.com/forums/thread/787607; no es documentación):
  con las APIs nuevas se puede si la app ha estado en primer plano al menos
  una vez; con \`startUpdatingLocation()\`, no. Si en 10 s no hay posiciones,
  la orden contesta «abre la app». El registro de «Placa» apunta qué pasó.
- **Restauración de estado de Bluetooth:** el gestor central lleva
  identificador de restauración; si iOS cierra la app para liberar memoria,
  la vuelve a abrir cuando la placa escribe. Según los foros, no si el usuario
  la cierra a mano desde el selector de apps.
- **Sin probar** en el iPhone: decide si se hace el flujo completo (recalcular
  y confirmar en el cuadro).
