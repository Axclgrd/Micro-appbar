// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SMCKit",
    platforms: [.macOS(.v14)],
    products: [
        // Couche bas niveau partagée entre l'interface et le démon privilégié.
        // Elle vit ici, hors de l'app, parce que ses deux consommateurs sont
        // maintenant dans deux paquets différents.
        .library(name: "SMCKit", targets: ["SMCKit"])
    ],
    targets: [
        .target(name: "SMCKit")
    ]
)
