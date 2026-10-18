// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JaugeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JaugeKit", targets: ["JaugeKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "JaugeKit", dependencies: ["Commun"])
    ]
)
