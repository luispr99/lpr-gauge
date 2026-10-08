# lpr-gauge

App para el móvil que envía por Bluetooth LE al cuadro de instrumentos de una
moto (un ESP32-S3 con pantalla redonda) la navegación —flecha del siguiente giro
y metros que faltan— y la altitud.

## Estado

Fase 0: app mínima para comprobar la cadena completa (GitHub Actions → `.ipa`
sin firmar → Sideloadly → iPhone). Las decisiones tomadas, sus fuentes y lo que
queda pendiente están en [docs/DECISIONES.md](docs/DECISIONES.md); el protocolo,
en [docs/PROTOCOLO.md](docs/PROTOCOLO.md).

## Estructura

- `Core/`: paquete Swift sin frameworks de Apple, con el protocolo y sus pruebas.
- `App/`: app de iPhone en SwiftUI (iOS 17 o posterior).
- `project.yml`: proyecto de Xcode para XcodeGen; el `.xcodeproj` se genera en CI.

## Plataformas

- iPhone primero, en Swift.
- Android más adelante, en Kotlin, con el mismo protocolo.

## Licencia

Sin licencia: © 2026 lpr, todos los derechos reservados.
