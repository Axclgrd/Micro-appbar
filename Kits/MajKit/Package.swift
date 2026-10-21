// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MajKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MajKit", targets: ["MajKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "MajKit", dependencies: ["Commun"])
    ]
)
