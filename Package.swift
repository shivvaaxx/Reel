// swift-tools-version:6.2
import PackageDescription

// Sparkle (self-updates) is vendored by tools/fetch-sparkle.sh, which build.sh runs first.
let package = Package(
    name: "Reel",
    platforms: [.macOS(.v26)],
    targets: [
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle/Sparkle.xcframework"),
        .executableTarget(
            name: "Reel",
            dependencies: ["Sparkle"],
            path: "Sources/Reel",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "ReelTests",
            dependencies: ["Reel"],
            path: "Tests/ReelTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
