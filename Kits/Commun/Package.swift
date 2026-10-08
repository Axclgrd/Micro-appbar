// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Commun",
    // macOS 14 : c'est la cible des apps autonomes. Trousse monte plus haut
    // pour le verre liquide, mais le socle doit rester compatible avec les six.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Commun", targets: ["Commun"])
    ],
    targets: [
        .target(name: "Commun")
    ]
)
