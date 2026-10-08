// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bande",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/BandeKit"),
    ],
    targets: [
        .executableTarget(name: "BandeApp", dependencies: ["Commun", "BandeKit"])
    ]
)
