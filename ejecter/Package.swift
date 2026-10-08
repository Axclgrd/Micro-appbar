// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ejecter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/EjecterKit"),
    ],
    targets: [
        // Une seule cible : l'outil n'a ni démon ni privilège à part. Tout ce
        // qu'il fait, l'utilisateur connecté a déjà le droit de le faire.
        .executableTarget(name: "EjecterApp", dependencies: ["Commun", "EjecterKit"])
    ]
)
