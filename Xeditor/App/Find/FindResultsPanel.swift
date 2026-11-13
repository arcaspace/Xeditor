import AppKit

/// Gutter strip along the left of the results text. Draws a square +/- marker
/// per file group with a fold line running along its matches, like the editor's
/// fold margin, and toggles the group when its header row is clicked.
private final class FoldGutterView: NSView {
    struct LineRects {
        let headerLine: Int
        let header: NSRect
        let last: NSRect
        let expanded: Bool
    }

    var rectsProvider: (() -> [LineRects])?
    var onToggle: ((Int) -> Bool)?

    /// Match the text view's top-down coordinates so line rects line up.
    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let rects = rectsProvider?() else { return }
        for item in rects where point.y >= item.header.minY && point.y < item.header.maxY {
            _ = onToggle?(item.headerLine)
            return
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rects = rectsProvider?(), !rects.isEmpty else { return }
        let centerX = bounds.width - 14
        let side: CGFloat = 9
        // System colors so the markers follow the light and dark appearance.
        let fill = NSColor.textBackgroundColor
        let frameColor = NSColor.secondaryLabelColor

        for item in rects {
            let header = item.header
            let box = NSRect(x: centerX - side / 2, y: header.midY - side / 2,
                             width: side, height: side)

            // Same look as the editor's fold margin: outlined square with a
            // minus (expanded) or plus (collapsed) inside.
            let frame = NSBezierPath(rect: box)
            fill.setFill()
            frame.fill()
            frameColor.setStroke()
            frame.lineWidth = 1
            frame.stroke()

            let glyph = NSBezierPath()
            glyph.lineWidth = 1
            glyph.move(to: NSPoint(x: box.minX + 2, y: box.midY))
            glyph.line(to: NSPoint(x: box.maxX - 2, y: box.midY))
            if !item.expanded {
                glyph.move(to: NSPoint(x: box.midX, y: box.minY + 2))
                glyph.line(to: NSPoint(x: box.midX, y: box.maxY - 2))
            }
            frameColor.setStroke()
            glyph.stroke()

            if item.expanded, item.last.midY > box.maxY {
                let line = NSBezierPath()
                line.lineWidth = 1
                let endY = item.last.midY + 4
                line.move(to: NSPoint(x: centerX, y: box.maxY))
                line.line(to: NSPoint(x: centerX, y: endY))
                line.move(to: NSPoint(x: centerX, y: endY))
                line.line(to: NSPoint(x: centerX + 5, y: endY))
                frameColor.setStroke()
                line.stroke()
            }
        }
    }
}

/// Selectable text view for the results list; double-click or Return jumps to
/// the match under the cursor.
private final class ResultsTextView: NSTextView {
    var onActivate: ((Int) -> Void)?
    var onLayout: (() -> Void)?

    /// The Find panel is usually key when results appear; accept the click that
    /// brings the main window forward so selecting text works immediately.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            onActivate?(characterIndexForInsertion(at: point))
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
            onActivate?(selectedRange().location)
            return
        }
        super.keyDown(with: event)
    }
}

/// Search results docked at the bottom of the main window. The list is a
/// selectable text view (mouse selection and ⌘C work everywhere); file groups
/// fold with gutter +/- boxes, and double-clicking or Return jumps to a match.
@MainActor
final class FindResultsPanel: NSView {
    private let headerLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = ResultsTextView(frame: .zero)
    private let gutter = FoldGutterView()
    private var model: SearchResultsModel?
    /// Match shown on each rendered line (0-based), for click-to-jump.
    private var lineToMatch: [Int: SearchResultMatch] = [:]
    private var renderedLines = 0
    private var lineStarts: [Int] = []
    /// Folded file groups, their header line and the last line of the group.
    private var collapsedGroups: Set<ObjectIdentifier> = []
    private var headerLineToGroup: [Int: SearchResultGroup] = [:]
    private var foldSpans: [ObjectIdentifier: (header: Int, last: Int)] = [:]
    private var groupByID: [ObjectIdentifier: SearchResultGroup] = [:]

    /// Called when a result line is double-clicked or Return is pressed.
    var onJump: ((SearchResultMatch) -> Void)?
    /// Called when the panel's Close button is pressed.
    var onClose: (() -> Void)?

    var hitCount: Int { model?.totalHits ?? 0 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.stringValue = L("Search Results")

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1

        closeButton.title = L("Close")
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        let headerRow = FindUI.horizontal([headerLabel, spacer, closeButton], spacing: 8)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 30, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.onActivate = { [weak self] index in
            self?.activate(atCharacterIndex: index)
        }
        textView.onLayout = { [weak self] in
            self?.layoutGutter()
        }
        gutter.rectsProvider = { [weak self] in
            self?.gutterLineRects() ?? []
        }
        gutter.onToggle = { [weak self] line in
            self?.toggleGroup(atHeaderLine: line) ?? false
        }
        gutter.autoresizingMask = [.height]
        textView.addSubview(gutter)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        addSubview(headerRow)
        addSubview(summaryLabel)
        addSubview(scrollView)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            summaryLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 2),
            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layoutGutter()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderAll()
    }

    // MARK: - Contents

    func show(model: SearchResultsModel) {
        self.model = model
        collapsedGroups = []
        renderAll()
        updateHeader()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clear() {
        model = nil
        collapsedGroups = []
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        lineToMatch = [:]
        lineStarts = []
        headerLineToGroup = [:]
        foldSpans = [:]
        groupByID = [:]
        renderedLines = 0
        syncTextViewState()
        headerLabel.stringValue = L("No results.")
        summaryLabel.stringValue = ""
        summaryLabel.isHidden = true
    }

    /// Rebuilds the header and the rendered lines after a language change,
    /// keeping the current results and fold state.
    func applyLocalization() {
        closeButton.title = L("Close")
        updateHeader()
        renderAll()
    }

    private func renderAll() {
        guard let storage = textView.textStorage else { return }
        storage.setAttributedString(NSAttributedString(string: ""))
        lineToMatch = [:]
        lineStarts = []
        headerLineToGroup = [:]
        foldSpans = [:]
        groupByID = [:]
        renderedLines = 0
        guard let model else {
            syncTextViewState()
            return
        }
        for group in model.groups {
            let headerLine = renderedLines
            headerLineToGroup[headerLine] = group
            let id = ObjectIdentifier(group)
            groupByID[id] = group
            appendGroupHeader(group)
            guard !collapsedGroups.contains(id) else {
                foldSpans[id] = (headerLine, headerLine)
                continue
            }
            for match in group.matches {
                appendMatchLine(match)
            }
            foldSpans[id] = (headerLine, max(headerLine, renderedLines - 1))
        }
        syncTextViewState()
    }

    /// Positions the gutter strip over the left inset and refreshes it.
    private func syncTextViewState() {
        layoutGutter()
    }

    private func layoutGutter() {
        gutter.frame = NSRect(x: 0, y: 0, width: textView.textContainerInset.width,
                              height: max(textView.bounds.height, textView.frame.height))
        gutter.needsDisplay = true
    }

    /// Fold markers in text view coordinates, resolved from the current layout.
    private func gutterLineRects() -> [FoldGutterView.LineRects] {
        guard let lm = textView.layoutManager, let container = textView.textContainer else { return [] }
        lm.ensureLayout(for: container)
        let origin = textView.textContainerOrigin
        let string = textView.string as NSString

        func rect(forLine line: Int) -> NSRect? {
            guard line >= 0, line < lineStarts.count else { return nil }
            let charIndex = min(lineStarts[line], string.length)
            let glyph = lm.glyphIndexForCharacter(at: charIndex)
            if glyph >= lm.numberOfGlyphs {
                let extra = lm.extraLineFragmentRect
                return extra.isEmpty ? nil : extra.offsetBy(dx: origin.x, dy: origin.y)
            }
            return lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                .offsetBy(dx: origin.x, dy: origin.y)
        }

        return foldSpans.compactMap { id, span in
            guard let header = rect(forLine: span.header),
                  let last = rect(forLine: span.last) else { return nil }
            return FoldGutterView.LineRects(headerLine: span.header, header: header, last: last,
                                            expanded: !collapsedGroups.contains(id))
        }
    }

    private func updateHeader() {
        guard let model else {
            headerLabel.stringValue = L("No results.")
            summaryLabel.stringValue = ""
            summaryLabel.isHidden = true
            return
        }
        let hits = model.totalHits
        let files = model.groups.count
        headerLabel.stringValue = hits == 1
            ? L("Search Results — 1 hit")
            : LF("Search Results — %d hits", hits)
        let detail: String
        if hits == 1 {
            detail = files == 1
                ? LF("%@ — 1 hit in 1 file", model.querySummary)
                : LF("%@ — 1 hit in %d files", model.querySummary, files)
        } else {
            detail = files == 1
                ? LF("%@ — %d hits in 1 file", model.querySummary, hits)
                : LF("%@ — %d hits in %d files", model.querySummary, hits, files)
        }
        summaryLabel.stringValue = model.truncated ? detail + L("  (truncated)") : detail
        summaryLabel.isHidden = false
    }

    // MARK: - Rendering

    private func appendGroupHeader(_ group: SearchResultGroup, includeCount: Bool = true) {
        var title = group.displayName
        if includeCount {
            title += "  (\(group.matches.count))"
        }
        append(NSAttributedString(string: title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]), match: nil)
    }

    private func appendMatchLine(_ match: SearchResultMatch) {
        let line = NSMutableAttributedString(
            string: LF("Line %d:", match.line) + "  ",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
        line.append(NSAttributedString(string: match.preview, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]))
        line.append(NSAttributedString(string: "\n"))
        append(line, match: match)
    }

    private func append(_ text: NSAttributedString, match: SearchResultMatch?) {
        guard let storage = textView.textStorage else { return }
        lineStarts.append(storage.length)
        if let match {
            lineToMatch[renderedLines] = match
        }
        storage.append(text)
        renderedLines += 1
    }

    // MARK: - Jumping / folding

    /// Folds or unfolds the group whose header line was clicked in the gutter.
    private func toggleGroup(atHeaderLine line: Int) -> Bool {
        guard let group = headerLineToGroup[line] else { return false }
        let id = ObjectIdentifier(group)
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
        renderAll()
        updateHeader()
        return true
    }

    private func activate(atCharacterIndex index: Int) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let limit = min(max(index, 0), string.length)
        var line = 0
        for i in 0..<limit where string.character(at: i) == 10 {
            line += 1
        }
        guard let match = lineToMatch[line] else { return }
        onJump?(match)
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
