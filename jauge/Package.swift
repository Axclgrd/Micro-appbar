// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Jauge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/JaugeKit"),
    ],
    targets: [
        .executableTarget(name: "JaugeApp", dependencies: ["Commun", "JaugeKit"])
    ]
)
