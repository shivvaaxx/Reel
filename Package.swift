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
        )
    ]
)
