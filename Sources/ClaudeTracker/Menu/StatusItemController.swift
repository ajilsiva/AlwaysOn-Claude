import AppKit

/// Owns the NSStatusItem; renders the compact "◐ 42% · 89%" title
/// (5h utilization · context %) and hosts the dropdown menu.
final class StatusItemController {
    private let item: NSStatusItem
    private let state: AppState
    let menuBuilder: MenuBuilder

    init(state: AppState) {
        self.state = state
        self.menuBuilder = MenuBuilder(state: state)
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menuBuilder.menu
        render()
    }

    /// "✳︎ [▰▰▰▱▱] 31% · 62%" — glyph (☕︎ while Wake is on), drawn 5-hour bar,
    /// then 5h and weekly percentages.
    func render() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString()

        let glyph = state.wakeEnabled ? "☕\u{FE0E} " : "✳\u{FE0E} "
        title.append(NSAttributedString(
            string: glyph,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]))

        let barSize = NSSize(width: 36, height: 7)
        let attachment = NSTextAttachment()
        attachment.image = BarRenderer.statusBarImage(percent: state.usage.fiveHourPercent,
                                                      size: barSize)
        attachment.bounds = NSRect(x: 0, y: 1, width: barSize.width, height: barSize.height)
        title.append(NSAttributedString(attachment: attachment))

        title.append(NSAttributedString(
            string: " \(Format.percent(state.usage.fiveHourPercent))",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        title.append(NSAttributedString(
            string: " · \(Format.percent(state.usage.sevenDayPercent))",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))

        item.button?.attributedTitle = title
        item.button?.toolTip = tooltip()
        menuBuilder.update()
    }

    private func tooltip() -> String {
        var parts: [String] = []
        if let model = state.session.modelId { parts.append(Format.modelDisplayName(model)) }
        if let u = state.usage.fiveHourPercent { parts.append("5h \(Format.percent(u))") }
        if let w = state.usage.sevenDayPercent { parts.append("week \(Format.percent(w))") }
        if let c = state.session.contextPercent { parts.append("ctx \(Format.percent(c))") }
        if state.wakeEnabled { parts.append("awake") }
        return parts.isEmpty ? "Claude Tracker" : parts.joined(separator: " · ")
    }
}
