// swift-tools-version:5.9
// Lógica sin dependencias de la app: protocolo BLE y lo que no necesite
// frameworks de Apple. Solo usa la biblioteca estándar de Swift, así que
// compila igual para el iPhone, en macOS (CI) y en Windows.
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LPRCore", targets: ["LPRCore"]),
    ],
    targets: [
        .target(name: "LPRCore"),
        .testTarget(name: "LPRCoreTests", dependencies: ["LPRCore"]),
    ]
)
