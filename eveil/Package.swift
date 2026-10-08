// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Eveil",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/EveilKit"),
    ],
    targets: [
        .executableTarget(name: "EveilApp", dependencies: ["Commun", "EveilKit"])
    ]
)
