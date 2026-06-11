// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeTracker",
            path: "Sources/ClaudeTracker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
