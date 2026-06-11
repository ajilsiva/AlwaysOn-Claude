import Foundation

/// GUI wrapper around /usr/bin/caffeinate. The `-w <our pid>` flag ties the
/// child's lifetime to ours, so a crash or kill -9 can never orphan a sleep
/// assertion.
final class CaffeinateController {
    private var process: Process?
    var onStateChange: ((Bool) -> Void)?

    var isActive: Bool { process?.isRunning == true }

    func start() {
        guard !isActive else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-dims", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.process === proc else { return }
                self.process = nil
                self.onStateChange?(false)
            }
        }
        do {
            try p.run()
            process = p
            onStateChange?(true)
        } catch {
            process = nil
            onStateChange?(false)
        }
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        p.terminationHandler = nil
        p.terminate()
        onStateChange?(false)
    }

    func toggle() {
        isActive ? stop() : start()
    }
}
