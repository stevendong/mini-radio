// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniRadio",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MiniRadio", targets: ["RoamRadio"])],
    targets: [
        .target(name: "RadioCore"),
        .executableTarget(name: "RoamRadio", dependencies: ["RadioCore"]),
        .testTarget(name: "RadioCoreTests", dependencies: ["RadioCore"])
    ]
)
