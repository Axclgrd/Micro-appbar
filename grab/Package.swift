// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Grab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/GrabKit"),
    ],
    targets: [
        .executableTarget(name: "GrabApp", dependencies: ["Commun", "GrabKit"])
    ]
)
