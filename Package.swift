// swift-tools-version:5.9
import PackageDescription

// Pinned to tools-version 5.9 (Xcode 15+) on purpose: it builds on every
// recent Swift toolchain, and at this manifest version Swift 5 language mode
// is already the default — so we get v5 (no strict-concurrency churn) without
// the SwiftSetting.swiftLanguageMode(.v5) API, which only exists on newer 6.x
// toolchains and breaks the manifest on earlier ones.
let package = Package(
    name: "ClaudeTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeTracker",
            path: "Sources/ClaudeTracker"
        )
    ]
)
