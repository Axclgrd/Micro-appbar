// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FonteKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FonteKit", targets: ["FonteKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "FonteKit", dependencies: ["Commun"])
    ]
)
