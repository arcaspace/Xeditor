import AppKit

/// JSON / YAML / SQL structuring: pretty-print, compact JSON and push the
/// result back into the editor.
@MainActor
final class StructuredToolWindowController: ToolWindowController {
    /// Called after a result is written back to the editor so the main window
    /// can refresh its tab bar and status bar.
    var onEditorChanged: (() -> Void)?

    private let store: DocumentStore
    private let formatControl = NSSegmentedControl(labels: StructuredDataFormat.allCases.map(\.title),
                                                   trackingMode: .selectOne,
                                                   target: nil,
                                                   action: nil)
    private let inputTextView = ToolUI.makeTextView(editable: true)
    private let outputTextView = ToolUI.makeTextView(editable: false)
    private let statusLabel = ToolUI.label("", size: 11, color: .secondaryLabelColor)
    private let minifyButton = NSButton()

    init(store: DocumentStore) {
        self.store = store
        super.init(title: L("Structured Data"),
                   size: NSSize(width: 720, height: 620),
                   minSize: NSSize(width: 560, height: 460),
                   autosaveName: "XeditorStructuredDataTool")
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

        formatControl.selectedSegment = StructuredDataFormat.json.rawValue
        formatControl.target = self
        formatControl.action = #selector(formatKindChanged)

        let inputScroll = ToolUI.wrap(inputTextView)
        let outputScroll = ToolUI.wrap(outputTextView)
        inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let kindRow = NSStackView(views: [
            ToolUI.sectionLabel(L("Format")),
            formatControl,
            ToolUI.spacer(),
        ])
        kindRow.orientation = .horizontal
        kindRow.alignment = .centerY
        kindRow.spacing = 10

        let formatButton = ToolUI.button(L("Format"), target: self, action: #selector(formatAction))
        formatButton.toolTip = L("Pretty-print the input in the selected format.")

        minifyButton.title = L("Minify")
        minifyButton.bezelStyle = .rounded
        minifyButton.target = self
        minifyButton.action = #selector(minifyAction)
        minifyButton.toolTip = L("Remove insignificant whitespace (JSON only).")
        minifyButton.isEnabled = isMinifySupported

        let clearButton = ToolUI.button(L("Clear"), target: self, action: #selector(clearAction))

        let actionRow = NSStackView(views: [formatButton, minifyButton, clearButton, ToolUI.spacer()])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let applyButton = ToolUI.button(L("Apply to Editor"), target: self, action: #selector(applyToEditorAction))
        applyButton.toolTip = L("Replace the editor selection, or the whole document when nothing is selected.")

        let copyButton = ToolUI.button(L("Copy Result"), target: self, action: #selector(copyOutputAction))

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [applyButton, copyButton, ToolUI.spacer(), statusLabel])
        footerRow.orientation = .horizontal
        footerRow.distribution = .fill
        footerRow.alignment = .centerY
        footerRow.spacing = 8

        let stack = NSStackView(views: [
            kindRow,
            ToolUI.sectionLabel(L("Input")),
            inputScroll,
            actionRow,
            ToolUI.sectionLabel(L("Result")),
            outputScroll,
            footerRow,
        ])
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        for view in [kindRow, inputScroll, actionRow, outputScroll, footerRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            // Both panes share the window's spare height equally.
            inputScroll.heightAnchor.constraint(equalTo: outputScroll.heightAnchor),
        ])
    }

    // MARK: - Input

    private var selectedFormat: StructuredDataFormat {
        StructuredDataFormat(rawValue: formatControl.selectedSegment) ?? .json
    }

    private var isMinifySupported: Bool { selectedFormat.supportsMinify }

    /// Pulls the current editor selection in, falling back to the whole
    /// document when the selection is empty and the input is still blank.
    private func prefillFromEditor() {
        guard let editor = store.activeDocument?.editor else { return }
        let selection = editor.selectedText()
        if !selection.isEmpty, selection.utf16.count <= 2_000_000 {
            inputTextView.string = selection
            selectDetectedFormat(for: selection)
            showStatus(L("Loaded the editor selection."), isError: false)
            return
        }
        guard inputTextView.string.isEmpty else { return }
        let document = editor.text()
        guard !document.isEmpty, document.utf16.count <= 2_000_000 else { return }
        inputTextView.string = document
        selectDetectedFormat(for: document)
        showStatus(L("Loaded the active document."), isError: false)
    }

    private func selectDetectedFormat(for text: String) {
        let detected = StructuredDataFormat.detect(text)
        formatControl.selectedSegment = detected.rawValue
        minifyButton.isEnabled = detected.supportsMinify
    }

    // MARK: - Actions

    @objc private func formatKindChanged() {
        minifyButton.isEnabled = isMinifySupported
        showStatus("", isError: false)
    }

    @objc private func formatAction() {
        let input = inputTextView.string
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            showStatus(L("There is no input to format."), isError: true)
            return
        }
        let format = selectedFormat
        do {
            let result = try format.format(input)
            outputTextView.string = result
            showStatus(LF("Formatted %@.", format.title), isError: false)
        } catch let error as StructuredFormatError {
            NSSound.beep()
            showStatus("\(format.title): \(error.displayText)", isError: true)
        } catch {
            NSSound.beep()
            showStatus("\(format.title): \(error.localizedDescription)", isError: true)
        }
    }

    @objc private func minifyAction() {
        let format = selectedFormat
        guard format.supportsMinify else { return }
        let input = inputTextView.string
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            showStatus(L("There is no input to minify."), isError: true)
            return
        }
        do {
            let result = try format.minify(input)
            outputTextView.string = result
            showStatus(LF("Minified %@.", format.title), isError: false)
        } catch let error as StructuredFormatError {
            NSSound.beep()
            showStatus("\(format.title): \(error.displayText)", isError: true)
        } catch {
            NSSound.beep()
            showStatus("\(format.title): \(error.localizedDescription)", isError: true)
        }
    }

    @objc private func applyToEditorAction() {
        guard let editor = store.activeDocument?.editor else {
            NSSound.beep()
            showStatus(L("No document is open."), isError: true)
            return
        }
        let result = outputTextView.string
        guard !result.isEmpty else {
            NSSound.beep()
            showStatus(L("There is no result to apply."), isError: true)
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
            showStatus(L("The editor selection is not valid."), isError: true)
            return
        }

        let inserted = editor.replaceBytes(Data(result.utf8),
                                           inStart: start,
                                           inEnd: end,
                                           regex: false)
        guard inserted >= 0 else {
            NSSound.beep()
            showStatus(L("The editor rejected the replacement."), isError: true)
            return
        }
        editor.selectRange(start: start, end: start + inserted)
        onEditorChanged?()
        showStatus(wholeDocument
                    ? L("Applied to the whole document.")
                    : L("Applied to the editor selection."), isError: false)
    }

    @objc private func copyOutputAction() {
        let text = outputTextView.string
        guard !text.isEmpty else {
            NSSound.beep()
            showStatus(L("There is no result to copy."), isError: true)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showStatus(L("Result copied to the clipboard."), isError: false)
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
