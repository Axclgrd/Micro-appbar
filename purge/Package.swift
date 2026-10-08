// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Purge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/PurgeKit"),
    ],
    targets: [
        .executableTarget(name: "PurgeApp", dependencies: ["Commun", "PurgeKit"])
    ]
)
