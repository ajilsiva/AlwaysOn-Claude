import AppKit

/// Dropdown card replicating Claude Code's /usage panel: header with plan
/// badge and status dot, "5-hour" and "Weekly" progress bars with reset
/// captions, and an "updated …" footer that doubles as the error-status line.
final class UsageCardView: NSView {
    static let cardWidth: CGFloat = 300
    static let cardHeight: CGFloat = 148

    private final class BarView: NSView {
        var percent: Double? { didSet { needsDisplay = true } }
        override func draw(_ dirtyRect: NSRect) {
            BarRenderer.drawBar(in: NSRect(x: 0, y: (bounds.height - 7) / 2,
                                           width: bounds.width, height: 7),
                                percent: percent)
        }
    }

    private let titleLabel = NSTextField(labelWithString: "✳︎ Claude")
    private let planBadge = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "●")
    private let fiveHourName = NSTextField(labelWithString: "5-hour")
    private let fiveHourBar = BarView()
    private let fiveHourValue = NSTextField(labelWithString: "–%")
    private let fiveHourCaption = NSTextField(labelWithString: "")
    private let weeklyName = NSTextField(labelWithString: "Weekly")
    private let weeklyBar = BarView()
    private let weeklyValue = NSTextField(labelWithString: "–%")
    private let weeklyCaption = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "connecting…")

    init() {
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: Self.cardWidth, height: Self.cardHeight))

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        planBadge.font = .systemFont(ofSize: 9, weight: .bold)
        planBadge.textColor = .secondaryLabelColor
        statusDot.font = .systemFont(ofSize: 10)

        for name in [fiveHourName, weeklyName] {
            name.font = .systemFont(ofSize: 12)
            name.textColor = .secondaryLabelColor
        }
        for value in [fiveHourValue, weeklyValue] {
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            value.alignment = .right
        }
        for caption in [fiveHourCaption, weeklyCaption] {
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .secondaryLabelColor
            caption.alignment = .right
        }
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor

        let left: CGFloat = 14
        let right = Self.cardWidth - 14
        let barX: CGFloat = 72
        let valueWidth: CGFloat = 48
        let barWidth = right - valueWidth - 6 - barX

        // Frames are laid out top-down (flipped coordinates done by hand).
        titleLabel.frame = NSRect(x: left, y: Self.cardHeight - 28, width: 120, height: 18)
        planBadge.frame = NSRect(x: left + 64, y: Self.cardHeight - 25, width: 60, height: 12)
        statusDot.frame = NSRect(x: right - 12, y: Self.cardHeight - 26, width: 12, height: 14)

        fiveHourName.frame = NSRect(x: left, y: Self.cardHeight - 54, width: 54, height: 16)
        fiveHourBar.frame = NSRect(x: barX, y: Self.cardHeight - 54, width: barWidth, height: 16)
        fiveHourValue.frame = NSRect(x: right - valueWidth, y: Self.cardHeight - 54,
                                     width: valueWidth, height: 16)
        fiveHourCaption.frame = NSRect(x: barX, y: Self.cardHeight - 70,
                                       width: right - barX, height: 14)

        weeklyName.frame = NSRect(x: left, y: Self.cardHeight - 96, width: 54, height: 16)
        weeklyBar.frame = NSRect(x: barX, y: Self.cardHeight - 96, width: barWidth, height: 16)
        weeklyValue.frame = NSRect(x: right - valueWidth, y: Self.cardHeight - 96,
                                   width: valueWidth, height: 16)
        weeklyCaption.frame = NSRect(x: barX, y: Self.cardHeight - 112,
                                     width: right - barX, height: 14)

        footer.frame = NSRect(x: left, y: 8, width: right - left, height: 14)

        for view in [titleLabel, planBadge, statusDot,
                     fiveHourName, fiveHourBar, fiveHourValue, fiveHourCaption,
                     weeklyName, weeklyBar, weeklyValue, weeklyCaption, footer] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(usage: UsageSnapshot) {
        planBadge.stringValue = usage.subscriptionType?.uppercased() ?? ""

        fiveHourBar.percent = usage.fiveHourPercent
        fiveHourValue.stringValue = Format.percent(usage.fiveHourPercent)
        fiveHourCaption.stringValue = Format.resetCaption(prefix: "5h", date: usage.fiveHourResetsAt)

        weeklyBar.percent = usage.sevenDayPercent
        weeklyValue.stringValue = Format.percent(usage.sevenDayPercent)
        weeklyCaption.stringValue = Format.resetCaption(prefix: "Week", date: usage.sevenDayResetsAt)

        let (footerText, dotColor) = Self.status(usage)
        footer.stringValue = footerText
        statusDot.textColor = dotColor
    }

    private static func status(_ usage: UsageSnapshot) -> (String, NSColor) {
        switch usage.status {
        case .never:
            return ("connecting…", .systemGray)
        case .ok:
            if let stale = usage.staleSeconds {
                return ("updated \(Format.duration(stale)) ago (stale)", .systemYellow)
            }
            return ("updated \(Format.ago(usage.fetchedAt))", .systemGreen)
        case .noCredentials:
            return ("sign in via Claude Code to see limits", .systemGray)
        case .unauthorized:
            return ("re-auth needed — run: claude login", .systemRed)
        case .rateLimited(let until):
            let suffix = until.map { " until \(Format.clock($0))" } ?? ""
            return ("rate-limited\(suffix)", .systemOrange)
        case .error(let message):
            return ("unavailable (\(message))", .systemRed)
        }
    }
}
