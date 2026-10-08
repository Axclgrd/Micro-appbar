// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortsKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortsKit", targets: ["PortsKit"])
    ],
    dependencies: [
        .package(path: "../Commun")
    ],
    targets: [
        .target(name: "PortsKit", dependencies: ["Commun"])
    ]
)
