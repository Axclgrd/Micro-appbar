// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EveilKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EveilKit", targets: ["EveilKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "EveilKit", dependencies: ["Commun"])
    ]
)
