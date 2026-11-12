import AppKit

/// Settings tab, mirroring notepad--: history size, how result lines are
/// shown, and what the ⌘G / ⇧⌘G hotkeys search for.
@MainActor
final class SettingsPaneView: NSView {
    private let settings = FindSettings.shared
    private weak var controller: FindWindowController?

    private let historyField = FindUI.field()
    private let historyStepper = NSStepper()
    private let fullLineRadio: NSButton
    private let contextRadio: NSButton
    private let lengthField = FindUI.field()
    private let lengthStepper = NSStepper()
    private let followSearchRadio: NSButton
    private let followSelectionRadio: NSButton
    private let wordBox: NSButton
    private let caseBox: NSButton

    init(controller: FindWindowController) {
        self.controller = controller
        fullLineRadio = FindUI.radio("Show the whole line containing the result (not recommended for long lines)",
                                     target: nil, action: nil, on: false)
        contextRadio = FindUI.radio("Show the text around the result",
                                    target: nil, action: nil, on: true)
        followSearchRadio = FindUI.radio("Use the text from the last search",
                                         target: nil, action: nil, on: true)
        followSelectionRadio = FindUI.radio("Use the current selection",
                                            target: nil, action: nil, on: false)
        wordBox = FindUI.checkbox("Whole word", target: nil, action: nil, on: false)
        caseBox = FindUI.checkbox("Match case", target: nil, action: nil, on: false)

        super.init(frame: .zero)

        historyField.alignment = .right
        historyField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        historyField.target = self
        historyField.action = #selector(historyFieldChanged)

        historyStepper.minValue = 5
        historyStepper.maxValue = 100
        historyStepper.increment = 5
        historyStepper.target = self
        historyStepper.action = #selector(historyStepperChanged)

        let clearHistory = FindUI.button("Clear History", target: self, action: #selector(clearHistory))
        let historyRow = FindUI.horizontal([FindUI.sectionLabel("Max history items:"),
                                            historyField, historyStepper,
                                            FindUI.label("(5–100)"),
                                            clearHistory], spacing: 8)
        historyRow.arrangedSubviews[3].setContentHuggingPriority(.required, for: .horizontal)

        for radio in [fullLineRadio, contextRadio] {
            radio.target = self
            radio.action = #selector(resultModeChanged)
        }
        lengthField.alignment = .right
        lengthField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        lengthField.target = self
        lengthField.action = #selector(lengthFieldChanged)

        lengthStepper.minValue = 20
        lengthStepper.maxValue = 500
        lengthStepper.increment = 10
        lengthStepper.target = self
        lengthStepper.action = #selector(lengthStepperChanged)

        let lengthRow = FindUI.horizontal([contextRadio, lengthField, lengthStepper,
                                           FindUI.label("(20–500)")], spacing: 8)
        let displayGroup = FindUI.group("Result line display mode",
                                        [fullLineRadio, lengthRow], spacing: 14)

        for radio in [followSearchRadio, followSelectionRadio] {
            radio.target = self
            radio.action = #selector(hotkeyModeChanged)
        }
        for box in [wordBox, caseBox] {
            box.target = self
            box.action = #selector(findOptionsChanged)
        }
        let hotkeyOptions = FindUI.horizontal([wordBox, caseBox], spacing: 32)
        let hotkeyGroup = FindUI.group("Find hotkey behavior (⌘G ⇧⌘G)",
                                       [followSearchRadio, followSelectionRadio, hotkeyOptions],
                                       spacing: 12)

        let save = FindUI.button("Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let close = FindUI.button("Close", target: self, action: #selector(closePanel))
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = FindUI.horizontal([buttonSpacer, save, close], spacing: 10)

        let stack = FindUI.vertical([historyRow, displayGroup, hotkeyGroup, flexibleSpacer(), buttons],
                                    spacing: 18)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            displayGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hotkeyGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return spacer
    }

    func activate() {
        reload()
        window?.makeFirstResponder(historyField)
    }

    func reload() {
        historyField.stringValue = String(settings.historyLimit)
        historyStepper.integerValue = settings.historyLimit
        fullLineRadio.state = settings.resultFullLine ? .on : .off
        contextRadio.state = settings.resultFullLine ? .off : .on
        lengthField.stringValue = String(settings.resultPreviewLength)
        lengthField.doubleValue = Double(settings.resultPreviewLength)
        lengthStepper.integerValue = settings.resultPreviewLength
        followSearchRadio.state = settings.hotkeyFollowsSelection ? .off : .on
        followSelectionRadio.state = settings.hotkeyFollowsSelection ? .on : .off
        wordBox.state = settings.wholeWord ? .on : .off
        caseBox.state = settings.matchCase ? .on : .off
        updateEnabledState()
    }

    private func updateEnabledState() {
        lengthField.isEnabled = !settings.resultFullLine
        lengthStepper.isEnabled = !settings.resultFullLine
    }

    /// Commits whatever is in the fields, so edits made without pressing
    /// Return are not lost when Save is clicked.
    private func commitFields() {
        window?.makeFirstResponder(nil)
        settings.historyLimit = max(5, min(100, Int(historyField.stringValue) ?? settings.historyLimit))
        settings.resultPreviewLength = max(20, min(500, Int(lengthField.stringValue) ?? settings.resultPreviewLength))
        settings.applyHistoryLimit()
    }

    @objc private func historyFieldChanged() {
        settings.historyLimit = max(5, min(100, Int(historyField.stringValue) ?? settings.historyLimit))
        settings.applyHistoryLimit()
        reload()
        controller?.reloadHistories()
    }

    @objc private func historyStepperChanged() {
        settings.historyLimit = historyStepper.integerValue
        settings.applyHistoryLimit()
        reload()
        controller?.reloadHistories()
    }

    @objc private func resultModeChanged() {
        settings.resultFullLine = fullLineRadio.state == .on
        fullLineRadio.state = settings.resultFullLine ? .on : .off
        contextRadio.state = settings.resultFullLine ? .off : .on
        updateEnabledState()
    }

    @objc private func lengthFieldChanged() {
        settings.resultPreviewLength = max(20, min(500, Int(lengthField.stringValue) ?? settings.resultPreviewLength))
        reload()
    }

    @objc private func lengthStepperChanged() {
        settings.resultPreviewLength = lengthStepper.integerValue
        reload()
    }

    @objc private func hotkeyModeChanged() {
        settings.hotkeyFollowsSelection = followSelectionRadio.state == .on
        followSearchRadio.state = settings.hotkeyFollowsSelection ? .off : .on
        followSelectionRadio.state = settings.hotkeyFollowsSelection ? .on : .off
    }

    @objc private func findOptionsChanged() {
        settings.wholeWord = wordBox.state == .on
        settings.matchCase = caseBox.state == .on
        controller?.optionsDidChange()
    }

    @objc private func clearHistory() {
        controller?.clearHistory()
    }

    @objc private func save() {
        commitFields()
        reload()
        controller?.setStatus("Settings saved.", kind: .info)
    }

    @objc private func closePanel() {
        commitFields()
        controller?.closePanel()
    }
}
