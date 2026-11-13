import AppKit

final class MainViewController: NSViewController, NativeTabBarDelegate, FindHost, StatusBarDelegate {
    let store: DocumentStore

    private let tabBar = NativeTabBarView()
    private let editorContainer = NSView()
    private let resultsPanel = FindResultsPanel(frame: .zero)
    private let resultsDivider = SplitDividerView()
    private let statusBar = StatusBarView()
    private var resultsHeight: CGFloat = 240
    private var resultsVisible = false

    init(store: DocumentStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = AppearanceAwareView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 1. Tab Bar
        tabBar.delegate = self
        view.addSubview(tabBar)

        // 2. Editor Container
        editorContainer.wantsLayer = true
        view.addSubview(editorContainer)

        // 3. Search results, docked below the editor (hidden until a Find All)
        resultsPanel.isHidden = true
        resultsPanel.onClose = { [weak self] in self?.setResultsVisible(false) }
        view.addSubview(resultsPanel)

        resultsDivider.isHidden = true
        resultsDivider.onDrag = { [weak self] delta in
            self?.adjustResultsHeight(by: delta)
        }
        view.addSubview(resultsDivider)

        // 3. Status Bar
        statusBar.delegate = self
        view.addSubview(statusBar)

        // Initial tabs
        tabBar.reloadTabs(store: store)
        displayActiveDocument()

        // Files dropped anywhere in the window open as tabs. Drops on the
        // editor itself arrive through the bridge (see DocumentStore).
        store.onFileDrop = { [weak self] urls in
            self?.openDroppedFiles(urls)
        }
        (view as? AppearanceAwareView)?.onFileDrop = { [weak self] urls in
            self?.openDroppedFiles(urls)
        }
    }

    private func openDroppedFiles(_ urls: [URL]) {
        let files = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        guard !files.isEmpty else { return }
        for url in files {
            _ = store.open(url: url)
        }
        reloadAll()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutViews()
    }

    private func layoutViews() {
        let b = view.bounds
        let tabBarH: CGFloat = 32
        let statusBarH: CGFloat = 22
        let dividerH: CGFloat = 6

        tabBar.frame = NSRect(x: 0, y: b.height - tabBarH, width: b.width, height: tabBarH)
        statusBar.frame = NSRect(x: 0, y: 0, width: b.width, height: statusBarH)

        let editorTop = b.height - tabBarH
        var editorBottom = statusBarH

        if resultsVisible {
            let available = max(0, editorTop - statusBarH)
            let maxPanelH = max(80, available - 140)
            let panelH = min(max(resultsHeight, 80), maxPanelH)
            resultsHeight = panelH
            resultsPanel.frame = NSRect(x: 0, y: statusBarH, width: b.width, height: panelH)
            resultsDivider.frame = NSRect(x: 0, y: statusBarH + panelH, width: b.width, height: dividerH)
            editorBottom = statusBarH + panelH + dividerH
        }

        editorContainer.frame = NSRect(x: 0, y: editorBottom, width: b.width,
                                       height: max(0, editorTop - editorBottom))

        if let active = store.activeDocument {
            active.editor.view.frame = editorContainer.bounds
        }
    }

    /// Splits the editor area and shows the search results beneath it.
    private func setResultsVisible(_ visible: Bool) {
        guard resultsVisible != visible else { return }
        resultsVisible = visible
        resultsPanel.isHidden = !visible
        resultsDivider.isHidden = !visible
        layoutViews()
    }

    private func adjustResultsHeight(by delta: CGFloat) {
        guard resultsVisible else { return }
        let b = view.bounds
        let available = max(0, b.height - 32 - 22)
        let maxPanelH = max(80, available - 140)
        // The divider sits on top of the panel, so moving it up grows the panel.
        resultsHeight = min(max(resultsHeight + delta, 80), maxPanelH)
        layoutViews()
    }

    func displayActiveDocument() {
        editorContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let active = store.activeDocument else {
            statusBar.update(document: nil)
            return
        }

        let editorView = active.editor.view
        editorView.frame = editorContainer.bounds
        editorView.autoresizingMask = [.width, .height]
        editorContainer.addSubview(editorView)

        view.window?.makeFirstResponder(editorView)
        tabBar.updateActiveTab(activeID: active.id)
        statusBar.update(document: active)
        view.window?.title = active.displayName
    }

    func reloadAll() {
        tabBar.reloadTabs(store: store)
        displayActiveDocument()
    }

    func updateActiveDocumentContent() {
        guard let active = store.activeDocument else { return }
        active.refreshMetrics()
        tabBar.updateDocument(id: active.id)
        statusBar.update(document: active)
        view.window?.title = active.displayName
    }

    // MARK: - NativeTabBarDelegate

    func tabBarDidSelect(document: EditorDocument) {
        store.select(document)
        displayActiveDocument()
    }

    func tabBarDidClose(document: EditorDocument) {
        closeDocumentWithConfirmation(document)
    }

    func tabBarDidCloseOthers(document: EditorDocument) {
        for other in store.documents where other.id != document.id {
            closeDocumentWithConfirmation(other)
        }
        store.select(document)
        reloadAll()
    }

    func tabBarDidClickNewTab() {
        _ = store.newDocument()
        reloadAll()
    }

    func closeDocumentWithConfirmation(_ document: EditorDocument) {
        if document.isDirty {
            let alert = NSAlert()
            alert.messageText = LF("Do you want to save the changes made to “%@”?", document.displayName)
            alert.informativeText = L("Your changes will be lost if you don’t save them.")
            alert.addButton(withTitle: L("Save"))
            alert.addButton(withTitle: L("Cancel"))
            alert.addButton(withTitle: L("Don’t Save"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let ok = document.url == nil ? saveDocumentAs(document) : document.save()
                guard ok else { return }
            case .alertSecondButtonReturn:
                return
            default:
                break
            }
        }
        store.close(document)
        reloadAll()
    }

    @discardableResult
    func saveDocumentAs(_ document: EditorDocument) -> Bool {
        let panel = NSSavePanel()
        panel.title = L("Save File")
        panel.nameFieldStringValue = document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard document.save(to: url) else { return false }
        updateActiveDocumentContent()
        return true
    }

    // MARK: - FindHost

    var findHostSelectedText: String {
        store.activeDocument?.editor.selectedText() ?? ""
    }

    func findHostReveal(documentID: EditorDocument.ID) {
        guard let doc = store.documents.first(where: { $0.id == documentID }) else { return }
        if store.activeID != documentID {
            store.select(doc)
            displayActiveDocument()
        }
    }

    func findHostOpenFile(_ url: URL) {
        _ = store.open(url: url)
        reloadAll()
    }

    func findHostRefresh() {
        updateActiveDocumentContent()
    }

    func findHostRefreshAll() {
        reloadAll()
    }

    func findHostFocusEditor() {
        guard let active = store.activeDocument else { return }
        view.window?.makeFirstResponder(active.editor.view)
    }

    var findHostResultsPanel: FindResultsPanel { resultsPanel }

    func findHostSetResultsVisible(_ visible: Bool) {
        setResultsVisible(visible)
    }

    // MARK: - StatusBarDelegate

    func statusBarDidChangeLanguage(_ preset: LanguagePreset) {
        store.activeDocument?.setLanguage(preset)
        updateActiveDocumentContent()
    }

    func statusBarDidChangeEncoding(_ encoding: DocumentEncoding) {
        store.activeDocument?.reload(withEncoding: encoding)
        updateActiveDocumentContent()
    }

    // MARK: - Localization

    /// Refreshes the parts of the main window that are built once at launch.
    func applyLocalization() {
        tabBar.applyLocalization()
        resultsPanel.applyLocalization()
    }
}

// MARK: - Appearance-aware container

/// Root container whose layer background is resolved from the current
/// appearance. `NSColor.windowBackgroundColor.cgColor` snapshots the colour
/// once, so it must be refreshed whenever the app theme changes.
final class AppearanceAwareView: NSView {
    /// Called with the regular files dropped on the window.
    var onFileDrop: (([URL]) -> Void)?

    private var isDropHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        updateDropHighlight()
    }

    // MARK: - File drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        setDropHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlighted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlighted(false)
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: options) as? [URL] ?? []
        return items.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private func setDropHighlighted(_ highlighted: Bool) {
        guard isDropHighlighted != highlighted else { return }
        isDropHighlighted = highlighted
        updateDropHighlight()
    }

    private func updateDropHighlight() {
        wantsLayer = true
        layer?.borderWidth = isDropHighlighted ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }
}

/// Thin grab bar between the editor and the docked results panel.
final class SplitDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    private var lastY: CGFloat = 0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        // Track in window coordinates: the divider moves under the cursor while
        // dragging, so view-local coordinates would cancel out the movement and
        // the panel would barely follow the mouse.
        lastY = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        let y = event.locationInWindow.y
        let delta = y - lastY
        lastY = y
        onDrag?(delta)
    }
}
