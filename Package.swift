// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lair",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LairCore", targets: ["LairCore"]),
        .executable(name: "lair-spike", targets: ["LairSpike"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        .target(name: "LairCore"),
        .executableTarget(
            name: "LairSpike",
            dependencies: ["LairCore", .product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .testTarget(name: "LairCoreTests", dependencies: ["LairCore"]),
    ]
)
