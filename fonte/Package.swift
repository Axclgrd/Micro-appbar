// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Fonte",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/FonteKit"),
    ],
    targets: [
        .executableTarget(name: "FonteApp", dependencies: ["Commun", "FonteKit"])
    ]
)
