// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EjecterKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EjecterKit", targets: ["EjecterKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "EjecterKit", dependencies: ["Commun"])
    ]
)
