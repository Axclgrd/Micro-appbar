// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/SMCKit"),
        .package(path: "../Kits/FanKit"),
    ],
    targets: [
        // App menu bar (non privilégiée). Son interface vit dans FanKit, d'où
        // Trousse la tire aussi : il n'y a qu'un seul panneau de ventilateurs.
        .executableTarget(name: "FanControlApp", dependencies: ["Commun", "FanKit"]),
        // Démon root : seul composant autorisé à écrire dans le SMC.
        //
        // Mode langage Swift 5 volontaire : en Swift 6, tout le code top-level
        // d'un `main.swift` est isolé sur le MainActor, ce qui n'a aucun sens
        // pour un démon bâti sur des appels POSIX bloquants (accept/read) et
        // un fil de ré-affirmation. L'état partagé est protégé explicitement
        // par NSLock dans `State`.
        .executableTarget(
            name: "fancontrold",
            dependencies: ["SMCKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
