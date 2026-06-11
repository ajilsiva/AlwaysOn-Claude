import Foundation

enum UsageStatus: Equatable {
    case never
    case ok
    case noCredentials
    case unauthorized
    case rateLimited(until: Date?)
    case error(String)
}

struct UsageSnapshot {
    var fiveHourPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayPercent: Double?
    var sevenDayResetsAt: Date?
    var fetchedAt: Date?
    var status: UsageStatus = .never

    var staleSeconds: TimeInterval? {
        guard let fetchedAt else { return nil }
        let age = Date().timeIntervalSince(fetchedAt)
        return age > 300 ? age : nil
    }
}

enum SessionActivity {
    case active
    case idle(minutes: Int)
    case none
}

struct SessionSnapshot {
    var modelId: String?
    var contextTokens: Int?
    var contextLimit: Int = 200_000
    var projectPath: String?
    var sessionFileURL: URL?
    var lastActivity: Date?
    var projectActiveSeconds: TimeInterval?
    var effortLevel: String?
    var claudeCodeVersion: String?

    var contextPercent: Double? {
        guard let tokens = contextTokens, contextLimit > 0 else { return nil }
        return Double(tokens) / Double(contextLimit) * 100
    }

    var activity: SessionActivity {
        guard let last = lastActivity else { return .none }
        let age = Date().timeIntervalSince(last)
        if age > 86_400 { return .none }
        if age > 600 { return .idle(minutes: Int(age / 60)) }
        return .active
    }

    /// Display value for the project timer: stored sum plus the live tail
    /// since the last transcript write (capped at the idle-gap rule).
    var displayActiveSeconds: TimeInterval? {
        guard let base = projectActiveSeconds else { return nil }
        guard let last = lastActivity, case .active = activity else { return base }
        return base + min(Date().timeIntervalSince(last), 300)
    }
}

final class AppState {
    private(set) var usage = UsageSnapshot()
    private(set) var session = SessionSnapshot()
    private(set) var wakeEnabled = false
    private var observers: [() -> Void] = []

    func subscribe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    func apply(usage: UsageSnapshot) {
        self.usage = usage
        notify()
    }

    func apply(session: SessionSnapshot) {
        self.session = session
        notify()
    }

    func setWake(_ on: Bool) {
        guard wakeEnabled != on else { return }
        wakeEnabled = on
        notify()
    }

    private func notify() {
        observers.forEach { $0() }
    }
}

enum Format {
    /// "claude-fable-5" -> "Fable 5", "claude-opus-4-8" -> "Opus 4.8",
    /// "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    static func modelDisplayName(_ id: String) -> String {
        var s = id
        if s.hasPrefix("claude-") { s.removeFirst("claude-".count) }
        let parts = s.split(separator: "-").map(String.init)
        var words: [String] = []
        var numbers: [String] = []
        for p in parts {
            if p.allSatisfy(\.isNumber) {
                if p.count >= 8 { continue } // date suffix like 20251001
                numbers.append(p)
            } else {
                words.append(p.prefix(1).uppercased() + p.dropFirst())
            }
        }
        let name = words.joined(separator: " ")
        let version = numbers.joined(separator: ".")
        return [name, version].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–%" }
        return "\(Int(value.rounded()))%"
    }

    /// "12h 34m" / "34m" / "<1m"
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return "–" }
        let total = Int(seconds)
        let d = total / 86_400, h = (total % 86_400) / 3_600, m = (total % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    /// "14:32 (in 1h 23m)" or "Mon 09:00 (in 3d 4h)" for dates beyond today
    static func reset(_ date: Date?) -> String {
        guard let date else { return "–" }
        let remaining = date.timeIntervalSinceNow
        let f = DateFormatter()
        f.locale = Locale.current
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "EEE HH:mm"
        }
        let clock = f.string(from: date)
        if remaining <= 0 { return "\(clock) (now)" }
        return "\(clock) (in \(duration(remaining)))"
    }

    /// 177_556 -> "177.6k"
    static func tokens(_ count: Int?) -> String {
        guard let count else { return "–" }
        if count >= 1_000_000 { return String(format: "%.2fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }
}
