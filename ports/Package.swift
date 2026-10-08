// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ports",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/PortsKit"),
    ],
    targets: [
        .executableTarget(name: "PortsApp", dependencies: ["Commun", "PortsKit"])
    ]
)
