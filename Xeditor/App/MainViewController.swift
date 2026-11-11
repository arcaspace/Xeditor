import AppKit

final class MainViewController: NSViewController, NativeTabBarDelegate, FindBarDelegate, StatusBarDelegate {
    let store: DocumentStore

    private let tabBar = NativeTabBarView()
    private let findBar = FindBarView()
    private let editorContainer = NSView()
    private let statusBar = StatusBarView()

    private var isFindBarVisible: Bool = false

    init(store: DocumentStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 1. Tab Bar
        tabBar.delegate = self
        view.addSubview(tabBar)

        // 2. Find Bar (hidden initially)
        findBar.delegate = self
        findBar.isHidden = true
        view.addSubview(findBar)

        // 3. Editor Container
        editorContainer.wantsLayer = true
        view.addSubview(editorContainer)

        // 4. Status Bar
        statusBar.delegate = self
        view.addSubview(statusBar)

        // Initial tabs
        tabBar.reloadTabs(store: store)
        displayActiveDocument()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutViews()
    }

    private func layoutViews() {
        let b = view.bounds
        let tabBarH: CGFloat = 32
        let statusBarH: CGFloat = 22
        let findBarH: CGFloat = isFindBarVisible ? 32 : 0

        tabBar.frame = NSRect(x: 0, y: b.height - tabBarH, width: b.width, height: tabBarH)

        if isFindBarVisible {
            findBar.isHidden = false
            findBar.frame = NSRect(x: 0, y: b.height - tabBarH - findBarH, width: b.width, height: findBarH)
        } else {
            findBar.isHidden = true
            findBar.frame = NSRect(x: 0, y: b.height - tabBarH, width: b.width, height: 0)
        }

        statusBar.frame = NSRect(x: 0, y: 0, width: b.width, height: statusBarH)

        let editorY = statusBarH
        let editorH = max(0, b.height - tabBarH - findBarH - statusBarH)
        editorContainer.frame = NSRect(x: 0, y: editorY, width: b.width, height: editorH)

        if let active = store.activeDocument {
            active.editor.view.frame = editorContainer.bounds
        }
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

        // Update find match count if find bar is open
        if isFindBarVisible {
            let count = Int(active.editor.matchCount(active.editor.selectedText(), flags: findBar.searchFlags))
            findBar.updateMatchCount(count)
        }
    }

    func reloadAll() {
        tabBar.reloadTabs(store: store)
        displayActiveDocument()
    }

    func updateActiveDocumentContent() {
        guard let active = store.activeDocument else { return }
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
            alert.messageText = "Do you want to save the changes made to “\(document.displayName)”?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don’t Save")
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
        panel.title = "Save File"
        panel.nameFieldStringValue = document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard document.save(to: url) else { return false }
        updateActiveDocumentContent()
        return true
    }

    // MARK: - Find Bar

    func toggleFindBar() {
        isFindBarVisible.toggle()
        layoutViews()
        if isFindBarVisible {
            let sel = store.activeDocument?.editor.selectedText() ?? ""
            findBar.setInitialText(sel)
        } else {
            if let active = store.activeDocument {
                view.window?.makeFirstResponder(active.editor.view)
            }
        }
    }

    func findBarDidFindNext(text: String, flags: XEditorSearchFlags) {
        guard let editor = store.activeDocument?.editor else { return }
        let pos = editor.findNext(text, flags: flags)
        if pos >= 0 {
            updateActiveDocumentContent()
        }
        findBar.updateMatchCount(Int(editor.matchCount(text, flags: flags)))
    }

    func findBarDidFindPrevious(text: String, flags: XEditorSearchFlags) {
        guard let editor = store.activeDocument?.editor else { return }
        let pos = editor.findPrevious(text, flags: flags)
        if pos >= 0 {
            updateActiveDocumentContent()
        }
        findBar.updateMatchCount(Int(editor.matchCount(text, flags: flags)))
    }

    func findBarDidReplace(text: String, replacement: String, flags: XEditorSearchFlags) {
        guard let editor = store.activeDocument?.editor else { return }
        let isRegex = (flags.contains(.regex))
        if !editor.replaceCurrent(replacement, regex: isRegex) {
            _ = editor.findNext(text, flags: flags)
            _ = editor.replaceCurrent(replacement, regex: isRegex)
        }
        _ = editor.findNext(text, flags: flags)
        findBar.updateMatchCount(Int(editor.matchCount(text, flags: flags)))
        updateActiveDocumentContent()
    }

    func findBarDidReplaceAll(text: String, replacement: String, flags: XEditorSearchFlags) {
        guard let editor = store.activeDocument?.editor else { return }
        _ = editor.replaceAll(text, with: replacement, flags: flags)
        findBar.updateMatchCount(Int(editor.matchCount(text, flags: flags)))
        updateActiveDocumentContent()
    }

    func findBarDidChangeSearchText(text: String, flags: XEditorSearchFlags) {
        guard let editor = store.activeDocument?.editor else { return }
        findBar.updateMatchCount(Int(editor.matchCount(text, flags: flags)))
    }

    func findBarDidDismiss() {
        isFindBarVisible = false
        layoutViews()
        if let active = store.activeDocument {
            view.window?.makeFirstResponder(active.editor.view)
        }
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
}
