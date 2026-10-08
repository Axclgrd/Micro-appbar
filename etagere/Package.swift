// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Etagere",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/EtagereKit"),
    ],
    targets: [
        .executableTarget(name: "EtagereApp", dependencies: ["Commun", "EtagereKit"])
    ]
)
