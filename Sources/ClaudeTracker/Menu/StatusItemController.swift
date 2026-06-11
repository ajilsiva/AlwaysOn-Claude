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

    func render() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString()

        let utilization = state.usage.fiveHourPercent
        var utilizationColor = NSColor.labelColor
        if let u = utilization {
            if u >= 90 { utilizationColor = .systemRed }
            else if u >= 70 { utilizationColor = .systemOrange }
        }
        let wakeMark = state.wakeEnabled ? "☕ " : ""
        title.append(NSAttributedString(
            string: "\(wakeMark)◐ \(Format.percent(utilization))",
            attributes: [.font: font, .foregroundColor: utilizationColor]))

        if state.session.contextTokens != nil, case .active = state.session.activity {
            title.append(NSAttributedString(
                string: " · \(Format.percent(state.session.contextPercent))",
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        }

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
