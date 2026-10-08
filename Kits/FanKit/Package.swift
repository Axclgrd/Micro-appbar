// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FanKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FanKit", targets: ["FanKit"])
    ],
    dependencies: [
        .package(path: "../Commun"),
        .package(path: "../SMCKit"),
    ],
    targets: [
        .target(name: "FanKit", dependencies: ["Commun", "SMCKit"])
    ]
)
