// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lair",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lair", targets: ["Lair"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "LairCore"),
        .target(name: "LairACP", dependencies: ["LairCore"]),
        .target(name: "LairVoice", dependencies: ["LairCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "LairMCP", dependencies: [
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "Hummingbird", package: "hummingbird"),
        ]),
        .executableTarget(
            name: "Lair",
            dependencies: ["LairCore", "LairACP", "LairVoice", "LairMCP", "KeyboardShortcuts",
                           .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework sits in Contents/Frameworks of the app (see scripts/build-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])]
        ),
        .testTarget(name: "LairCoreTests", dependencies: ["LairCore"]),
        .testTarget(name: "LairACPTests", dependencies: ["LairACP", "LairCore"]),
        .testTarget(name: "LairVoiceTests", dependencies: ["LairVoice", "LairCore"]),
        .testTarget(name: "LairMCPTests", dependencies: ["LairMCP", .product(name: "MCP", package: "swift-sdk")]),
    ]
)
