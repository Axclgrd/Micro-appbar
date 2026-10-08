// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BandeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BandeKit", targets: ["BandeKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "BandeKit", dependencies: ["Commun"])
    ]
)
