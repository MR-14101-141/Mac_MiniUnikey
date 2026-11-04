// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniUnikey",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MiniUnikeyEngine",
            path: "Sources/MiniUnikeyEngine"
        ),
        .executableTarget(
            name: "MiniUnikey",
            dependencies: ["MiniUnikeyEngine"],
            path: "Sources/MiniUnikey"
        ),
        .executableTarget(
            name: "engine-cli",
            dependencies: ["MiniUnikeyEngine"],
            path: "Tools/engine-cli"
        ),
        .testTarget(
            name: "MiniUnikeyTests",
            dependencies: ["MiniUnikeyEngine"],
            path: "Tests/MiniUnikeyTests",
            resources: [
                .copy("corpus.jsonl"),
                .copy("corpus_telex.jsonl")
            ]
        ),
    ]
)
