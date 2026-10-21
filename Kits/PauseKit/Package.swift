// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PauseKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PauseKit", targets: ["PauseKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "PauseKit", dependencies: ["Commun"])
    ]
)
