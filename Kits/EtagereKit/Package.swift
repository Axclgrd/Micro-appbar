// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EtagereKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EtagereKit", targets: ["EtagereKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "EtagereKit", dependencies: ["Commun"])
    ]
)
