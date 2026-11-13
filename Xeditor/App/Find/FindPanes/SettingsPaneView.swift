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
    private let historyHeader = FindUI.sectionHeader(L("Search History"))
    private let hotkeyHeader = FindUI.sectionHeader(L("⌘G Behavior"))
    private let maxItemsLabel = FindUI.inlineLabel(L("Max items:"))
    private let clearHistoryButton = FindUI.button(L("Clear History"), target: nil, action: nil)

    private(set) var footerLeading: [NSView] = []
    private(set) var footerTrailing: [NSView] = []

    init(controller: FindWindowController) {
        self.controller = controller
        followSearchRadio = FindUI.radio(L("Use the last search term"),
                                         target: nil, action: nil, on: true)
        followSelectionRadio = FindUI.radio(L("Use the selected text"),
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

        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistory)
        clearHistoryButton.controlSize = .small
        clearHistoryButton.font = .systemFont(ofSize: 11)
        let historyRow = FindUI.horizontal([maxItemsLabel,
                                            historyField, historyStepper,
                                            FindUI.spacer(), clearHistoryButton], spacing: 8)

        for radio in [followSearchRadio, followSelectionRadio] {
            radio.target = self
            radio.action = #selector(hotkeyModeChanged)
            radio.font = .systemFont(ofSize: 11)
            radio.controlSize = .small
        }
        let radios = FindUI.verticalFill([followSearchRadio, followSelectionRadio], spacing: 8)

        let stack = FindUI.verticalFill([historyHeader, FindUI.rule(),
                                         historyRow,
                                         hotkeyHeader, FindUI.rule(),
                                         radios],
                                        spacing: 8)
        stack.setCustomSpacing(16, after: historyRow)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
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

    func applyLocalization() {
        historyHeader.stringValue = L("Search History")
        hotkeyHeader.stringValue = L("⌘G Behavior")
        maxItemsLabel.stringValue = L("Max items:")
        clearHistoryButton.title = L("Clear History")
        followSearchRadio.title = L("Use the last search term")
        followSelectionRadio.title = L("Use the selected text")
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
