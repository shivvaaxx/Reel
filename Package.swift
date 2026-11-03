// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Reel",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Reel",
            path: "Sources/Reel",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ReelTests",
            dependencies: ["Reel"],
            path: "Tests/ReelTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
