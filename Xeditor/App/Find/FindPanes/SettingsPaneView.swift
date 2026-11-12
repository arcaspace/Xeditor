import AppKit

/// Settings tab: the handful of preferences that are not already exposed on
/// the Find pane — search history size and which text ⌘G uses.
@MainActor
final class SettingsPaneView: NSView, NSTextFieldDelegate {
    private let settings = FindSettings.shared
    private weak var controller: FindWindowController?

    private let historyField = FindUI.field()
    private let historyStepper = NSStepper()
    private let followSearchRadio: NSButton
    private let followSelectionRadio: NSButton

    private(set) var footerLeading: [NSView] = []
    private(set) var footerTrailing: [NSView] = []

    init(controller: FindWindowController) {
        self.controller = controller
        followSearchRadio = FindUI.radio("Use the last search term",
                                         target: nil, action: nil, on: true)
        followSelectionRadio = FindUI.radio("Use the selected text",
                                            target: nil, action: nil, on: false)

        super.init(frame: .zero)

        historyField.alignment = .right
        historyField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        historyField.target = self
        historyField.action = #selector(historyFieldChanged)
        historyField.delegate = self

        historyStepper.minValue = 5
        historyStepper.maxValue = 100
        historyStepper.increment = 5
        historyStepper.target = self
        historyStepper.action = #selector(historyStepperChanged)

        let clearHistory = FindUI.button("Clear History", target: self, action: #selector(clearHistory))
        let historyRow = FindUI.horizontal([FindUI.label("Max items:"),
                                            historyField, historyStepper,
                                            FindUI.spacer()], spacing: 8)
        let historyGroup = FindUI.group("Search history",
                                        [historyRow,
                                         FindUI.horizontal([clearHistory, FindUI.spacer()], spacing: 8)],
                                        spacing: 10)

        for radio in [followSearchRadio, followSelectionRadio] {
            radio.target = self
            radio.action = #selector(hotkeyModeChanged)
        }
        let hotkeyGroup = FindUI.group("⌘G behavior",
                                       [followSearchRadio, followSelectionRadio],
                                       spacing: 10)

        let stack = FindUI.vertical([historyGroup, hotkeyGroup],
                                    spacing: 14)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            historyGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotkeyGroup.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Settings

    func activate() {
        reload()
        window?.makeFirstResponder(historyField)
    }

    func reload() {
        historyField.stringValue = String(settings.historyLimit)
        historyStepper.integerValue = settings.historyLimit
        followSearchRadio.state = settings.hotkeyFollowsSelection ? .off : .on
        followSelectionRadio.state = settings.hotkeyFollowsSelection ? .on : .off
    }

    /// Changes take effect immediately; the history field also commits when it
    /// loses focus, so an edit made without pressing Return is not lost.
    private func commitHistoryLimit() {
        let value = max(5, min(100, Int(historyField.stringValue) ?? settings.historyLimit))
        guard value != settings.historyLimit else { return }
        settings.historyLimit = value
        settings.applyHistoryLimit()
        controller?.reloadHistories()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === historyField else { return }
        commitHistoryLimit()
        reload()
    }

    @objc private func historyFieldChanged() {
        commitHistoryLimit()
        reload()
    }

    @objc private func historyStepperChanged() {
        settings.historyLimit = historyStepper.integerValue
        settings.applyHistoryLimit()
        reload()
        controller?.reloadHistories()
    }

    @objc private func hotkeyModeChanged() {
        settings.hotkeyFollowsSelection = followSelectionRadio.state == .on
        followSearchRadio.state = settings.hotkeyFollowsSelection ? .off : .on
        followSelectionRadio.state = settings.hotkeyFollowsSelection ? .on : .off
    }

    @objc private func clearHistory() {
        controller?.clearHistory()
    }
}
