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
    case directory
    case mark
    case settings

    var title: String {
        switch self {
        case .find:      return "Find"
        case .replace:   return "Replace"
        case .directory: return "Dir Find"
        case .mark:      return "Mark"
        case .settings:  return "Settings"
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
    private let tabStrip = FindTabStrip()
    private let paneContainer = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var findPane: FindPaneView!
    private var replacePane: ReplacePaneView!
    private var dirPane: DirFindPaneView!
    private var markPane: MarkPaneView!
    private var settingsPane: SettingsPaneView!

    private var dirFinder: DirFinder?
    /// Query that produced the current result list, for stale-result relocation.
    private var resultsQuery: SearchQuery?

    private static let currentDocumentLimit = 50_000
    private static let openDocumentsLimit = 50_000
    private static let confirmThreshold = 2_000
    private static let dirHitLimit = 20_000

    init(store: DocumentStore, host: FindHost?) {
        self.store = store
        self.session = FindSession(store: store)
        self.host = host
        self.panel = FindPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                               styleMask: [.titled, .closable, .resizable, .utilityWindow],
                               backing: .buffered,
                               defer: false)
        super.init()

        panel.title = "Find"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        panel.setFrameAutosaveName("XeditorFindWindow")
        panel.contentMinSize = NSSize(width: 720, height: 500)

        findPane = FindPaneView(controller: self)
        replacePane = ReplacePaneView(controller: self)
        dirPane = DirFindPaneView(controller: self)
        markPane = MarkPaneView(controller: self)
        settingsPane = SettingsPaneView(controller: self)

        tabStrip.titles = FindTab.allCases.map { $0.title }
        tabStrip.onSelect = { [weak self] index in
            self?.selectTab(rawValue: index, activate: true)
        }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = panel.contentView ?? NSView()
        content.addSubview(tabStrip)
        content.addSubview(paneContainer)
        content.addSubview(statusLabel)
        for view in [tabStrip, paneContainer, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        for tab in FindTab.allCases {
            let view = self.view(for: tab)
            paneContainer.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: content.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 42),

            paneContainer.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            paneContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
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
        case .directory: return dirPane
        case .mark:      return markPane
        case .settings:  return nil
        }
    }

    private func view(for tab: FindTab) -> NSView {
        if tab == .settings { return settingsPane }
        return pane(for: tab) ?? findPane
    }

    private var currentTab: FindTab {
        FindTab(rawValue: tabStrip.selectedIndex) ?? .find
    }

    private var currentPane: FindPaneBase? { pane(for: currentTab) }

    /// Pane that supplies the query for actions that can also be triggered
    /// from the menu while the Settings tab is frontmost.
    private var queryPane: FindPaneBase { currentPane ?? findPane }

    // MARK: - Showing

    func showFind() { show(tab: .find) }
    func showReplace() { show(tab: .replace) }
    func showDirectoryFind() { show(tab: .directory) }
    func showMark() { show(tab: .mark) }
    func showSettings() { show(tab: .settings) }

    func show(tab: FindTab) {
        let wasVisible = panel.isVisible
        selectTab(rawValue: tab.rawValue, activate: false)
        if !wasVisible {
            prefillFromSelectionOrHistory()
            if !panel.setFrameUsingName("XeditorFindWindow") {
                panel.center()
            }
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        applyOpacity()
        view(for: tab).activateIfPossible()
    }

    private func selectTab(rawValue: Int, activate: Bool) {
        let tab = FindTab(rawValue: rawValue) ?? .find
        tabStrip.selectedIndex = tab.rawValue
        settings.lastTab = tab.rawValue

        for candidate in FindTab.allCases {
            view(for: candidate).isHidden = candidate != tab
        }
        setStatus("", kind: .info)
        if activate, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            view(for: tab).activateIfPossible()
        }
    }

    private func loadLastText() {
        let panes: [FindPaneBase] = [findPane, replacePane, dirPane, markPane]
        if !settings.lastQuery.isEmpty {
            for pane in panes {
                pane.searchField.stringValue = settings.lastQuery
            }
        }
        if !settings.lastReplacement.isEmpty {
            replacePane.replacementField?.stringValue = settings.lastReplacement
            dirPane.replacementField?.stringValue = settings.lastReplacement
        }
    }

    private func prefillFromSelectionOrHistory() {
        let selected = (host?.findHostSelectedText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = !selected.isEmpty && !selected.contains("\n") && selected.count <= 300
        let text = usable ? selected : settings.lastQuery
        let panes: [FindPaneBase] = [findPane, replacePane, dirPane, markPane]
        for pane in panes {
            pane.searchField.stringValue = text
        }
        if !settings.lastReplacement.isEmpty {
            replacePane.replacementField?.stringValue = settings.lastReplacement
            dirPane.replacementField?.stringValue = settings.lastReplacement
        }
    }

    // MARK: - Transparency

    func applyOpacity() {
        guard settings.opacityEnabled else {
            panel.alphaValue = 1
            return
        }
        if settings.opacityAlways {
            panel.alphaValue = settings.opacity
        } else {
            panel.alphaValue = panel.isKeyWindow ? 1 : settings.opacity
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyOpacity()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyOpacity()
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
            setStatus("Not found: \(text)", kind: .warning)
        case .invalidRegex:
            NSSound.beep()
            setStatus("Invalid regular expression.", kind: .error)
        case .badRange:
            NSSound.beep()
            setStatus("Invalid search range.", kind: .error)
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
            setStatus("Enter text to find.", kind: .warning)
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
        for tab in [FindTab.find, .replace, .directory, .mark] {
            pane(for: tab)?.reloadHistory()
        }
    }

    func clearHistory() {
        settings.clearHistory()
        reloadHistories()
        setStatus("Search history cleared.", kind: .info)
    }

    // MARK: - Find actions

    func performFind(forward: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.find(query: query, forward: forward) else {
            setStatus("No document is open.", kind: .warning)
            return
        }

        switch result.status {
        case .ok:
            if result.wrapped {
                setStatus(forward ? "Found — wrapped to the top." : "Found — wrapped to the bottom.",
                          kind: .warning)
            } else if let match = result.match {
                setStatus("Found on line \(match.line).", kind: .info)
            }
            host?.findHostRefresh()
        case .notFound, .invalidRegex, .badRange:
            report(result.status, text: query.text)
        }
    }

    func performCount() {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.count(query: query) else {
            setStatus("No document is open.", kind: .warning)
            return
        }
        switch result.status {
        case .ok:
            setStatus("\(result.count) match\(result.count == 1 ? "" : "es") found.", kind: .info)
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
                setStatus("No document is open.", kind: .warning)
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
            let model = SearchResultsModel(querySummary: "Search “\(query.text)”",
                                           groups: [group],
                                           truncated: all.truncated)
            showResults(model, query: query)
            setStatus("\(matches.count) match\(matches.count == 1 ? "" : "es") found.", kind: .info)
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

        let model = SearchResultsModel(querySummary: "Search “\(query.text)” in open documents",
                                       groups: groups,
                                       truncated: total >= Self.openDocumentsLimit)
        showResults(model, query: query)
        setStatus("\(total) match\(total == 1 ? "" : "es") in \(groups.count) file\(groups.count == 1 ? "" : "s").",
                  kind: .info)
    }

    private func confirmLargeResult(count: Int) -> Bool {
        guard count > Self.confirmThreshold else { return true }
        let alert = NSAlert()
        alert.messageText = "\(count) matches found."
        alert.informativeText = "Listing this many results can be slow. Show them anyway?"
        alert.addButton(withTitle: "Show Results")
        alert.addButton(withTitle: "Cancel")
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
            setStatus("No document is open.", kind: .warning)
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
        setStatus("Copied \(pieces.count) match\(pieces.count == 1 ? "" : "es").", kind: .info)
    }

    func clearResults() {
        host?.findHostResultsPanel.clear()
        host?.findHostSetResultsVisible(false)
        resultsQuery = nil
        setStatus("Results cleared.", kind: .info)
    }

    // MARK: - Result jump

    private func jump(to match: SearchResultMatch) {
        switch match.location {
        case .document(let id):
            guard let doc = store.documents.first(where: { $0.id == id }) else {
                NSSound.beep()
                setStatus("That document is no longer open.", kind: .warning)
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
                setStatus("Text changed — jumped to line \(match.line).", kind: .warning)
            }
            host?.findHostFocusEditor()

        case .file(let url):
            host?.findHostOpenFile(url)
            guard let doc = store.documents.first(where: {
                $0.url?.standardizedFileURL == url.standardizedFileURL
            }) else {
                NSSound.beep()
                setStatus("Could not open \(url.lastPathComponent).", kind: .warning)
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
            setStatus("No document is open.", kind: .warning)
            return
        }
        switch result.status {
        case .ok:
            setStatus("Replaced 1 occurrence.", kind: .info)
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
            setStatus("No document is open.", kind: .warning)
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
        setStatus("Replaced \(result.count) occurrence\(result.count == 1 ? "" : "s").", kind: .info)
        host?.findHostRefresh()
    }

    func performReplaceAllInSelection() {
        let pane = queryPane
        let text = pane.searchField.stringValue
        guard !text.isEmpty else {
            NSSound.beep()
            setStatus("Enter text to find.", kind: .warning)
            return
        }
        guard let doc = store.activeDocument else {
            setStatus("No document is open.", kind: .warning)
            return
        }
        let selStart = doc.editor.selectionStart
        let selEnd = doc.editor.selectionEnd
        guard selEnd > selStart else {
            NSSound.beep()
            setStatus("Select the text to replace first.", kind: .warning)
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
        setStatus("Replaced \(result.count) occurrence\(result.count == 1 ? "" : "s") in the selection.",
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
        setStatus("Replaced \(replaced) occurrence\(replaced == 1 ? "" : "s") in \(filesChanged) document\(filesChanged == 1 ? "" : "s").",
                  kind: .info)
        host?.findHostRefreshAll()
    }

    private func confirmReplaceAll(count: Int, fileCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace \(count) occurrence\(count == 1 ? "" : "s")"
            + (fileCount > 1 ? " in \(fileCount) documents" : "") + "?"
        alert.informativeText = "This replaces all matches in the selected scope. It can be undone per document."
        alert.addButton(withTitle: "Replace All")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Marks

    func performMarkAll(colorIndex: Int, addBookmarks: Bool) {
        guard let query = typedQuery(from: queryPane) else { return }
        guard let result = session.markAll(query: query, colorIndex: colorIndex, addBookmarks: addBookmarks) else {
            setStatus("No document is open.", kind: .warning)
            return
        }
        if result.status == .ok {
            setStatus("Marked \(result.count) occurrence\(result.count == 1 ? "" : "s").", kind: .info)
            host?.findHostRefresh()
        } else {
            report(result.status, text: query.text)
        }
    }

    func clearMarks(all: Bool, colorIndex: Int) {
        session.clearMarks(all: all, colorIndex: colorIndex)
        setStatus(all ? "Cleared all marks." : "Cleared mark color \(colorIndex + 1).", kind: .info)
        host?.findHostRefresh()
    }

    func clearAllMarks() {
        clearMarks(all: true, colorIndex: settings.markColorIndex)
    }

    // MARK: - Directory search

    func performDirSearch(replace: Bool) {
        guard !dirPane.isRunning else { return }
        guard let options = dirPane.makeOptions() else {
            NSSound.beep()
            setStatus("Choose a directory and enter search text first.", kind: .warning)
            return
        }
        settings.recordQuery(options.query.text)
        reloadHistories()

        if replace {
            countThenReplaceDirectory(options: options)
        } else {
            runDirectorySearch(options: options)
        }
    }

    private func runDirectorySearch(options: DirSearchOptions) {
        let finder = DirFinder()
        dirFinder = finder
        dirPane.setRunning(true)
        setStatus("Scanning…", kind: .info)

        let model = SearchResultsModel(querySummary: "Search “\(options.query.text)” in \(options.directory.path)",
                                       isDirectorySearch: true)
        resultsQuery = options.query
        guard let host else { return }
        let results = host.findHostResultsPanel
        results.onJump = { [weak self] match in self?.jump(to: match) }
        host.findHostSetResultsVisible(true)
        results.show(model: model)

        finder.search(options: options,
                      hitLimit: Self.dirHitLimit,
                      onProgress: { [weak self] scanned, total, hits in
                          self?.dirPane.updateProgress(scanned: scanned, total: total, hits: hits)
                      },
                      onBatch: { [weak self] batch in
                          self?.host?.findHostResultsPanel.appendDirectoryHits(batch)
                      },
                      completion: { [weak self] truncated, cancelled, error in
                          guard let self else { return }
                          self.dirFinder = nil
                          self.dirPane.setRunning(false)
                          if let error {
                              NSSound.beep()
                              self.setStatus(error, kind: .error)
                              return
                          }
                          if truncated {
                              self.setStatus("Search stopped at \(Self.dirHitLimit) matches.",
                                             kind: .warning)
                          } else if cancelled {
                              self.setStatus("Search cancelled.", kind: .warning)
                          } else {
                              let hits = self.host?.findHostResultsPanel.hitCount ?? 0
                              self.setStatus("Found \(hits) match\(hits == 1 ? "" : "es").", kind: .info)
                          }
                          self.host?.findHostResultsPanel.finishDirectorySearch()
                      })
    }

    private func countThenReplaceDirectory(options: DirSearchOptions) {
        let counter = DirFinder()
        dirFinder = counter
        dirPane.setRunning(true)
        setStatus("Counting matches…", kind: .info)

        var counted: [DirSearchHit] = []
        counter.search(options: options,
                       hitLimit: 10_001,
                       onProgress: { [weak self] scanned, total, hits in
                           self?.dirPane.updateProgress(scanned: scanned, total: total, hits: hits)
                       },
                       onBatch: { batch in
                           counted.append(contentsOf: batch)
                       },
                       completion: { [weak self] truncated, cancelled, error in
                           guard let self else { return }
                           self.dirFinder = nil
                           self.dirPane.setRunning(false)
                           if let error {
                               NSSound.beep()
                               self.setStatus(error, kind: .error)
                               return
                           }
                           if cancelled { return }
                           guard !counted.isEmpty else {
                               NSSound.beep()
                               self.setStatus("No matches to replace.", kind: .warning)
                               return
                           }

                           let fileURLs = Set(counted.map { $0.url })
                           let total = counted.count
                           var message = "Replace \(total)\(truncated ? "+" : "") occurrence\(total == 1 ? "" : "s") in \(fileURLs.count) file\(fileURLs.count == 1 ? "" : "s")?"
                           message += "\n\nFiles are written back in their original encoding."
                           let alert = NSAlert()
                           alert.messageText = message

                           let dirtyOpen = self.store.documents.filter { doc in
                               guard let url = doc.url else { return false }
                               return doc.isDirty && fileURLs.contains(url.standardizedFileURL)
                           }
                           if !dirtyOpen.isEmpty {
                               let names = dirtyOpen.prefix(5).map { $0.displayName }.joined(separator: ", ")
                               alert.informativeText = "These open files have unsaved changes: \(names). Save them before replacing?"
                               alert.addButton(withTitle: "Save and Replace")
                               alert.addButton(withTitle: "Cancel")
                               guard alert.runModal() == .alertFirstButtonReturn else { return }
                               for doc in dirtyOpen {
                                   guard doc.save(to: doc.url) else {
                                       NSSound.beep()
                                       self.setStatus("Could not save \(doc.displayName); replace cancelled.", kind: .error)
                                       return
                                   }
                               }
                           } else {
                               alert.addButton(withTitle: "Replace All")
                               alert.addButton(withTitle: "Cancel")
                               guard alert.runModal() == .alertFirstButtonReturn else { return }
                           }

                           self.runDirectoryReplace(options: options)
                       })
    }

    private func runDirectoryReplace(options: DirSearchOptions) {
        let replacer = DirFinder()
        dirFinder = replacer
        dirPane.setRunning(true)
        setStatus("Replacing…", kind: .info)

        replacer.replaceAll(options: options,
                            onProgress: { [weak self] scanned, total in
                                self?.dirPane.updateProgress(scanned: scanned, total: total, hits: 0)
                            },
                            completion: { [weak self] summary, error in
                                guard let self else { return }
                                self.dirFinder = nil
                                self.dirPane.setRunning(false)

                                if let error {
                                    NSSound.beep()
                                    self.setStatus(error, kind: .error)
                                    return
                                }

                                // Re-sync any open documents that were rewritten.
                                for doc in self.store.documents {
                                    guard let url = doc.url,
                                          url.standardizedFileURL.path.hasPrefix(options.directory.standardizedFileURL.path),
                                          !doc.isDirty else { continue }
                                    doc.reload(withEncoding: doc.encoding)
                                }
                                self.host?.findHostRefreshAll()

                                var text = "Replaced \(summary.replaced) occurrence\(summary.replaced == 1 ? "" : "s") in \(summary.filesChanged) file\(summary.filesChanged == 1 ? "" : "s")."
                                if !summary.skipped.isEmpty {
                                    text += " Skipped \(summary.skipped.count) file\(summary.skipped.count == 1 ? "" : "s")."
                                }
                                self.setStatus(text, kind: summary.skipped.isEmpty ? .info : .warning)
                            })
    }

    func cancelDirSearch() {
        dirFinder?.cancel()
        setStatus("Cancelling…", kind: .warning)
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
                let panes: [FindPaneBase] = [findPane, replacePane, dirPane, markPane]
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
