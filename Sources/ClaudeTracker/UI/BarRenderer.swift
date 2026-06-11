import AppKit

/// Shared progress-bar drawing for the menu bar, dropdown card, and Touch Bar.
/// Color scheme mirrors Claude Code's /usage card: green, orange from 50%,
/// red from 85%.
enum BarRenderer {
    static func color(forPercent percent: Double?) -> NSColor {
        guard let percent else { return .systemGray }
        if percent >= 85 { return .systemRed }
        if percent >= 50 { return .systemOrange }
        return .systemGreen
    }

    static func drawBar(in rect: NSRect, percent: Double?,
                        trackColor: NSColor = NSColor.gray.withAlphaComponent(0.35)) {
        let radius = rect.height / 2
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard let percent else { return }
        let fraction = max(0, min(percent / 100, 1))
        guard fraction > 0 else { return }
        let width = max(rect.height, rect.width * fraction) // never narrower than a dot
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        color(forPercent: percent).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    /// Small bar for the status-item title (inline NSTextAttachment image).
    /// Drawn via handler so it adapts to menu bar appearance at draw time.
    static func statusBarImage(percent: Double?,
                               size: NSSize = NSSize(width: 36, height: 7)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            drawBar(in: rect, percent: percent)
            return true
        }
    }

    /// Two-row "5h / wk" widget for the Control Strip button. Touch Bar is
    /// always dark, so colors are fixed.
    static func touchBarStripImage(fiveHour: Double?, weekly: Double?) -> NSImage {
        let size = NSSize(width: 96, height: 26)
        return NSImage(size: size, flipped: false) { _ in
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            let labelAttributes: [NSAttributedString.Key: Any] =
                [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
            let valueAttributes: [NSAttributedString.Key: Any] =
                [.font: font, .foregroundColor: NSColor.white]
            func row(y: CGFloat, label: String, percent: Double?) {
                (label as NSString).draw(at: NSPoint(x: 0, y: y), withAttributes: labelAttributes)
                drawBar(in: NSRect(x: 16, y: y + 2, width: 48, height: 6), percent: percent,
                        trackColor: NSColor.white.withAlphaComponent(0.25))
                let text = percent.map { "\(Int($0.rounded()))%" } ?? "–%"
                (text as NSString).draw(at: NSPoint(x: 68, y: y), withAttributes: valueAttributes)
            }
            row(y: 14, label: "5h", percent: fiveHour)
            row(y: 1, label: "wk", percent: weekly)
            return true
        }
    }

    /// Single-row "label [bar] 31% suffix" image for the modal Touch Bar.
    static func touchBarRowImage(label: String, percent: Double?, suffix: String? = nil) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let labelAttributes: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
        let valueAttributes: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: NSColor.white]
        let percentText = percent.map { "\(Int($0.rounded()))%" } ?? "–%"
        let labelWidth = (label as NSString).size(withAttributes: labelAttributes).width
        let percentWidth = (percentText as NSString).size(withAttributes: valueAttributes).width
        let suffixText = suffix.map { " " + $0 }
        let suffixWidth = (suffixText as NSString?)?.size(withAttributes: labelAttributes).width ?? 0
        let barWidth: CGFloat = 44
        let gap: CGFloat = 5
        let width = labelWidth + gap + barWidth + gap + percentWidth + suffixWidth + 2
        let size = NSSize(width: ceil(width), height: 18)
        return NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            (label as NSString).draw(at: NSPoint(x: x, y: 2), withAttributes: labelAttributes)
            x += labelWidth + gap
            drawBar(in: NSRect(x: x, y: 5, width: barWidth, height: 7), percent: percent,
                    trackColor: NSColor.white.withAlphaComponent(0.25))
            x += barWidth + gap
            (percentText as NSString).draw(at: NSPoint(x: x, y: 2), withAttributes: valueAttributes)
            x += percentWidth
            if let suffixText {
                (suffixText as NSString).draw(at: NSPoint(x: x, y: 2), withAttributes: labelAttributes)
            }
            return true
        }
    }
}
