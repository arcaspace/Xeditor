import AppKit

/// The main window surface the Find window talks to.
@MainActor
protocol FindHost: AnyObject {
    /// Current selection in the active editor, used to prefill the search box.
    var findHostSelectedText: String { get }
    /// Brings a document to the front (and focus it).
    func findHostReveal(documentID: EditorDocument.ID)
    /// Opens a file into a tab (or reuses the existing tab) and focuses it.
    func findHostOpenFile(_ url: URL)
    /// Redraws the active document's chrome after a replace.
    func findHostRefresh()
    /// Redraws everything (used after cross-document operations).
    func findHostRefreshAll()
    /// Returns keyboard focus to the active editor.
    func findHostFocusEditor()
    /// The results panel docked below the editor in the main window.
    var findHostResultsPanel: FindResultsPanel { get }
    /// Splits the editor area to show (or collapse) the results panel.
    func findHostSetResultsVisible(_ visible: Bool)
}

enum FindTab: Int, CaseIterable {
    case find
    case replace
    case mark
    case settings

    var title: String {
        switch self {
        case .find:     return L("Find")
        case .replace:  return L("Replace")
        case .mark:     return L("Mark")
        case .settings: return L("Settings")
        }
    }
}

/// Modeless Find/Replace window, modeled on notepad--'s dialog: a full-width
/// tab strip, two-column panes, and a separate results panel.
@MainActor
final class FindWindowController: NSObject, NSWindowDelegate {
    enum StatusKind {
        case info
        case warning
        case error
    }

    weak var host: FindHost?

    private let store: DocumentStore
    private let session: FindSession
    private let settings = FindSettings.shared

    private let panel: FindPanel
    private let tabControl: NSSegmentedControl
    private let paneContainer = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let footerBar = NSView()
    private let footerRule = FindUI.rule()
    private var footerStack: NSStackView?
    private var footerHeightConstraint: NSLayoutConstraint!
    private var paneConstraints: [FindTab: [NSLayoutConstraint]] = [:]

    private var findPane: FindPaneView!
    private var replacePane: ReplacePaneView!
    private var markPane: MarkPaneView!
    private var settingsPane: SettingsPaneView!

    /// Query that produced the current result list, for stale-result relocation.
    private var resultsQuery: SearchQuery?

    private static let currentDocumentLimit = 50_000
    private static let openDocumentsLimit = 50_000
    private static let confirmThreshold = 2_000

    init(store: DocumentStore, host: FindHost?) {
        self.store = store
        self.session = FindSession(store: store)
        self.host = host
        self.panel = FindPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 178),
                               styleMask: [.titled, .closable],
                               backing: .buffered,
                               defer: false)
        self.tabControl = NSSegmentedControl(labels: FindTab.allCases.map { $0.title },
                                             trackingMode: .selectOne,
                                             target: nil,
                                             action: nil)
        super.init()

        panel.title = L("Find and Replace")
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        panel.setFrameAutosaveName("XeditorFindWindow.v4")
        panel.contentMinSize = NSSize(width: 540, height: 160)

        findPane = FindPaneView(controller: self)
        replacePane = ReplacePaneView(controller: self)
        markPane = MarkPaneView(controller: self)
        settingsPane = SettingsPaneView(controller: self)

        tabControl.target = self
        tabControl.action = #selector(tabControlChanged)
        tabControl.segmentStyle = .rounded
        tabControl.controlSize = .small

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = panel.contentView ?? NSView()
        content.addSubview(tabControl)
        content.addSubview(paneContainer)
        content.addSubview(statusLabel)
        content.addSubview(footerBar)
        content.addSubview(footerRule)
        for view in [tabControl, paneContainer, statusLabel, footerBar, footerRule] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        for tab in FindTab.allCases {
            let paneView = self.view(for: tab)
            paneContainer.addSubview(paneView)
            paneView.translatesAutoresizingMaskIntoConstraints = false
            paneConstraints[tab] = [
                paneView.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                paneView.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                paneView.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                paneView.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor)
            ]
            paneView.isHidden = true
        }
        // Only the selected pane's constraints may size the window; hidden
        // panes would otherwise impose their own minimum height.
        NSLayoutConstraint.deactivate(paneConstraints.values.flatMap { $0 })

        footerHeightConstraint = footerBar.heightAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            paneContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 12),
            paneContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(equalToConstant: 14),
            statusLabel.bottomAnchor.constraint(equalTo: footerBar.topAnchor, constant: -4),

            footerBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footerHeightConstraint,

            footerRule.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footerRule.topAnchor.constraint(equalTo: footerBar.topAnchor),
            footerRule.heightAnchor.constraint(equalToConstant: 1)
        ])

        loadLastText()
        selectTab(rawValue: settings.lastTab, activate: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Panes

    private func pane(for tab: FindTab) -> FindPaneBase? {
        switch tab {
        case .find:      return findPane
        case .replace:   return replacePane
        case .mark:      return markPane
        case .settings:  return nil
        }
    }

    private func view(for tab: FindTab) -> NSView {
        if tab == .settings { return settingsPane }
        return pane(for: tab) ?? findPane
    }

    private var currentTab: FindTab {
        FindTab(rawValue: tabControl.selectedSegment) ?? .find
    }

    private var currentPane: FindPaneBase? { pane(for: currentTab) }

    /// Pane that supplies the query for actions that can also be triggered
    /// from the menu while the Settings tab is frontmost.
    private var queryPane: FindPaneBase { currentPane ?? findPane }

    // MARK: - Showing

    func showFind() { show(tab: .find) }
    func showReplace() { show(tab: .replace) }
    func showMark() { show(tab: .mark) }
    func showSettings() { show(tab: .settings) }

    func show(tab: FindTab) {
        let wasVisible = panel.isVisible
        selectTab(rawValue: tab.rawValue, activate: false)
        if !wasVisible {
            prefillFromSelectionOrHistory()
            if !panel.setFrameUsingName("XeditorFindWindow.v4") {
                panel.center()
            }
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        resizePanel(for: tab)
        view(for: tab).activateIfPossible()
    }

    private func selectTab(rawValue: Int, activate: Bool) {
        let tab = FindTab(rawValue: rawValue) ?? .find
        tabControl.selectedSegment = tab.rawValue
        settings.lastTab = tab.rawValue

        for candidate in FindTab.allCases {
            let paneView = view(for: candidate)
            let selected = candidate == tab
            paneView.isHidden = !selected
            let constraints = paneConstraints[candidate] ?? []
            if selected {
                NSLayoutConstraint.activate(constraints)
            } else {
                NSLayoutConstraint.deactivate(constraints)
            }
        }
        rebuildFooter(for: tab)
        setStatus("", kind: .info)
        resizePanel(for: tab)
        if activate, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            view(for: tab).activateIfPossible()
        }
    }

    @objc private func tabControlChanged() {
        selectTab(rawValue: tabControl.selectedSegment, activate: true)
    }

    // MARK: - Footer

    /// Rebuilds the bottom button row for the selected tab. Buttons belong to
    /// the panes; the window only lays them out.
    private func rebuildFooter(for tab: FindTab) {
        footerStack?.removeFromSuperview()
        let pane = view(for: tab)
        let leading: [NSView]
        let trailing: [NSView]
        if let base = pane as? FindPaneBase {
            leading = base.footerLeading
            trailing = base.footerTrailing
        } else if let settings = pane as? SettingsPaneView {
            leading = settings.footerLeading
            trailing = settings.footerTrailing
        } else {
            leading = []
            trailing = []
        }
        let hasFooter = !leading.isEmpty || !trailing.isEmpty
        footerRule.isHidden = !hasFooter
        guard hasFooter else {
            footerHeightConstraint.constant = 0
            footerStack = nil
            return
        }

        footerHeightConstraint.constant = 40
        let stack = NSStackView(views: leading + [FindUI.spacer()] + trailing)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        footerBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])
        footerStack = stack
    }

    /// Keeps the panel height matched to the selected tab's content.
    private func resizePanel(for tab: FindTab) {
        guard panel.isVisible else { return }
        var frame = panel.frame
        let currentContentHeight = panel.contentRect(forFrameRect: frame).height
        let target = tab.preferredContentHeight
        guard abs(currentContentHeight - target) > 0.5 else { return }
        frame.size.height += target - currentContentHeight
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.height > visible.height - 40 {
                frame.size.height = visible.height - 40
            }
            if frame.maxY > visible.maxY {
                frame.origin.y = visible.maxY - frame.height
            }
            if frame.minY < visible.minY {
                frame.origin.y = visible.minY
            }
        }
        panel.setFrame(frame, display: true)
    }

    private func loadLastText() {
        let panes: [FindPaneBase] = [findPane, replacePane, markPane]
        if !settings.lastQuery.isEmpty {
            for pane in panes {
                pane.searchField.stringValue = settings.lastQuery
            }
        }
        if !settings.lastReplacement.isEmpty {
            replacePane.replacementField?.stringValue = settings.lastReplacement
        }
    }

    private func prefillFromSelectionOrHistory() {
        let selected = (host?.findHostSelectedText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = !selected.isEmpty && !selected.contains("\n") && selected.count <= 300
        let text = usable ? selected : settings.lastQuery
        let panes: [FindPaneBase] = [findPane, replacePane, markPane]
        for pane in panes {
            pane.searchField.stringValue = text
        }
        if !settings.lastReplacement.isEmpty {
            replacePane.replacementField?.stringValue = settings.lastReplacement
        }
    }

    // MARK: - Status

    func setStatus(_ text: String, kind: StatusKind) {
        statusLabel.stringValue = text
        switch kind {
        case .info:    statusLabel.textColor = .secondaryLabelColor
        case .warning: statusLabel.textColor = .systemOrange
        case .error:   statusLabel.textColor = .systemRed
        }
    }

    private func report(_ status: XEditorFindStatus, text: String) {
        switch status {
        case .ok:
            setStatus("", kind: .info)
        case .notFound:
            NSSound.beep()
            setStatus(LF("Not found: %@", text), kind: .warning)
        case .invalidRegex:
            NSSound.beep()
            setStatus(L("Invalid regular expression."), kind: .error)
        case .badRange:
            NSSound.beep()
            setStatus(L("Invalid search range."), kind: .error)
        }
    }

    // MARK: - Query

    func makeQuery(text: String, replacement: String) -> SearchQuery {
        session.makeQuery(text: text, replacement: replacement)
    }

    private func typedQuery(from pane: FindPaneBase) -> SearchQuery? {
        let text = pane.searchField.stringValue
        guard !text.isEmpty else {
            NSSound.beep()
            setStatus(L("Enter text to find."), kind: .warning)
            return nil
        }
        settings.recordQuery(text)
        if !pane.replacementText.isEmpty {
            settings.recordReplacement(pane.replacementText)
        }
        reloadHistories()
        return session.makeQuery(text: text, replacement: pane.replacementText)
    }

    func optionsDidChange() {
        // Options are persisted by SearchOptionsView; nothing else to do.
    }

    func reloadHistories() {
        for tab in [FindTab.find, .replace, .mark] {
            pane(for: tab)?.reloadHistory()
        }
    }

    func clearHistory() {
        settings.clearHistory()
        reloadHistories()
        setStatus(L("Search history cleared."), kind: .info)
    }

    // MARK: - Find actions

    func performFind(forward: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.find(query: query, forward: forward) else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }

        switch result.status {
        case .ok:
            if result.wrapped {
                setStatus(L(forward ? "Found — wrapped to the top." : "Found — wrapped to the bottom."),
                          kind: .warning)
            } else if let match = result.match {
                setStatus(LF("Found on line %d.", match.line), kind: .info)
            }
            host?.findHostRefresh()
        case .notFound, .invalidRegex, .badRange:
            report(result.status, text: query.text)
        }
    }

    func performCount() {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.count(query: query) else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        switch result.status {
        case .ok:
            setStatus(result.count == 1 ? L("1 match found.") : LF("%d matches found.", result.count), kind: .info)
        case .notFound, .invalidRegex, .badRange:
            report(result.status, text: query.text)
        }
    }

    // MARK: - Find All

    func performFindAll(openDocuments: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }

        if openDocuments {
            findAllInOpenDocuments(query: query)
        } else {
            guard let doc = store.activeDocument else {
                setStatus(L("No document is open."), kind: .warning)
                return
            }
            let count = session.count(query: query)?.count ?? 0
            guard count > 0 else {
                report(.notFound, text: query.text)
                return
            }
            guard confirmLargeResult(count: count) else { return }

            let all = session.findAll(query: query, document: doc, maxCount: Self.currentDocumentLimit)
            guard all.status == .ok else {
                report(all.status, text: query.text)
                return
            }
            let matches = session.resultMatches(for: doc,
                                                matches: all.matches,
                                                location: .document(doc.id))
            let group = SearchResultGroup(location: .document(doc.id),
                                          displayName: doc.displayName,
                                          matches: matches)
            let model = SearchResultsModel(querySummary: LF("Search “%@”", query.text),
                                           groups: [group],
                                           truncated: all.truncated)
            showResults(model, query: query)
            setStatus(matches.count == 1 ? L("1 match found.") : LF("%d matches found.", matches.count), kind: .info)
        }
    }

    private func findAllInOpenDocuments(query: SearchQuery) {
        var groups: [SearchResultGroup] = []
        var total = 0
        for doc in store.documents {
            let all = session.findAll(query: query, document: doc, maxCount: Self.openDocumentsLimit)
            if all.status == .invalidRegex {
                report(.invalidRegex, text: query.text)
                return
            }
            guard !all.matches.isEmpty else { continue }
            let matches = session.resultMatches(for: doc,
                                                matches: all.matches,
                                                location: .document(doc.id))
            groups.append(SearchResultGroup(location: .document(doc.id),
                                            displayName: doc.displayName,
                                            matches: matches))
            total += matches.count
        }
        guard total > 0 else {
            report(.notFound, text: query.text)
            return
        }
        guard confirmLargeResult(count: total) else { return }

        let model = SearchResultsModel(querySummary: LF("Search “%@” in open documents", query.text),
                                       groups: groups,
                                       truncated: total >= Self.openDocumentsLimit)
        showResults(model, query: query)
        let status: String
        if total == 1 {
            status = groups.count == 1
                ? L("1 match in 1 file.")
                : LF("1 match in %d files.", groups.count)
        } else {
            status = groups.count == 1
                ? LF("%d matches in 1 file.", total)
                : LF("%d matches in %d files.", total, groups.count)
        }
        setStatus(status,
                  kind: .info)
    }

    private func confirmLargeResult(count: Int) -> Bool {
        guard count > Self.confirmThreshold else { return true }
        let alert = NSAlert()
        alert.messageText = LF("%d matches found.", count)
        alert.informativeText = L("Listing this many results can be slow. Show them anyway?")
        alert.addButton(withTitle: L("Show Results"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showResults(_ model: SearchResultsModel, query: SearchQuery) {
        resultsQuery = query
        guard let host else { return }
        let panel = host.findHostResultsPanel
        panel.onJump = { [weak self] match in
            self?.jump(to: match)
        }
        host.findHostSetResultsVisible(true)
        panel.show(model: model)
    }

    // MARK: - Copy matched text

    func copyMatchedText() {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let doc = store.activeDocument else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        let all = session.findAll(query: query, document: doc, maxCount: 50_000)
        guard all.status == .ok else {
            report(all.status, text: query.text)
            return
        }
        guard !all.matches.isEmpty else {
            report(.notFound, text: query.text)
            return
        }

        var pieces: [String] = []
        var currentLine = -1
        var lineBytes: [UInt8] = []
        for match in all.matches {
            let line = Int(match.line)
            if line != currentLine {
                currentLine = line
                lineBytes = Array(doc.editor.lineText(line).utf8)
            }
            let lineStart = Int(doc.editor.lineStartPosition(line))
            let start = Int(match.start) - lineStart
            let end = Int(match.end) - lineStart
            guard start >= 0, end >= start, end <= lineBytes.count else { continue }
            pieces.append(String(decoding: lineBytes[start..<end], as: UTF8.self))
        }
        guard !pieces.isEmpty else {
            report(.notFound, text: query.text)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pieces.joined(separator: "\n"), forType: .string)
        setStatus(pieces.count == 1 ? L("Copied 1 match.") : LF("Copied %d matches.", pieces.count), kind: .info)
    }

    func clearResults() {
        host?.findHostResultsPanel.clear()
        host?.findHostSetResultsVisible(false)
        resultsQuery = nil
        setStatus(L("Results cleared."), kind: .info)
    }

    // MARK: - Result jump

    private func jump(to match: SearchResultMatch) {
        switch match.location {
        case .document(let id):
            guard let doc = store.documents.first(where: { $0.id == id }) else {
                NSSound.beep()
                setStatus(L("That document is no longer open."), kind: .warning)
                return
            }
            host?.findHostReveal(documentID: id)
            if doc.contentRevision == match.revision {
                doc.editor.selectRange(start: match.byteStart, end: match.byteEnd)
            } else if let relocated = relocate(match, in: doc) {
                doc.editor.selectRange(start: Int(relocated.start), end: Int(relocated.end))
            } else {
                doc.editor.goToLine(match.line)
                NSSound.beep()
                setStatus(LF("Text changed — jumped to line %d.", match.line), kind: .warning)
            }
            host?.findHostFocusEditor()

        case .file(let url):
            host?.findHostOpenFile(url)
            guard let doc = store.documents.first(where: {
                $0.url?.standardizedFileURL == url.standardizedFileURL
            }) else {
                NSSound.beep()
                setStatus(LF("Could not open %@.", url.lastPathComponent), kind: .warning)
                return
            }
            let range = NSRange(location: match.byteStart, length: max(0, match.byteEnd - match.byteStart))
            doc.editor.selectLine(match.line, rangeInLine: range)
            host?.findHostFocusEditor()
        }
    }

    /// Re-runs the query to find the match again after the buffer changed.
    private func relocate(_ match: SearchResultMatch, in doc: EditorDocument) -> XEditorFindMatch? {
        guard let query = resultsQuery else { return nil }
        let all = session.findAll(query: query, document: doc, maxCount: 0)
        guard all.status == .ok else { return nil }
        return all.matches.first { Int($0.line) == match.line }
            ?? all.matches.first { Int($0.start) >= match.byteStart }
    }

    // MARK: - Replace

    func performReplace() {
        let pane = queryPane
        guard let query = typedQuery(from: pane) else { return }

        var result = session.replaceCurrent(query: query)
        if result?.status == .notFound {
            if let found = session.find(query: query, forward: !query.backward), found.status == .ok {
                result = session.replaceCurrent(query: query)
            }
        }

        guard let result else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        switch result.status {
        case .ok:
            setStatus(L("Replaced 1 occurrence."), kind: .info)
            host?.findHostRefresh()
            // Move on to the next match, like notepad--'s Replace button.
            _ = session.find(query: query, forward: !query.backward)
        case .notFound, .invalidRegex, .badRange:
            report(result.status, text: query.text)
        }
    }

    func performReplaceAll(openDocuments: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }

        if openDocuments {
            replaceAllInOpenDocuments(query: query)
            return
        }

        guard let doc = store.activeDocument else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        let count = session.count(query: query)?.count ?? 0
        guard count > 0 else {
            report(.notFound, text: query.text)
            return
        }
        guard confirmReplaceAll(count: count, fileCount: 1) else { return }

        let result = session.replaceAll(query: query, document: doc)
        guard result.status == .ok else {
            report(result.status, text: query.text)
            return
        }
        setStatus(result.count == 1 ? L("Replaced 1 occurrence.") : LF("Replaced %d occurrences.", result.count), kind: .info)
        host?.findHostRefresh()
    }

    func performReplaceAllInSelection() {
        let pane = queryPane
        let text = pane.searchField.stringValue
        guard !text.isEmpty else {
            NSSound.beep()
            setStatus(L("Enter text to find."), kind: .warning)
            return
        }
        guard let doc = store.activeDocument else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        let selStart = doc.editor.selectionStart
        let selEnd = doc.editor.selectionEnd
        guard selEnd > selStart else {
            NSSound.beep()
            setStatus(L("Select the text to replace first."), kind: .warning)
            return
        }

        settings.recordQuery(text)
        if !pane.replacementText.isEmpty {
            settings.recordReplacement(pane.replacementText)
        }
        reloadHistories()

        let query = session.makeQuery(text: text,
                                      replacement: pane.replacementText,
                                      inSelectionOverride: true)
        let count = doc.editor.countBytes(query.needleData,
                                          flags: query.flags,
                                          inStart: selStart,
                                          inEnd: selEnd)
        guard count.status == .ok else {
            report(count.status, text: query.text)
            return
        }
        guard count.count > 0 else {
            report(.notFound, text: query.text)
            return
        }
        guard confirmReplaceAll(count: count.count, fileCount: 1) else { return }

        let result = doc.editor.replaceAllBytes(query.needleData,
                                                replacement: query.replacementData,
                                                flags: query.flags,
                                                inStart: selStart,
                                                inEnd: selEnd)
        guard result.status == .ok else {
            report(result.status, text: query.text)
            return
        }
        setStatus(result.count == 1
                    ? L("Replaced 1 occurrence in the selection.")
                    : LF("Replaced %d occurrences in the selection.", result.count),
                  kind: .info)
        host?.findHostRefresh()
    }

    private func replaceAllInOpenDocuments(query: SearchQuery) {
        var counts: [(doc: EditorDocument, count: Int)] = []
        var total = 0
        for doc in store.documents {
            let result = session.findAll(query: query, document: doc, maxCount: 0)
            if result.status == .invalidRegex {
                report(.invalidRegex, text: query.text)
                return
            }
            guard !result.matches.isEmpty else { continue }
            counts.append((doc, result.matches.count))
            total += result.matches.count
        }
        guard total > 0 else {
            report(.notFound, text: query.text)
            return
        }
        guard confirmReplaceAll(count: total, fileCount: counts.count) else { return }

        var replaced = 0
        var filesChanged = 0
        for entry in counts {
            let result = session.replaceAll(query: query, document: entry.doc)
            guard result.status == .ok else { continue }
            replaced += Int(result.count)
            if result.count > 0 { filesChanged += 1 }
        }
        let key: String
        if filesChanged == 1 {
            key = replaced == 1 ? "Replaced 1 occurrence in 1 document."
                                : "Replaced %d occurrences in 1 document."
        } else {
            key = replaced == 1 ? "Replaced 1 occurrence in %d documents."
                                : "Replaced %d occurrences in %d documents."
        }
        setStatus(LF(key, replaced, filesChanged), kind: .info)
        host?.findHostRefreshAll()
    }

    private func confirmReplaceAll(count: Int, fileCount: Int) -> Bool {
        let alert = NSAlert()
        if fileCount > 1 {
            alert.messageText = LF("Replace %d occurrences in %d documents?", count, fileCount)
        } else if count == 1 {
            alert.messageText = L("Replace 1 occurrence?")
        } else {
            alert.messageText = LF("Replace %d occurrences?", count)
        }
        alert.informativeText = L("This replaces all matches in the selected scope. It can be undone per document.")
        alert.addButton(withTitle: L("Replace All"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Marks

    func performMarkAll(colorIndex: Int, addBookmarks: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.markAll(query: query, colorIndex: colorIndex, addBookmarks: addBookmarks) else {
            setStatus(L("No document is open."), kind: .warning)
            return
        }
        if result.status == .ok {
            setStatus(result.count == 1 ? L("Marked 1 occurrence.") : LF("Marked %d occurrences.", result.count), kind: .info)
            host?.findHostRefresh()
        } else {
            report(result.status, text: query.text)
        }
    }

    func clearMarks(all: Bool, colorIndex: Int) {
        session.clearMarks(all: all, colorIndex: colorIndex)
        setStatus(all ? L("Cleared all marks.") : LF("Cleared mark color %d.", colorIndex + 1), kind: .info)
        host?.findHostRefresh()
    }

    func clearAllMarks() {
        clearMarks(all: true, colorIndex: settings.markColorIndex)
    }

    // MARK: - Panel lifecycle

    func closePanel() {
        panel.orderOut(nil)
        host?.findHostFocusEditor()
    }

    func closeAllWindows() {
        panel.orderOut(nil)
        host?.findHostSetResultsVisible(false)
    }

    /// ⌘G / ⇧⌘G without opening the panel; falls back to opening it when there
    /// is no previous query.
    func findNext() { findFromMenu(forward: true) }
    func findPrevious() { findFromMenu(forward: false) }

    private func findFromMenu(forward: Bool) {
        if settings.hotkeyFollowsSelection {
            let selected = (host?.findHostSelectedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty && !selected.contains("\n") && selected.count <= 300 {
                let panes: [FindPaneBase] = [findPane, replacePane, markPane]
                for pane in panes {
                    pane.searchField.stringValue = selected
                }
                settings.recordQuery(selected)
                reloadHistories()
            }
        }

        let pane = queryPane
        if pane.searchField.stringValue.isEmpty {
            pane.searchField.stringValue = settings.lastQuery
        }
        if pane.searchField.stringValue.isEmpty {
            showFind()
            return
        }
        performFind(forward: forward)
    }

    func clearFindHistory() {
        clearHistory()
    }

    // MARK: - Localization

    /// Applies the current UI language to the window and its panes in place.
    func applyLocalization() {
        panel.title = L("Find and Replace")
        for tab in FindTab.allCases {
            tabControl.setLabel(tab.title, forSegment: tab.rawValue)
        }
        findPane.applyLocalization()
        replacePane.applyLocalization()
        markPane.applyLocalization()
        settingsPane.applyLocalization()
        rebuildFooter(for: currentTab)
        setStatus("", kind: .info)
    }

    func windowWillClose(_ notification: Notification) {
        host?.findHostFocusEditor()
    }

}

private extension NSView {
    /// Calls `activate()` on panes that have one; plain views are just shown.
    func activateIfPossible() {
        (self as? FindPaneBase)?.activate()
        (self as? SettingsPaneView)?.activate()
    }
}

extension FindTab {
    /// Panel content height that fits the tab without dead space.
    var preferredContentHeight: CGFloat {
        switch self {
        case .find:     return 158
        case .replace:  return 198
        case .mark:     return 188
        case .settings: return 208
        }
    }
}
