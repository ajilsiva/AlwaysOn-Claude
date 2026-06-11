import AppKit

/// The app's nervous system: 60 s timer, FSEvents-triggered local refreshes,
/// manual refresh, and refresh-on-wake. Local parsing happens on a serial
/// utility queue; snapshots are applied to AppState on the main queue.
final class RefreshCoordinator {
    private let state: AppState
    private let pipeline = LocalDataPipeline()
    private let api = UsageAPIClient()
    private let queue = DispatchQueue(label: "com.aproitsolutions.claude-tracker.refresh",
                                      qos: .utility)
    private var timer: Timer?
    private var blockedUntil: Date?
    private var lastNetworkFetch: Date?
    private var fetchInFlight = false

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
        networkRefresh(force: true)
    }

    private func tick() {
        localRefresh()
        networkRefresh(force: false)
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

    // MARK: - Network (main-thread entry)

    /// Etiquette: never more than ~1 req/min on the timer; manual refresh is
    /// debounced to 5 s; 429s gate everything via blockedUntil.
    private func networkRefresh(force: Bool) {
        guard !fetchInFlight else { return }
        if let blocked = blockedUntil, Date() < blocked { return }
        if let last = lastNetworkFetch,
           Date().timeIntervalSince(last) < (force ? 5 : 55) { return }

        fetchInFlight = true
        lastNetworkFetch = Date()
        let version = state.session.claudeCodeVersion
        Task { [weak self] in
            guard let self else { return }
            await self.performFetch(claudeVersion: version, retryOn401: true)
            await MainActor.run { self.fetchInFlight = false }
        }
    }

    private func performFetch(claudeVersion: String?, retryOn401: Bool) async {
        guard case .success(let credentials) = CredentialsProvider.load() else {
            await applyUsageStatus(.noCredentials)
            return
        }
        do {
            let response = try await api.fetch(token: credentials.accessToken,
                                               claudeVersion: claudeVersion)
            await MainActor.run {
                var usage = UsageSnapshot()
                usage.fiveHourPercent = response.fiveHour?.utilization
                usage.fiveHourResetsAt = response.fiveHour?.resetsAtDate
                usage.sevenDayPercent = response.sevenDay?.utilization
                usage.sevenDayResetsAt = response.sevenDay?.resetsAtDate
                usage.fetchedAt = Date()
                usage.subscriptionType = credentials.subscriptionType
                usage.status = .ok
                self.state.apply(usage: usage)
            }
        } catch UsageFetchError.unauthorized where retryOn401 {
            // Claude Code may have rotated the token since we read it.
            await performFetch(claudeVersion: claudeVersion, retryOn401: false)
        } catch UsageFetchError.unauthorized {
            await applyUsageStatus(.unauthorized)
        } catch UsageFetchError.rateLimited(let until) {
            let resume = until ?? Date().addingTimeInterval(300)
            await MainActor.run { self.blockedUntil = resume }
            await applyUsageStatus(.rateLimited(until: until))
        } catch UsageFetchError.server(let code) {
            await applyUsageStatus(.error("HTTP \(code)"))
        } catch UsageFetchError.decode {
            await applyUsageStatus(.error("bad response"))
        } catch {
            await applyUsageStatus(.error("offline"))
        }
    }

    /// Errors keep the last known values; only the status changes.
    private func applyUsageStatus(_ status: UsageStatus) async {
        await MainActor.run {
            var usage = self.state.usage
            usage.status = status
            self.state.apply(usage: usage)
        }
    }
}
