// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenIsland",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenIsland", targets: ["TokenIsland"])],
    targets: [
        .target(name: "TokenIslandCore"),
        .executableTarget(name: "TokenIsland", dependencies: ["TokenIslandCore"]),
        .testTarget(name: "TokenIslandCoreTests", dependencies: ["TokenIslandCore"])
    ],
    swiftLanguageModes: [.v5]
)
