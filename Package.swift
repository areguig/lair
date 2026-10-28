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
    ],
    targets: [
        .target(name: "LairCore"),
        .target(name: "LairVoice", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(
            name: "Lair",
            dependencies: ["LairCore", "LairVoice", "KeyboardShortcuts"]
        ),
        .testTarget(name: "LairCoreTests", dependencies: ["LairCore"]),
        .testTarget(name: "LairVoiceTests", dependencies: ["LairVoice"]),
    ]
)
