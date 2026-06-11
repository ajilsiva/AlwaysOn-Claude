import AppKit
import ServiceManagement

/// Owns the dropdown NSMenu. Data rows are disabled items whose titles are
/// re-rendered from AppState; a 1 s timer keeps countdowns ticking while the
/// menu is open (added in .common mode so it fires during menu tracking).
final class MenuBuilder: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let state: AppState

    var onToggleWake: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onSelectDisplayMode: ((DisplayMode) -> Void)?

    private let usageCard = UsageCardView()
    private let usageCardItem = NSMenuItem()
    private let modelItem = NSMenuItem()
    private let contextItem = NSMenuItem()
    private let effortItem = NSMenuItem()
    private let projectItem = NSMenuItem()
    private let timeItem = NSMenuItem()
    private let wakeItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let displayItem = NSMenuItem()
    private var displayModeItems: [DisplayMode: NSMenuItem] = [:]
    private let refreshItem = NSMenuItem()
    private var tickTimer: Timer?

    init(state: AppState) {
        self.state = state
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self

        for item in [modelItem, contextItem, effortItem, projectItem, timeItem] {
            item.isEnabled = false
        }

        usageCardItem.view = usageCard

        wakeItem.title = "Keep Mac Awake"
        wakeItem.target = self
        wakeItem.action = #selector(toggleWake)

        loginItem.title = "Launch at Login"
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        // SMAppService needs a real bundle; hidden under bare `swift run`.
        loginItem.isHidden = Bundle.main.bundleIdentifier == nil

        displayItem.title = "Display"
        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(selectDisplayMode(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            // Touch Bar choices are pointless without the hardware.
            if mode != .menuBarOnly, !ControlStripController.hardwarePresent {
                item.isEnabled = false
                item.title = mode.title + "  (no Touch Bar)"
            }
            displayMenu.addItem(item)
            displayModeItems[mode] = item
        }
        displayItem.submenu = displayMenu

        refreshItem.title = "Refresh Now"
        refreshItem.target = self
        refreshItem.action = #selector(refresh)
        refreshItem.keyEquivalent = "r"

        let quitItem = NSMenuItem(title: "Quit Claude Tracker",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.target = NSApp

        menu.addItem(usageCardItem)
        menu.addItem(.separator())
        menu.addItem(modelItem)
        menu.addItem(contextItem)
        menu.addItem(effortItem)
        menu.addItem(.separator())
        menu.addItem(projectItem)
        menu.addItem(timeItem)
        menu.addItem(.separator())
        menu.addItem(wakeItem)
        menu.addItem(loginItem)
        menu.addItem(displayItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        update()
    }

    func update() {
        let session = state.session

        usageCard.update(usage: state.usage)

        if let model = session.modelId {
            modelItem.title = Format.modelDisplayName(model)
        } else {
            modelItem.title = "Claude Tracker"
        }

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
        if !loginItem.isHidden {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        for (mode, item) in displayModeItems {
            item.state = mode == state.displayMode ? .on : .off
        }
    }

    private func contextLine(_ session: SessionSnapshot) -> String {
        guard session.contextTokens != nil else { return "Context\t–" }
        let limit = Format.tokens(session.contextLimit)
        return "Context\t\(Format.percent(session.contextPercent)) of \(limit) (\(Format.tokens(session.contextTokens)))"
    }

    @objc private func toggleWake() {
        onToggleWake?()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw) else { return }
        onSelectDisplayMode?(mode)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("LoginItem: \(error.localizedDescription)")
        }
        update()
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
