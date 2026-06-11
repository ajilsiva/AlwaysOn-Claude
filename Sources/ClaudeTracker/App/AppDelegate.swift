import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let caffeinate = CaffeinateController()
    private var statusController: StatusItemController?
    private var refreshCoordinator: RefreshCoordinator?
    private var controlStrip: ControlStripController?
    private var sigusr1Source: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        caffeinate.onStateChange = { [weak self] on in
            self?.state.setWake(on)
        }

        let coordinator = RefreshCoordinator(state: state)
        refreshCoordinator = coordinator

        let controller = StatusItemController(state: state)
        controller.menuBuilder.onToggleWake = { [weak self] in
            self?.caffeinate.toggle()
        }
        controller.menuBuilder.onRefresh = { [weak coordinator] in
            coordinator?.manualRefresh()
        }
        statusController = controller

        let strip = ControlStripController(state: state)
        strip.onToggleWake = { [weak self] in
            self?.caffeinate.toggle()
        }
        strip.onRefresh = { [weak coordinator] in
            coordinator?.manualRefresh()
        }
        controlStrip = strip
        strip.install()

        coordinator.start()

        state.subscribe { [weak controller, weak strip] in
            controller?.render()
            strip?.render()
        }

        // `kill -USR1 <pid>` toggles Wake — scriptable (hotkeys) and testable.
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            self?.caffeinate.toggle()
        }
        source.resume()
        sigusr1Source = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        caffeinate.stop()
        refreshCoordinator?.stop()
        controlStrip?.uninstall()
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0 != NSRunningApplication.current }
    }
}
