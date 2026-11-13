import AppKit
import CryptoKit

enum HashAlgorithm: CaseIterable {
    case md5
    case sha1
    case sha256
    case sha512

    var title: String {
        switch self {
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        }
    }

    func hexDigest(of data: Data) -> String {
        switch self {
        case .md5: return Self.hex(Insecure.MD5.hash(data: data))
        case .sha1: return Self.hex(Insecure.SHA1.hash(data: data))
        case .sha256: return Self.hex(SHA256.hash(data: data))
        case .sha512: return Self.hex(SHA512.hash(data: data))
        }
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Hash calculator for the current selection, arbitrary text, or a file.
@MainActor
final class HashToolWindowController: ToolWindowController {
    private let store: DocumentStore
    private let inputTextView = ToolUI.makeTextView(editable: true)
    private let sourceLabel = ToolUI.label("", size: 11, color: .secondaryLabelColor)
    private let statusLabel = ToolUI.label("", size: 11, color: .secondaryLabelColor)
    private let spinner = NSProgressIndicator()
    private let hashFileButton = NSButton()
    private var hashTextButton = NSButton()
    private var resultFields: [HashAlgorithm: NSTextField] = [:]
    private var copyButtons: [HashAlgorithm: NSButton] = [:]
    private var hashes: [HashAlgorithm: String] = [:]
    private var isBusy = false

    init(store: DocumentStore) {
        self.store = store
        super.init(title: L("MD5 / SHA"),
                   size: NSSize(width: 700, height: 470),
                   minSize: NSSize(width: 520, height: 380),
                   autosaveName: "XeditorHashTool")
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

        let inputScroll = ToolUI.wrap(inputTextView)
        inputScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        hashTextButton = ToolUI.button(L("Hash Text"), target: self, action: #selector(hashTextAction))
        hashTextButton.keyEquivalent = "\r"

        hashFileButton.title = L("Hash File…")
        hashFileButton.bezelStyle = .rounded
        hashFileButton.target = self
        hashFileButton.action = #selector(hashFileAction)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let buttonRow = NSStackView(views: [hashTextButton, hashFileButton, ToolUI.spacer(), spinner])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var rows: [NSView] = [ToolUI.sectionLabel(L("Text to hash")), inputScroll, buttonRow]
        rows.append(sourceLabel)

        let separator = NSBox()
        separator.boxType = .separator
        rows.append(separator)

        var resultRows: [NSView] = []
        for (index, algorithm) in HashAlgorithm.allCases.enumerated() {
            resultRows.append(makeResultRow(algorithm, index: index))
        }
        let resultsStack = NSStackView(views: resultRows)
        resultsStack.orientation = .vertical
        resultsStack.distribution = .fill
        resultsStack.alignment = .leading
        resultsStack.spacing = 6

        rows.append(resultsStack)
        rows.append(statusLabel)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        // Vertical stack views only hug their arranged views along the cross
        // axis; give the full-width items an explicit width so they stretch.
        for view in [inputScroll, buttonRow, sourceLabel, separator, resultsStack, statusLabel] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for row in resultRows {
            row.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func makeResultRow(_ algorithm: HashAlgorithm, index: Int) -> NSView {
        let name = ToolUI.label(algorithm.title, size: 12, weight: .semibold)
        name.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        name.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let field = NSTextField(labelWithString: "—")
        field.font = ToolUI.codeFont
        field.isSelectable = true
        field.usesSingleLineMode = false
        field.lineBreakMode = .byCharWrapping
        field.maximumNumberOfLines = 2
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.textColor = .labelColor
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        resultFields[algorithm] = field

        let copy = ToolUI.button(L("Copy"), target: self, action: #selector(copyHash(_:)))
        copy.tag = index
        copy.controlSize = .small
        copy.isEnabled = false
        copy.widthAnchor.constraint(equalToConstant: 60).isActive = true
        copyButtons[algorithm] = copy

        let row = NSStackView(views: [name, field, copy])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    // MARK: - Actions

    private func prefillFromEditorSelection() {
        guard let editor = store.activeDocument?.editor else { return }
        let selection = editor.selectedText()
        guard !selection.isEmpty, selection.count <= 1_000_000 else { return }
        inputTextView.string = selection
        sourceLabel.stringValue = LF("Source: editor selection (%d characters)", selection.count)
        hashTextAction()
    }

    @objc private func hashTextAction() {
        guard !isBusy else { return }
        let text = inputTextView.string
        guard !text.isEmpty else {
            showStatus(L("Nothing to hash."), isError: true)
            NSSound.beep()
            return
        }
        let data = Data(text.utf8)
        var values: [HashAlgorithm: String] = [:]
        for algorithm in HashAlgorithm.allCases {
            values[algorithm] = algorithm.hexDigest(of: data)
        }
        let sourceKey = data.count == 1
            ? "Source: 1 byte of UTF-8 text"
            : "Source: %d bytes of UTF-8 text"
        apply(values, source: LF(sourceKey, data.count))
    }

    @objc private func hashFileAction() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L("Hash File")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        hashFile(at: url)
    }

    private func hashFile(at url: URL) {
        setBusy(true)
        showStatus(LF("Hashing %@…", url.lastPathComponent), isError: false)

        Task.detached(priority: .userInitiated) {
            let result = Self.computeHashes(of: url)
            await MainActor.run { [weak self] in
                self?.finishFileHash(result, url: url)
            }
        }
    }

    private nonisolated static func computeHashes(of url: URL) -> Result<[HashAlgorithm: String], Error> {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var md5 = Insecure.MD5()
            var sha1 = Insecure.SHA1()
            var sha256 = SHA256()
            var sha512 = SHA512()

            while true {
                guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
                md5.update(data: chunk)
                sha1.update(data: chunk)
                sha256.update(data: chunk)
                sha512.update(data: chunk)
            }

            return .success([
                .md5: HashAlgorithm.hex(md5.finalize()),
                .sha1: HashAlgorithm.hex(sha1.finalize()),
                .sha256: HashAlgorithm.hex(sha256.finalize()),
                .sha512: HashAlgorithm.hex(sha512.finalize()),
            ])
        } catch {
            return .failure(error)
        }
    }

    private func finishFileHash(_ result: Result<[HashAlgorithm: String], Error>, url: URL) {
        setBusy(false)
        switch result {
        case .success(let values):
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue
            let sizeText = size.map { " · " + LF("%d bytes", $0) } ?? ""
            apply(values, source: LF("Source: %@", url.lastPathComponent + sizeText))
        case .failure(let error):
            showStatus(LF("Could not hash %@: %@", url.lastPathComponent, error.localizedDescription), isError: true)
        }
    }

    @objc private func copyHash(_ sender: NSButton) {
        let algorithms = HashAlgorithm.allCases
        guard sender.tag >= 0, sender.tag < algorithms.count else { return }
        let algorithm = algorithms[sender.tag]
        guard let hash = hashes[algorithm] else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hash, forType: .string)
        showStatus(LF("%@ copied to the clipboard.", algorithm.title), isError: false)
    }

    // MARK: - Helpers

    private func apply(_ values: [HashAlgorithm: String], source: String) {
        hashes = values
        sourceLabel.stringValue = source
        for algorithm in HashAlgorithm.allCases {
            let hash = values[algorithm] ?? ""
            let field = resultFields[algorithm]
            field?.stringValue = Self.display(hash)
            field?.toolTip = hash
            copyButtons[algorithm]?.isEnabled = !hash.isEmpty
        }
        showStatus(L("Computed MD5, SHA-1, SHA-256 and SHA-512."), isError: false)
    }

    /// SHA-512 is 128 characters; showing it in two halves keeps the window
    /// narrow while still displaying the whole digest.
    private static func display(_ hash: String) -> String {
        guard hash.count > 64 else { return hash }
        var lines: [String] = []
        var index = hash.startIndex
        while index < hash.endIndex {
            let end = hash.index(index, offsetBy: 64, limitedBy: hash.endIndex) ?? hash.endIndex
            lines.append(String(hash[index..<end]))
            index = end
        }
        return lines.joined(separator: "\n")
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        hashTextButton.isEnabled = !busy
        hashFileButton.isEnabled = !busy
        if busy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
