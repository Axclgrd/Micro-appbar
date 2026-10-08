// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GrabKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrabKit", targets: ["GrabKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "GrabKit", dependencies: ["Commun"])
    ]
)
