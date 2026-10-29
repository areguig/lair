// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lair",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lair", targets: ["Lair"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
    ],
    targets: [
        .target(name: "LairCore"),
        .target(name: "LairVoice", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "LairMCP", dependencies: [
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "Hummingbird", package: "hummingbird"),
        ]),
        .executableTarget(
            name: "Lair",
            dependencies: ["LairCore", "LairVoice", "LairMCP", "KeyboardShortcuts"]
        ),
        .testTarget(name: "LairCoreTests", dependencies: ["LairCore"]),
        .testTarget(name: "LairVoiceTests", dependencies: ["LairVoice"]),
        .testTarget(name: "LairMCPTests", dependencies: ["LairMCP", .product(name: "MCP", package: "swift-sdk")]),
    ]
)
