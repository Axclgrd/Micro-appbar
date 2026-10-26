// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pouls",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/PoulsKit"),
    ],
    targets: [
        .executableTarget(name: "PoulsApp", dependencies: ["Commun", "PoulsKit"])
    ]
)
