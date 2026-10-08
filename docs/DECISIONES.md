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
- Android más adelante. El código debe servir para los dos sistemas en todo lo
  posible: la tecnología está [pendiente de decidir](#pendiente-de-decidir).

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
- La altitud.
- Sin GPS, un aviso; nada más por ahora.
- Supuesto, sin confirmar: si se corta la conexión Bluetooth, el cuadro muestra el
  mismo aviso.

### 2026-10-08 · De dónde salen las rutas

- iPhone: Apple Maps (MapKit), sin coste.
- Android: Google, más adelante. Hay que verificar sus condiciones antes de
  empezar (ver [Pendiente de decidir](#pendiente-de-decidir)).

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
  descargar los artefactos del workflow [F11].

## Pendiente de decidir

- **Tecnología para iOS y Android** (React Native, Flutter, Kotlin Multiplatform
  o dos apps nativas). En estudio.
- **Flechas con Apple Maps:** hay que confirmar si `MKRoute.Step` da el tipo de
  maniobra o solo texto. Si solo da texto, las flechas se deducirían de la
  geometría de la ruta y del texto, o se usaría un motor de rutas que dé el tipo
  de giro.
- **Google en Android:** condiciones de uso para guiar en tiempo real y si exige
  cuenta de facturación.
- **Apple ID para firmar:** el principal o uno secundario.
- **Altitud:** del GPS o del barómetro del móvil.

## Pendiente de probar

- Que Sideloadly v0.70.1 instale desde Windows en iOS 27.0.1: no hay ningún
  informe publicado.
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
