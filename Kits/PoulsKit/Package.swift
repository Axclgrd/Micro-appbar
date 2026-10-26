// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PoulsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PoulsKit", targets: ["PoulsKit"])
    ],
    dependencies: [
        .package(path: "../Commun"),
    ],
    targets: [
        .target(name: "PoulsKit", dependencies: ["Commun"])
    ]
)
