// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NxLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "NxLauncher", targets: ["NxLauncher"]),
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
    ],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "NxLauncher", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ]
)
