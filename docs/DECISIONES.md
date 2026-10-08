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

### 2026-10-08 · Firmware de referencia

- En la placa del propio cuadro (ESP32-S3), con un sketch aparte. Mientras está
  cargado, el cuadro no funciona y después hay que volver a cargar su sketch.
- Librería BLE: la del core arduino-esp32, la misma que usa el cuadro. En el
  ESP32-S3 va sobre NimBLE; en el ESP32 clásico, sobre Bluedroid
  (comprobado en el `sdkconfig` del core 3.3.8 instalado, 2026-10-08).

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
