import AppKit

/// One persistent Control Strip button ("◐ 42·89" — 5h utilization · context %).
/// Tapping it presents a modal Touch Bar with the full readout plus Wake and
/// Refresh controls. ControlStrip/TouchBarServer restarts drop tray items, so
/// the item is re-asserted every 60 s (MTMR does the same).
final class ControlStripController: NSObject, NSTouchBarDelegate {
    static let stripIdentifier = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.strip")
    private static let fiveHourID = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.modal.5h")
    private static let weekID = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.modal.week")
    private static let contextID = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.modal.ctx")
    private static let wakeID = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.modal.wake")
    private static let refreshID = NSTouchBarItem.Identifier("com.aproitsolutions.claude-tracker.modal.refresh")

    private let state: AppState
    var onToggleWake: (() -> Void)?
    var onRefresh: (() -> Void)?

    private var trayItem: NSCustomTouchBarItem?
    private var stripButton: NSButton?
    private var modalBar: NSTouchBar?
    private var fiveHourView: NSImageView?
    private var weekView: NSImageView?
    private var contextLabel: NSTextField?
    private var wakeButton: NSButton?
    private var reassertTimer: Timer?
    private(set) var isInstalled = false

    init(state: AppState) {
        self.state = state
        super.init()
    }

    /// True only on Macs with a physical Touch Bar: the DFR symbols exist in
    /// the shared cache on every Mac, but TouchBarServer runs only on Touch
    /// Bar hardware. Evaluated once.
    static let hardwarePresent: Bool = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "TouchBarServer"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }()

    /// Returns false when no Touch Bar hardware exists, the private API is
    /// unavailable, or CT_NO_TOUCHBAR=1 — the app then runs menu-bar-only.
    /// Idempotent: returns true immediately if already installed.
    @discardableResult
    func install() -> Bool {
        if isInstalled { return true }
        guard ProcessInfo.processInfo.environment["CT_NO_TOUCHBAR"] == nil else {
            NSLog("TouchBar: disabled via CT_NO_TOUCHBAR")
            return false
        }
        guard Self.hardwarePresent else {
            NSLog("TouchBar: no Touch Bar hardware — menu bar only")
            return false
        }
        guard DFR.isAvailable else {
            NSLog("TouchBar: DFR private API unavailable — menu bar only")
            return false
        }

        DFR.showsCloseBoxWhenFrontMost(true)
        let button = NSButton(title: "", target: self, action: #selector(stripTapped))
        button.image = BarRenderer.touchBarStripImage(fiveHour: nil, weekly: nil)
        button.imagePosition = .imageOnly
        let item = NSCustomTouchBarItem(identifier: Self.stripIdentifier)
        item.view = button
        trayItem = item
        stripButton = button
        DFR.addSystemTrayItem(item)
        DFR.setControlStripPresence(Self.stripIdentifier, true)
        isInstalled = true
        NSLog("TouchBar: control strip item installed")
        render()

        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reassert()
        }
        timer.tolerance = 10
        reassertTimer = timer
        return true
    }

    func uninstall() {
        reassertTimer?.invalidate()
        reassertTimer = nil
        guard isInstalled else { return }
        if let bar = modalBar { DFR.dismissSystemModal(bar) }
        DFR.setControlStripPresence(Self.stripIdentifier, false)
        if let item = trayItem { DFR.removeSystemTrayItem(item) }
        isInstalled = false
    }

    func render() {
        guard isInstalled else { return }
        stripButton?.image = BarRenderer.touchBarStripImage(
            fiveHour: state.usage.fiveHourPercent,
            weekly: state.usage.sevenDayPercent)

        let resetSuffix = state.usage.fiveHourResetsAt.map {
            "→ \(Format.duration(max(0, $0.timeIntervalSinceNow)))"
        }
        fiveHourView?.image = BarRenderer.touchBarRowImage(
            label: "5h", percent: state.usage.fiveHourPercent, suffix: resetSuffix)
        weekView?.image = BarRenderer.touchBarRowImage(
            label: "wk", percent: state.usage.sevenDayPercent)

        var context = "–"
        if case .active = state.session.activity, let percent = state.session.contextPercent {
            context = "\(Int(percent.rounded()))%"
        }
        contextLabel?.stringValue = "ctx \(context)"
        wakeButton?.title = state.wakeEnabled ? "☕ Wake On" : "☕ Wake Off"
        wakeButton?.bezelColor = state.wakeEnabled ? .controlAccentColor : nil
    }

    /// ControlStrip can restart and forget us; remove+add is MTMR's idempotent
    /// recovery sequence.
    func reassert() {
        guard isInstalled, let item = trayItem else { return }
        DFR.removeSystemTrayItem(item)
        DFR.addSystemTrayItem(item)
        DFR.setControlStripPresence(Self.stripIdentifier, true)
    }

    // MARK: - Actions

    @objc private func stripTapped() {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.fiveHourID, Self.weekID, Self.contextID,
                                      .flexibleSpace, Self.wakeID, Self.refreshID]
        modalBar = bar
        DFR.presentSystemModal(bar, trayItem: Self.stripIdentifier)
        onRefresh?()
    }

    @objc private func wakeTapped() {
        onToggleWake?()
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        switch identifier {
        case Self.fiveHourID:
            let imageView = NSImageView()
            imageView.imageScaling = .scaleNone
            fiveHourView = imageView
            item.view = imageView
        case Self.weekID:
            let imageView = NSImageView()
            imageView.imageScaling = .scaleNone
            weekView = imageView
            item.view = imageView
        case Self.contextID:
            let label = NSTextField(labelWithString: "")
            label.font = labelFont
            contextLabel = label
            item.view = label
        case Self.wakeID:
            let button = NSButton(title: "☕ Wake Off", target: self, action: #selector(wakeTapped))
            wakeButton = button
            item.view = button
        case Self.refreshID:
            item.view = NSButton(title: "↻", target: self, action: #selector(refreshTapped))
        default:
            return nil
        }
        DispatchQueue.main.async { [weak self] in self?.render() }
        return item
    }
}
