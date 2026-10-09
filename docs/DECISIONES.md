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
- **Cuadro:** se hace en su proyecto (el código no entra en este
  repositorio): `docs/CAMBIOS_CLAUDE.md`, sección 76.

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
