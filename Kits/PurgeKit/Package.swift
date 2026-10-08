// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PurgeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PurgeKit", targets: ["PurgeKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "PurgeKit", dependencies: ["Commun"])
    ]
)
