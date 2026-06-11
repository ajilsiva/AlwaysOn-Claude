import AppKit

// `ClaudeTracker --dump` prints the local-data snapshot and exits — the same
// pipeline the GUI uses, made shell-verifiable. Never prints secrets.
if CommandLine.arguments.contains("--dump") {
    let pipeline = LocalDataPipeline()
    let snapshot = pipeline.buildSessionSnapshot()
    print("model: \(snapshot.modelId ?? "-")")
    print("modelDisplay: \(snapshot.modelId.map(Format.modelDisplayName) ?? "-")")
    print("contextTokens: \(snapshot.contextTokens.map(String.init) ?? "-")")
    print("contextLimit: \(snapshot.contextLimit)")
    print("contextPercent: \(snapshot.contextPercent.map { String(format: "%.1f", $0) } ?? "-")")
    print("projectPath: \(snapshot.projectPath ?? "-")")
    print("effortLevel: \(snapshot.effortLevel ?? "-")")
    print("activity: \(snapshot.activity)")
    print("projectActiveSeconds: \(snapshot.projectActiveSeconds.map { String(Int($0)) } ?? "-")")
    print("projectTimeDisplay: \(Format.duration(snapshot.displayActiveSeconds))")
    print("claudeCodeVersion: \(pipeline.claudeCodeVersion() ?? "-")")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
