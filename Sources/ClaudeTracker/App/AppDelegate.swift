import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let caffeinate = CaffeinateController()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        caffeinate.onStateChange = { [weak self] on in
            self?.state.setWake(on)
        }

        let controller = StatusItemController(state: state)
        controller.menuBuilder.onToggleWake = { [weak self] in
            self?.caffeinate.toggle()
        }
        controller.menuBuilder.onRefresh = {
            // Wired to RefreshCoordinator in M3/M5.
        }
        statusController = controller

        state.subscribe { [weak controller] in
            controller?.render()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        caffeinate.stop()
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0 != NSRunningApplication.current }
    }
}
