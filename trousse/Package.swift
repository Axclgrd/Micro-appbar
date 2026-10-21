// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Trousse",
    // macOS 26 : le verre liquide natif (`glassEffect`, `GlassEffectContainer`)
    // n'existe pas avant. C'est la seule app de la famille à monter si haut.
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/PortsKit"),
        .package(path: "../Kits/EveilKit"),
        .package(path: "../Kits/EtagereKit"),
        .package(path: "../Kits/EjecterKit"),
        .package(path: "../Kits/GrabKit"),
        .package(path: "../Kits/BandeKit"),
        .package(path: "../Kits/PurgeKit"),
        .package(path: "../Kits/FanKit"),
        .package(path: "../Kits/FonteKit"),
        .package(path: "../Kits/JaugeKit"),
        .package(path: "../Kits/PauseKit"),
        .package(path: "../Kits/MajKit"),
        .package(path: "../Kits/NuitKit"),
    ],
    targets: [
        .executableTarget(
            name: "TrousseApp",
            dependencies: [
                "Commun", "PortsKit", "EveilKit", "EjecterKit",
                "GrabKit", "BandeKit", "PurgeKit", "FanKit", "EtagereKit",
                "FonteKit", "JaugeKit", "PauseKit", "MajKit", "NuitKit",
            ])
    ]
)
