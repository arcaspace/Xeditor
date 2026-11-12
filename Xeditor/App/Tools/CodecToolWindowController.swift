import AppKit

/// Base64 and URL percent-encoding/decoding for text in either the editor
/// selection or the tool's own input area.
@MainActor
final class CodecToolWindowController: ToolWindowController {
    private let store: DocumentStore
    private let inputTextView = ToolUI.makeTextView(editable: true)
    private let outputTextView = ToolUI.makeTextView(editable: false)
    private let statusLabel = ToolUI.label("", size: 11, color: .secondaryLabelColor)
    private let swapButton = NSButton()
    private let copyButton = NSButton()

    /// RFC 3986 unreserved characters: everything else is percent-encoded,
    /// including non-ASCII text (encoded as UTF-8 bytes).
    private static let urlAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    init(store: DocumentStore) {
        self.store = store
        super.init(title: "Base64 / URL",
                   size: NSSize(width: 620, height: 540),
                   minSize: NSSize(width: 480, height: 400),
                   autosaveName: "XeditorCodecTool")
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func present() {
        prefillFromEditorSelection()
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

        let inputScroll = ToolUI.wrap(inputTextView)
        let outputScroll = ToolUI.wrap(outputTextView)
        inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let base64Encode = ToolUI.button("Base64 Encode", target: self, action: #selector(base64EncodeAction))
        let base64Decode = ToolUI.button("Base64 Decode", target: self, action: #selector(base64DecodeAction))
        let urlEncode = ToolUI.button("URL Encode", target: self, action: #selector(urlEncodeAction))
        let urlDecode = ToolUI.button("URL Decode", target: self, action: #selector(urlDecodeAction))

        let convertRow = NSStackView(views: [base64Encode, base64Decode, urlEncode, urlDecode, ToolUI.spacer()])
        convertRow.orientation = .horizontal
        convertRow.distribution = .fill
        convertRow.alignment = .centerY
        convertRow.spacing = 8

        swapButton.title = "Move Output Up"
        swapButton.bezelStyle = .rounded
        swapButton.target = self
        swapButton.action = #selector(swapAction)

        let clearButton = ToolUI.button("Clear", target: self, action: #selector(clearAction))

        copyButton.title = "Copy Result"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyOutputAction)

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerRow = NSStackView(views: [swapButton, clearButton, copyButton, ToolUI.spacer(), statusLabel])
        footerRow.orientation = .horizontal
        footerRow.distribution = .fill
        footerRow.alignment = .centerY
        footerRow.spacing = 8

        let stack = NSStackView(views: [
            ToolUI.sectionLabel("Input"),
            inputScroll,
            convertRow,
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

        for view in [inputScroll, convertRow, outputScroll, footerRow] {
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

    // MARK: - Actions

    private func prefillFromEditorSelection() {
        guard let editor = store.activeDocument?.editor else { return }
        let selection = editor.selectedText()
        guard !selection.isEmpty, selection.count <= 1_000_000 else { return }
        inputTextView.string = selection
        showStatus("Loaded the editor selection.", isError: false)
    }

    @objc private func base64EncodeAction() {
        let data = Data(inputTextView.string.utf8)
        setOutput(data.base64EncodedString(),
                  status: "Base64-encoded \(data.count) byte\(data.count == 1 ? "" : "s").")
    }

    @objc private func base64DecodeAction() {
        let compact = inputTextView.string
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard !compact.isEmpty else {
            NSSound.beep()
            showStatus("Nothing to decode.", isError: true)
            return
        }
        guard let data = Self.decodeBase64(compact) else {
            NSSound.beep()
            showStatus("The input is not valid Base64.", isError: true)
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        let validUTF8 = String(data: data, encoding: .utf8) != nil
        setOutput(text,
                  status: validUTF8
                    ? "Decoded \(data.count) byte\(data.count == 1 ? "" : "s")."
                    : "Decoded \(data.count) bytes; the result is not valid UTF-8 (invalid bytes were replaced).")
    }

    @objc private func urlEncodeAction() {
        let input = inputTextView.string
        guard let encoded = input.addingPercentEncoding(withAllowedCharacters: Self.urlAllowed) else {
            NSSound.beep()
            showStatus("The input could not be URL-encoded.", isError: true)
            return
        }
        setOutput(encoded, status: "Percent-encoded UTF-8 text.")
    }

    @objc private func urlDecodeAction() {
        guard let decoded = inputTextView.string.removingPercentEncoding else {
            NSSound.beep()
            showStatus("The input contains an invalid percent escape.", isError: true)
            return
        }
        setOutput(decoded, status: "Decoded percent escapes.")
    }

    @objc private func swapAction() {
        let result = outputTextView.string
        guard !result.isEmpty else {
            NSSound.beep()
            showStatus("There is no result to move up.", isError: true)
            return
        }
        let previousInput = inputTextView.string
        inputTextView.string = result
        outputTextView.string = previousInput
        showStatus("Swapped the result back into the input.", isError: false)
    }

    @objc private func clearAction() {
        inputTextView.string = ""
        outputTextView.string = ""
        showStatus("", isError: false)
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

    // MARK: - Helpers

    private func setOutput(_ text: String, status: String) {
        outputTextView.string = text
        showStatus(status, isError: false)
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private static func decodeBase64(_ string: String) -> Data? {
        if let data = Data(base64Encoded: string) { return data }
        // Accept the URL-safe alphabet as a convenience.
        var urlSafe = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while urlSafe.count % 4 != 0 {
            urlSafe += "="
        }
        return Data(base64Encoded: urlSafe)
    }
}
