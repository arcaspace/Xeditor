import AppKit

enum ConversionDirection: Int, CaseIterable {
    case jsonToYAML
    case yamlToJSON

    var title: String {
        switch self {
        case .jsonToYAML: return "JSON → YAML"
        case .yamlToJSON: return "YAML → JSON"
        }
    }

    var sourceName: String { self == .jsonToYAML ? "JSON" : "YAML" }
    var targetName: String { self == .jsonToYAML ? "YAML" : "JSON" }

    /// Converts text, throwing `StructuredFormatError` with line information.
    static func convert(_ text: String, direction: ConversionDirection) throws -> String {
        switch direction {
        case .jsonToYAML:
            let value = try JSONFormatter.parse(text)
            return YAMLEmitter.emit(value)
        case .yamlToJSON:
            let value = try YAMLParser.parse(text)
            return JSONEmitter.emit(value)
        }
    }

    /// Picks a direction from the text itself: JSON starts with `{` or `[`.
    static func detect(_ text: String) -> ConversionDirection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return .jsonToYAML }
        return .yamlToJSON
    }
}

/// JSON ⇄ YAML conversion window.
@MainActor
final class ConversionToolWindowController: ToolWindowController {
    var onEditorChanged: (() -> Void)?

    private let store: DocumentStore
    private let directionControl = NSSegmentedControl(
        labels: ConversionDirection.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil)
    private let inputTextView = ToolUI.makeTextView(editable: true)
    private let outputTextView = ToolUI.makeTextView(editable: false)
    private let statusLabel = ToolUI.label("", size: 11, color: .secondaryLabelColor)

    init(store: DocumentStore) {
        self.store = store
        super.init(title: "JSON ⇄ YAML",
                   size: NSSize(width: 720, height: 620),
                   minSize: NSSize(width: 560, height: 460),
                   autosaveName: "XeditorJSONYAMLTool")
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func present() {
        prefillFromEditor()
        super.present()
    }

    override func firstResponderView() -> NSView? {
        inputTextView
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        outputTextView.drawsBackground = true
        outputTextView.backgroundColor = .textBackgroundColor

        directionControl.selectedSegment = ConversionDirection.jsonToYAML.rawValue
        directionControl.target = self
        directionControl.action = #selector(directionChanged)

        let inputScroll = ToolUI.wrap(inputTextView)
        let outputScroll = ToolUI.wrap(outputTextView)
        inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let directionRow = NSStackView(views: [
            ToolUI.sectionLabel("Direction"),
            directionControl,
            ToolUI.spacer(),
        ])
        directionRow.orientation = .horizontal
        directionRow.alignment = .centerY
        directionRow.spacing = 10

        let convertButton = ToolUI.button("Convert", target: self, action: #selector(convertAction))
        convertButton.toolTip = "Parse the input and emit the other format."

        let swapButton = ToolUI.button("Swap", target: self, action: #selector(swapAction))
        swapButton.toolTip = "Move the result into the input and reverse the direction."

        let clearButton = ToolUI.button("Clear", target: self, action: #selector(clearAction))

        let actionRow = NSStackView(views: [convertButton, swapButton, clearButton, ToolUI.spacer()])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let applyButton = ToolUI.button("Apply to Editor", target: self, action: #selector(applyToEditorAction))
        applyButton.toolTip = "Replace the editor selection, or the whole document when nothing is selected."

        let copyButton = ToolUI.button("Copy Result", target: self, action: #selector(copyOutputAction))

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [applyButton, copyButton, ToolUI.spacer(), statusLabel])
        footerRow.orientation = .horizontal
        footerRow.distribution = .fill
        footerRow.alignment = .centerY
        footerRow.spacing = 8

        let stack = NSStackView(views: [
            directionRow,
            ToolUI.sectionLabel("Input"),
            inputScroll,
            actionRow,
            ToolUI.sectionLabel("Result"),
            outputScroll,
            footerRow,
        ])
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for view in [directionRow, inputScroll, actionRow, outputScroll, footerRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            inputScroll.heightAnchor.constraint(equalTo: outputScroll.heightAnchor),
        ])
    }

    // MARK: - Input

    private var direction: ConversionDirection {
        ConversionDirection(rawValue: directionControl.selectedSegment) ?? .jsonToYAML
    }

    private func prefillFromEditor() {
        guard let editor = store.activeDocument?.editor else { return }
        let selection = editor.selectedText()
        if !selection.isEmpty, selection.utf16.count <= 2_000_000 {
            inputTextView.string = selection
            selectDetectedDirection(for: selection)
            showStatus("Loaded the editor selection.", isError: false)
            return
        }
        guard inputTextView.string.isEmpty else { return }
        let document = editor.text()
        guard !document.isEmpty, document.utf16.count <= 2_000_000 else { return }
        inputTextView.string = document
        selectDetectedDirection(for: document)
        showStatus("Loaded the active document.", isError: false)
    }

    private func selectDetectedDirection(for text: String) {
        directionControl.selectedSegment = ConversionDirection.detect(text).rawValue
    }

    // MARK: - Actions

    @objc private func directionChanged() {
        showStatus("", isError: false)
    }

    @objc private func convertAction() {
        performConversion()
    }

    @discardableResult
    private func performConversion() -> Bool {
        let input = inputTextView.string
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            showStatus("There is no input to convert.", isError: true)
            return false
        }
        let selected = direction
        do {
            let result = try ConversionDirection.convert(input, direction: selected)
            outputTextView.string = result
            showStatus("Converted \(selected.sourceName) to \(selected.targetName).", isError: false)
            return true
        } catch let error as StructuredFormatError {
            NSSound.beep()
            showStatus("\(selected.sourceName): \(error.displayText)", isError: true)
            return false
        } catch {
            NSSound.beep()
            showStatus("\(selected.sourceName): \(error.localizedDescription)", isError: true)
            return false
        }
    }

    @objc private func swapAction() {
        let result = outputTextView.string
        guard !result.isEmpty else {
            NSSound.beep()
            showStatus("There is no result to swap.", isError: true)
            return
        }
        inputTextView.string = result
        outputTextView.string = ""
        directionControl.selectedSegment = (direction == .jsonToYAML ? ConversionDirection.yamlToJSON : .jsonToYAML).rawValue
        showStatus("Swapped direction.", isError: false)
        performConversion()
    }

    @objc private func applyToEditorAction() {
        guard let editor = store.activeDocument?.editor else {
            NSSound.beep()
            showStatus("No document is open.", isError: true)
            return
        }
        let result = outputTextView.string
        guard !result.isEmpty else {
            NSSound.beep()
            showStatus("There is no result to apply.", isError: true)
            return
        }

        var start = editor.selectionStart
        var end = editor.selectionEnd
        let wholeDocument = start == end
        if wholeDocument {
            start = 0
            end = editor.documentLength
        }
        guard end >= start else {
            NSSound.beep()
            showStatus("The editor selection is not valid.", isError: true)
            return
        }

        let inserted = editor.replaceBytes(Data(result.utf8),
                                           inStart: start,
                                           inEnd: end,
                                           regex: false)
        guard inserted >= 0 else {
            NSSound.beep()
            showStatus("The editor rejected the replacement.", isError: true)
            return
        }
        editor.selectRange(start: start, end: start + inserted)
        onEditorChanged?()
        showStatus(wholeDocument
                    ? "Applied to the whole document."
                    : "Applied to the editor selection.", isError: false)
    }

    @objc private func copyOutputAction() {
        let text = outputTextView.string
        guard !text.isEmpty else {
            NSSound.beep()
            showStatus("There is no result to copy.", isError: true)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showStatus("Result copied to the clipboard.", isError: false)
    }

    @objc private func clearAction() {
        inputTextView.string = ""
        outputTextView.string = ""
        showStatus("", isError: false)
    }

    // MARK: - Status

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
