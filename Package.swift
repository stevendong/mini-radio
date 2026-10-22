// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniRadio",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "RadioCore", targets: ["RadioCore"]),
        .executable(name: "MiniRadio", targets: ["RoamRadio"])
    ],
    targets: [
        .target(name: "RadioCore"),
        .executableTarget(name: "RoamRadio", dependencies: ["RadioCore"], path: "App",
                          exclude: ["iOS"], sources: ["macOS", "Shared"]),
        .testTarget(name: "RadioCoreTests", dependencies: ["RadioCore"])
    ]
)
