import AppKit

/// Side-by-side file comparison with synchronized scrolling. Rows are aligned
/// so a line removed from one file leaves a blank filler row on the other side,
/// keeping both panes on the same vertical grid.
@MainActor
final class CompareToolWindowController: ToolWindowController {
    private enum Source {
        case none
        case file(URL)
        case document(EditorDocument.ID)
    }

    private enum CompareError: LocalizedError {
        case missingSource(String)
        case unreadable(String)
        case documentClosed
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .missingSource(let side):
                return LF("Choose a file for the %@ pane first.", L(side))
            case .unreadable(let name):
                return LF("“%@” could not be decoded as text.", name)
            case .documentClosed:
                return L("That document is no longer open. Choose it again.")
            case .tooLarge:
                return L("The input is too large to compare (limit 60,000 lines or 20 MB per file).")
            }
        }
    }

    private let store: DocumentStore

    private let leftNameLabel = NSTextField(labelWithString: L("No file selected"))
    private let rightNameLabel = NSTextField(labelWithString: L("No file selected"))
    private let statsLabel = NSTextField(labelWithString: L("Choose two files to compare them."))
    private let compareButton = NSButton()
    private let ignoreWhitespaceCheckbox = NSButton(checkboxWithTitle: L("Ignore whitespace"),
                                                    target: nil, action: nil)
    private let ignoreCaseCheckbox = NSButton(checkboxWithTitle: L("Ignore case"),
                                              target: nil, action: nil)

    private let leftTextView = DiffTextView()
    private let rightTextView = DiffTextView()
    private let leftScroll = NSScrollView()
    private let rightScroll = NSScrollView()

    private var leftSource: Source = .none
    private var rightSource: Source = .none
    private var rows: [DiffRow] = []
    private var isSyncingScroll = false

    init(store: DocumentStore) {
        self.store = store
        super.init(title: L("Compare Files"),
                   size: NSSize(width: 1060, height: 680),
                   minSize: NSSize(width: 640, height: 320),
                   autosaveName: "XeditorCompareTool")
        buildUI()
        updateSourceLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func present() {
        if case .none = leftSource, let document = store.activeDocument {
            leftSource = .document(document.id)
            updateSourceLabels()
        }
        super.present()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let leftRow = makeSourceRow(title: L("Left"), nameLabel: leftNameLabel, tag: 0)
        let rightRow = makeSourceRow(title: L("Right"), nameLabel: rightNameLabel, tag: 1)

        compareButton.title = L("Compare")
        compareButton.bezelStyle = .rounded
        compareButton.target = self
        compareButton.action = #selector(compareAction)
        compareButton.keyEquivalent = "\r"

        let swapSources = ToolUI.button(L("Swap Sides"), target: self, action: #selector(swapSidesAction))

        ignoreWhitespaceCheckbox.target = self
        ignoreWhitespaceCheckbox.action = #selector(optionsChanged)
        ignoreCaseCheckbox.target = self
        ignoreCaseCheckbox.action = #selector(optionsChanged)

        statsLabel.font = NSFont.systemFont(ofSize: 11)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        statsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let optionsRow = NSStackView(views: [
            compareButton, swapSources, ignoreWhitespaceCheckbox, ignoreCaseCheckbox, statsLabel,
        ])
        optionsRow.orientation = .horizontal
        optionsRow.distribution = .fill
        optionsRow.alignment = .centerY
        optionsRow.spacing = 10

        let header = NSStackView(views: [leftRow, rightRow, optionsRow])
        header.orientation = .vertical
        header.distribution = .fill
        header.alignment = .leading
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)

        for row in [leftRow, rightRow, optionsRow] {
            row.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        }

        configureDiffTextView(leftTextView)
        configureDiffTextView(rightTextView)
        configureScroll(leftScroll, textView: leftTextView)
        configureScroll(rightScroll, textView: rightTextView)

        let divider = VerticalSeparatorView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        content.addSubview(leftScroll)
        content.addSubview(divider)
        content.addSubview(rightScroll)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            leftScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            leftScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            leftScroll.widthAnchor.constraint(equalTo: rightScroll.widthAnchor),

            divider.topAnchor.constraint(equalTo: leftScroll.topAnchor),
            divider.bottomAnchor.constraint(equalTo: leftScroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor),

            rightScroll.topAnchor.constraint(equalTo: leftScroll.topAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        for clip in [leftScroll.contentView, rightScroll.contentView] {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipViewBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    private func makeSourceRow(title: String, nameLabel: NSTextField, tag: Int) -> NSView {
        let titleLabel = ToolUI.sectionLabel(title)
        titleLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

        nameLabel.font = ToolUI.codeFont
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let current = ToolUI.button(L("Use Current Document"),
                                    target: self, action: #selector(useCurrentDocumentAction(_:)))
        current.controlSize = .small
        current.tag = tag

        let choose = ToolUI.button(L("Choose…"), target: self, action: #selector(chooseFileAction(_:)))
        choose.controlSize = .small
        choose.tag = tag

        let row = NSStackView(views: [titleLabel, nameLabel, current, choose])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func configureDiffTextView(_ textView: DiffTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = ToolUI.codeFont
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
    }

    private func configureScroll(_ scrollView: NSScrollView, textView: NSTextView) {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Sources

    @objc private func chooseFileAction(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = sender.tag == 0 ? L("Choose Left File") : L("Choose Right File")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setSource(.file(url), side: sender.tag)
    }

    @objc private func useCurrentDocumentAction(_ sender: NSButton) {
        guard let document = store.activeDocument else {
            NSSound.beep()
            showMessage(L("There is no open document to compare."), isError: true)
            return
        }
        setSource(.document(document.id), side: sender.tag)
    }

    private func setSource(_ source: Source, side: Int) {
        if side == 0 {
            leftSource = source
        } else {
            rightSource = source
        }
        updateSourceLabels()
    }

    private func updateSourceLabels() {
        leftNameLabel.stringValue = description(for: leftSource)
        leftNameLabel.toolTip = leftNameLabel.stringValue
        rightNameLabel.stringValue = description(for: rightSource)
        rightNameLabel.toolTip = rightNameLabel.stringValue
    }

    private func description(for source: Source) -> String {
        switch source {
        case .none:
            return L("No file selected")
        case .file(let url):
            return url.path
        case .document(let id):
            guard let document = store.documents.first(where: { $0.id == id }) else {
                return L("(document closed)")
            }
            return "\(document.url?.path ?? document.displayName) \(L("(open document)"))"
        }
    }

    // MARK: - Actions

    @objc private func swapSidesAction() {
        (leftSource, rightSource) = (rightSource, leftSource)
        updateSourceLabels()
        if hasSource(leftSource), hasSource(rightSource), !rows.isEmpty {
            compareAction()
        }
    }

    @objc private func optionsChanged() {
        if hasSource(leftSource), hasSource(rightSource), !rows.isEmpty {
            compareAction()
        }
    }

    @objc private func compareAction() {
        guard hasSource(leftSource) else {
            NSSound.beep()
            showMessage(CompareError.missingSource("Left").localizedDescription, isError: true)
            return
        }
        guard hasSource(rightSource) else {
            NSSound.beep()
            showMessage(CompareError.missingSource("Right").localizedDescription, isError: true)
            return
        }

        do {
            let left = try load(leftSource)
            let right = try load(rightSource)
            let leftLines = Self.lines(in: left.text)
            let rightLines = Self.lines(in: right.text)
            guard leftLines.count + rightLines.count <= 60_000 else {
                throw CompareError.tooLarge
            }

            let diff = LineDiff.rows(left: leftLines,
                                     right: rightLines,
                                     ignoreWhitespace: ignoreWhitespaceCheckbox.state == .on,
                                     ignoreCase: ignoreCaseCheckbox.state == .on)
            render(diff, leftName: left.name, rightName: right.name)
        } catch {
            showMessage(error.localizedDescription, isError: true)
        }
    }

    private func hasSource(_ source: Source) -> Bool {
        if case .none = source { return false }
        return true
    }

    private func load(_ source: Source) throws -> (name: String, text: String) {
        switch source {
        case .none:
            throw CompareError.missingSource("Left")
        case .file(let url):
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 20 * 1024 * 1024 else { throw CompareError.tooLarge }
            let data = try Data(contentsOf: url)
            guard let decoded = FileEncodingDetector.decode(data) else {
                throw CompareError.unreadable(url.lastPathComponent)
            }
            return (url.lastPathComponent, decoded.text)
        case .document(let id):
            guard let document = store.documents.first(where: { $0.id == id }) else {
                throw CompareError.documentClosed
            }
            let name = document.url?.lastPathComponent ?? document.displayName
            return (name, document.editor.text())
        }
    }

    private static func lines(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        // A trailing newline terminates the last line rather than starting an
        // empty one that the other file would not have.
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    // MARK: - Rendering

    private func render(_ rows: [DiffRow], leftName: String, rightName: String) {
        self.rows = rows
        leftTextView.show(rows: rows, side: .left)
        rightTextView.show(rows: rows, side: .right)

        let changed = rows.filter { $0.kind == .changed }.count
        let deleted = rows.filter { $0.kind == .deleted }.count
        let added = rows.filter { $0.kind == .added }.count

        window?.title = LF("Compare Files — %@ ↔ %@", leftName, rightName)

        if changed + deleted + added == 0 {
            showMessage(L("The two inputs are identical."), isError: false)
        } else {
            let key = changed + deleted + added == 1
                ? "1 differing line — %d removed, %d added, %d changed."
                : "%d differing lines — %d removed, %d added, %d changed."
            showMessage(LF(key, changed + deleted + added, deleted, added, changed),
                        isError: false)
        }

        scrollToFirstDifference()
    }

    private func scrollToFirstDifference() {
        guard let index = rows.firstIndex(where: { $0.kind != .same }) else {
            leftScroll.contentView.scroll(to: .zero)
            leftScroll.reflectScrolledClipView(leftScroll.contentView)
            return
        }
        let characterIndex = leftTextView.characterIndex(forRow: index)
        if let container = leftTextView.textContainer {
            leftTextView.layoutManager?.ensureLayout(for: container)
        }
        leftTextView.scrollRangeToVisible(NSRange(location: characterIndex, length: 0))
    }

    @objc private func clipViewBoundsChanged(_ notification: Notification) {
        guard !isSyncingScroll, let sourceClip = notification.object as? NSClipView else { return }
        let targetClip: NSClipView?
        if sourceClip === leftScroll.contentView {
            targetClip = rightScroll.contentView
        } else if sourceClip === rightScroll.contentView {
            targetClip = leftScroll.contentView
        } else {
            targetClip = nil
        }
        guard let targetClip else { return }

        var origin = targetClip.bounds.origin
        origin.y = sourceClip.bounds.origin.y
        isSyncingScroll = true
        targetClip.scroll(to: origin)
        targetClip.enclosingScrollView?.reflectScrolledClipView(targetClip)
        isSyncingScroll = false
    }

    private func showMessage(_ message: String, isError: Bool) {
        statsLabel.stringValue = message
        statsLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}

/// One-point divider between the two compare panes.
private final class VerticalSeparatorView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }
}
