// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NuitKit",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "NuitKit", targets: ["NuitKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "NuitKit", dependencies: ["Commun"]),
        // Banc d'essai en ligne de commande : n'est pas un produit, donc jamais
        // compilé par Trousse. Voir essai.sh.
        .executableTarget(name: "nuit-test", dependencies: ["NuitKit"])
    ]
)
