import AppKit

/// The app's nervous system: 60 s timer, FSEvents-triggered local refreshes,
/// manual refresh, and refresh-on-wake. Local parsing happens on a serial
/// utility queue; snapshots are applied to AppState on the main queue.
final class RefreshCoordinator {
    private let state: AppState
    private let pipeline = LocalDataPipeline()
    private let queue = DispatchQueue(label: "com.aproitsolutions.claude-tracker.refresh",
                                      qos: .utility)
    private var timer: Timer?

    init(state: AppState) {
        self.state = state
    }

    func start() {
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 10
        self.timer = timer

        pipeline.indexer.onChange = { [weak self] in
            self?.localRefresh()
        }
        pipeline.indexer.startWatching()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        manualRefresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pipeline.indexer.stopWatching()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func manualRefresh() {
        localRefresh()
        // M5: networkRefresh(force: true)
    }

    private func tick() {
        localRefresh()
        // M5: networkRefresh(force: false)
    }

    @objc private func didWake() {
        manualRefresh()
    }

    private func localRefresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.pipeline.buildSessionSnapshot()
            DispatchQueue.main.async {
                self.state.apply(session: snapshot)
            }
        }
    }
}
