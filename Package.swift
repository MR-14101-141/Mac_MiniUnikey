// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniUnikey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MiniUnikey",
            path: "Sources/MiniUnikey"
        ),
        .testTarget(
            name: "MiniUnikeyTests",
            dependencies: ["MiniUnikey"],
            path: "Tests/MiniUnikeyTests",
            resources: [
                .copy("corpus.jsonl")
            ]
        ),
    ]
)
