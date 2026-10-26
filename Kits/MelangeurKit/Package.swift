// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MelangeurKit",
    // macOS 14.2 : c'est là qu'arrivent les taps de processus CoreAudio, sans
    // lesquels on ne règle pas une application à part.
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "MelangeurKit", targets: ["MelangeurKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "MelangeurKit", dependencies: ["Commun"]),
        // Banc d'essai en ligne de commande : n'est pas un produit, donc jamais
        // compilé par Trousse. Voir essai.sh.
        .executableTarget(name: "melangeur-test", dependencies: ["MelangeurKit", "Commun"])
    ]
)
