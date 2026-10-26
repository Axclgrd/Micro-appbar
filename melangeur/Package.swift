// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Melangeur",
    // macOS 14.2 : les taps de processus CoreAudio, sans lesquels on ne règle
    // pas une application à part.
    platforms: [.macOS("14.2")],
    dependencies: [
        .package(path: "../Kits/Commun"),
        .package(path: "../Kits/MelangeurKit"),
    ],
    targets: [
        .executableTarget(name: "MelangeurApp", dependencies: ["Commun", "MelangeurKit"])
    ]
)
