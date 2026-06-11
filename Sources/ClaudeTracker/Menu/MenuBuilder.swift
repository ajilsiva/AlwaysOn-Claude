import AppKit

/// Owns the dropdown NSMenu. Data rows are disabled items whose titles are
/// re-rendered from AppState; a 1 s timer keeps countdowns ticking while the
/// menu is open (added in .common mode so it fires during menu tracking).
final class MenuBuilder: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let state: AppState

    var onToggleWake: (() -> Void)?
    var onRefresh: (() -> Void)?

    private let modelItem = NSMenuItem()
    private let sessionItem = NSMenuItem()
    private let weekItem = NSMenuItem()
    private let contextItem = NSMenuItem()
    private let effortItem = NSMenuItem()
    private let projectItem = NSMenuItem()
    private let timeItem = NSMenuItem()
    private let wakeItem = NSMenuItem()
    private let refreshItem = NSMenuItem()
    private var tickTimer: Timer?

    init(state: AppState) {
        self.state = state
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self

        for item in [modelItem, sessionItem, weekItem, contextItem, effortItem, projectItem, timeItem] {
            item.isEnabled = false
        }

        wakeItem.title = "Keep Mac Awake"
        wakeItem.target = self
        wakeItem.action = #selector(toggleWake)

        refreshItem.title = "Refresh Now"
        refreshItem.target = self
        refreshItem.action = #selector(refresh)
        refreshItem.keyEquivalent = "r"

        let quitItem = NSMenuItem(title: "Quit Claude Tracker",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp

        menu.addItem(modelItem)
        menu.addItem(sessionItem)
        menu.addItem(weekItem)
        menu.addItem(contextItem)
        menu.addItem(effortItem)
        menu.addItem(.separator())
        menu.addItem(projectItem)
        menu.addItem(timeItem)
        menu.addItem(.separator())
        menu.addItem(wakeItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        update()
    }

    func update() {
        let session = state.session
        let usage = state.usage

        if let model = session.modelId {
            modelItem.title = Format.modelDisplayName(model)
        } else {
            modelItem.title = "Claude Tracker"
        }

        renderUsageRows(usage)

        switch session.activity {
        case .none:
            contextItem.title = "No active session"
            contextItem.isHidden = false
        case .idle(let minutes):
            contextItem.title = contextLine(session) + "  · idle \(Format.duration(TimeInterval(minutes * 60)))"
        case .active:
            contextItem.title = contextLine(session)
        }

        if let effort = session.effortLevel {
            effortItem.title = "Effort\t\(effort)"
            effortItem.isHidden = false
        } else {
            effortItem.isHidden = true
        }

        if let path = session.projectPath {
            projectItem.title = "Project\t\((path as NSString).lastPathComponent)"
            projectItem.toolTip = path
            timeItem.title = "Time on project\t\(Format.duration(session.displayActiveSeconds))"
            projectItem.isHidden = false
            timeItem.isHidden = false
        } else {
            projectItem.isHidden = true
            timeItem.isHidden = true
        }

        wakeItem.state = state.wakeEnabled ? .on : .off
    }

    private func contextLine(_ session: SessionSnapshot) -> String {
        guard session.contextTokens != nil else { return "Context\t–" }
        let limit = Format.tokens(session.contextLimit)
        return "Context\t\(Format.percent(session.contextPercent)) of \(limit) (\(Format.tokens(session.contextTokens)))"
    }

    private func renderUsageRows(_ usage: UsageSnapshot) {
        let hasValues = usage.fiveHourPercent != nil || usage.sevenDayPercent != nil

        if hasValues {
            var sessionLine = "Session\t\(Format.percent(usage.fiveHourPercent)) · resets \(Format.reset(usage.fiveHourResetsAt))"
            let weekLine = "Week\t\(Format.percent(usage.sevenDayPercent)) · resets \(Format.reset(usage.sevenDayResetsAt))"
            if let stale = usage.staleSeconds {
                sessionLine += "  (stale \(Format.duration(stale)))"
            }
            sessionItem.title = sessionLine
            weekItem.title = weekLine
            weekItem.isHidden = false
            return
        }

        weekItem.isHidden = true
        switch usage.status {
        case .never:
            sessionItem.title = "Usage\tloading…"
        case .ok:
            sessionItem.title = "Usage\t–"
        case .noCredentials:
            sessionItem.title = "Usage\tsign in via Claude Code"
        case .unauthorized:
            sessionItem.title = "Usage\tre-auth needed (claude login)"
        case .rateLimited(let until):
            sessionItem.title = "Usage\trate-limited" + (until.map { " until \(Format.reset($0))" } ?? "")
        case .error(let message):
            sessionItem.title = "Usage\tunavailable (\(message))"
        }
    }

    @objc private func toggleWake() {
        onToggleWake?()
    }

    @objc private func refresh() {
        onRefresh?()
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        update()
        onRefresh?()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
