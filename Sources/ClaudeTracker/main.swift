import AppKit
import ServiceManagement

// Shell-scriptable launch-at-login control (same SMAppService the menu
// toggle uses): --register-login / --unregister-login / --login-status
if CommandLine.arguments.contains(where: {
    ["--register-login", "--unregister-login", "--login-status"].contains($0)
}) {
    let service = SMAppService.mainApp
    do {
        if CommandLine.arguments.contains("--register-login") { try service.register() }
        if CommandLine.arguments.contains("--unregister-login") { try service.unregister() }
    } catch {
        print("login item error: \(error.localizedDescription)")
        exit(1)
    }
    print("login item: \(service.status == .enabled ? "enabled" : "not enabled (status \(service.status.rawValue))")")
    exit(0)
}

// `--set-display both|menubar|touchbar` persists the surface preference and
// bounces the running GUI instance so it takes effect immediately.
if let index = CommandLine.arguments.firstIndex(of: "--set-display") {
    guard CommandLine.arguments.count > index + 1,
          let mode = DisplayMode(rawValue: CommandLine.arguments[index + 1]) else {
        print("usage: --set-display \(DisplayMode.allCases.map(\.rawValue).joined(separator: "|"))")
        exit(1)
    }
    mode.save()
    print("display mode: \(mode.rawValue) (\(mode.title))")
    if let bundleID = Bundle.main.bundleIdentifier {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !running.isEmpty {
            running.forEach { $0.terminate() }
            Thread.sleep(forTimeInterval: 1.0)
            let reopen = Process()
            reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            reopen.arguments = [Bundle.main.bundlePath]
            try? reopen.run()
            print("relaunched running instance")
        }
    }
    exit(0)
}

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
    print("claudeCodeVersion: \(snapshot.claudeCodeVersion ?? "-")")

    // `--dump --usage` also exercises the network path (prints percentages
    // and reset times only — never token material).
    if CommandLine.arguments.contains("--usage") {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            guard case .success(let credentials) = CredentialsProvider.load() else {
                print("usage: no credentials")
                return
            }
            do {
                let response = try await UsageAPIClient().fetch(
                    token: credentials.accessToken,
                    claudeVersion: snapshot.claudeCodeVersion)
                print("fiveHour: \(Format.percent(response.fiveHour?.utilization)) resets \(Format.reset(response.fiveHour?.resetsAtDate))")
                print("sevenDay: \(Format.percent(response.sevenDay?.utilization)) resets \(Format.reset(response.sevenDay?.resetsAtDate))")
            } catch {
                print("usage error: \(error)")
            }
        }
        semaphore.wait()
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
