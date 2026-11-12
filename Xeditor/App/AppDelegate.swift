import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, PreferencesDelegate, GoToLineDelegate {
    let store = DocumentStore()
    private var windowController: MainWindowController?
    private var preferencesController: PreferencesWindowController?
    private var goToLineController: GoToLineWindowController?
    private var findController: FindWindowController?
    private var appearanceObservation: NSKeyValueObservation?

    private static let sessionFilesKey = "session.files"
    private static let sessionActiveKey = "session.activeIndex"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Build Menu Bar
        buildMainMenu()

        // Create main window controller
        let wc = MainWindowController(store: store)
        windowController = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        wc.onWindowClose = { [weak self] in
            self?.findController?.closeAllWindows()
        }

        // Session restore or open CLI files
        let paths = CommandLine.arguments.dropFirst().filter {
            !$0.hasPrefix("--") && FileManager.default.fileExists(atPath: $0)
        }
        if !paths.isEmpty {
            for p in paths {
                store.open(url: URL(fileURLWithPath: p))
            }
        } else {
            restoreSession()
        }

        wc.mainVC.reloadAll()

        applyGlobalSettings()
        observeSystemAppearance()
    }

    /// Re-resolve the editor theme when macOS switches between light and dark
    /// while the "Follow System" theme is selected.
    private func observeSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, EditorSettings.shared.theme == .system else { return }
                self.applyGlobalSettings()
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for name in filenames {
            store.open(url: URL(fileURLWithPath: name))
        }
        windowController?.mainVC.reloadAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        findController?.closeAllWindows()
        saveSession()
    }

    // MARK: - Session

    private func saveSession() {
        let defaults = UserDefaults.standard
        defaults.set(store.documents.compactMap { $0.url?.path }, forKey: Self.sessionFilesKey)
        if let active = store.activeDocument,
           let index = store.documents.firstIndex(where: { $0.id == active.id }) {
            defaults.set(index, forKey: Self.sessionActiveKey)
        }
    }

    private func restoreSession() {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Self.sessionFilesKey) ?? []
        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        for u in urls { store.open(url: u) }
        let index = defaults.integer(forKey: Self.sessionActiveKey)
        if store.documents.indices.contains(index) {
            store.activeID = store.documents[index].id
        }
    }

    // MARK: - PreferencesDelegate

    func preferencesDidChange() {
        applyGlobalSettings()
    }

    private func applyGlobalSettings() {
        let settings = EditorSettings.shared

        // Theme the whole app, not just the editor: the window chrome, tab bar
        // and Preferences window should match the chosen scheme.
        switch settings.theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        for doc in store.documents {
            settings.apply(to: doc.editor)
        }
    }

    // MARK: - GoToLineDelegate

    func goToLineDidSelect(line: Int) {
        store.activeDocument?.editor.goToLine(line)
        windowController?.mainVC.updateActiveDocumentContent()
    }

    // MARK: - Menu Actions

    @objc func newDocument(_ sender: Any?) {
        _ = store.newDocument()
        windowController?.mainVC.reloadAll()
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Open File"
        guard panel.runModal() == .OK else { return }
        for u in panel.urls {
            store.open(url: u)
        }
        windowController?.mainVC.reloadAll()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let doc = store.activeDocument else { return }
        if doc.url == nil {
            saveDocumentAs(sender)
        } else {
            _ = doc.save()
            windowController?.mainVC.updateActiveDocumentContent()
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let doc = store.activeDocument else { return }
        windowController?.mainVC.saveDocumentAs(doc)
    }

    @objc func closeTab(_ sender: Any?) {
        guard let doc = store.activeDocument else { return }
        windowController?.mainVC.closeDocumentWithConfirmation(doc)
    }

    @objc func closeOtherTabs(_ sender: Any?) {
        guard let doc = store.activeDocument else { return }
        windowController?.mainVC.tabBarDidCloseOthers(document: doc)
    }

    @objc func showNextTab(_ sender: Any?) {
        store.selectNext()
        windowController?.mainVC.displayActiveDocument()
    }

    @objc func showPreviousTab(_ sender: Any?) {
        store.selectPrevious()
        windowController?.mainVC.displayActiveDocument()
    }

    /// Lazily creates the modeless Find window. It survives being closed so
    /// ⌘G keeps working after the panel is dismissed.
    private func findWindow() -> FindWindowController {
        if let findController { return findController }
        let controller = FindWindowController(store: store, host: windowController?.mainVC)
        findController = controller
        return controller
    }

    @objc func showFind(_ sender: Any?) {
        findWindow().showFind()
    }

    @objc func showReplace(_ sender: Any?) {
        findWindow().showReplace()
    }

    @objc func showDirectoryFind(_ sender: Any?) {
        findWindow().showDirectoryFind()
    }

    @objc func showMark(_ sender: Any?) {
        findWindow().showMark()
    }

    @objc func findNext(_ sender: Any?) {
        findWindow().findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        findWindow().findPrevious()
    }

    @objc func findAllInCurrentDocument(_ sender: Any?) {
        let find = findWindow()
        find.showFind()
        find.performFindAll(openDocuments: false)
    }

    @objc func findAllInOpenDocuments(_ sender: Any?) {
        let find = findWindow()
        find.showFind()
        find.performFindAll(openDocuments: true)
    }

    @objc func replaceAllInOpenDocuments(_ sender: Any?) {
        let find = findWindow()
        find.showReplace()
        find.performReplaceAll(openDocuments: true)
    }

    @objc func clearFindMarks(_ sender: Any?) {
        findWindow().clearAllMarks()
    }

    @objc func clearFindHistory(_ sender: Any?) {
        findWindow().clearFindHistory()
    }

    @objc func showGoToLine(_ sender: Any?) {
        guard let active = store.activeDocument else { return }
        let c = GoToLineWindowController(maxLine: active.lineCount, currentLine: active.cursorLine, delegate: self)
        goToLineController = c
        c.showWindow(nil)
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(delegate: self)
        }
        preferencesController?.showWindow(nil)
    }

    // MARK: - Edit & Formatting Actions

    @objc func duplicateLine(_ sender: Any?) { store.activeDocument?.duplicateLine(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func deleteLine(_ sender: Any?) { store.activeDocument?.deleteLine(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func moveLineUp(_ sender: Any?) { store.activeDocument?.moveLineUp(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func moveLineDown(_ sender: Any?) { store.activeDocument?.moveLineDown(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func joinLines(_ sender: Any?) { store.activeDocument?.joinLines(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func toggleComment(_ sender: Any?) { store.activeDocument?.toggleComment(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func makeUpperCase(_ sender: Any?) { store.activeDocument?.toUpperCase() }
    @objc func makeLowerCase(_ sender: Any?) { store.activeDocument?.toLowerCase() }
    @objc func sortLinesAscending(_ sender: Any?) { store.activeDocument?.sortLines(ascending: true) }
    @objc func sortLinesDescending(_ sender: Any?) { store.activeDocument?.sortLines(ascending: false) }
    @objc func trimTrailingWhitespace(_ sender: Any?) { store.activeDocument?.trimTrailingWhitespace() }

    // MARK: - Bookmarks & Folding Actions

    @objc func toggleBookmark(_ sender: Any?) { store.activeDocument?.toggleBookmark() }
    @objc func nextBookmark(_ sender: Any?) { store.activeDocument?.nextBookmark(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func previousBookmark(_ sender: Any?) { store.activeDocument?.previousBookmark(); windowController?.mainVC.updateActiveDocumentContent() }
    @objc func clearAllBookmarks(_ sender: Any?) { store.activeDocument?.clearAllBookmarks() }

    @objc func foldAll(_ sender: Any?) { store.activeDocument?.foldAll() }
    @objc func unfoldAll(_ sender: Any?) { store.activeDocument?.unfoldAll() }
    @objc func toggleFoldCurrent(_ sender: Any?) { store.activeDocument?.toggleFoldCurrent() }

    @objc func makeFontBigger(_ sender: Any?) {
        EditorSettings.shared.fontSize = min(36, EditorSettings.shared.fontSize + 1)
        applyGlobalSettings()
    }

    @objc func makeFontSmaller(_ sender: Any?) {
        EditorSettings.shared.fontSize = max(8, EditorSettings.shared.fontSize - 1)
        applyGlobalSettings()
    }

    @objc func resetFontSize(_ sender: Any?) {
        EditorSettings.shared.fontSize = 13
        applyGlobalSettings()
    }

    @objc func toggleWordWrap(_ sender: Any?) {
        EditorSettings.shared.wordWrap.toggle()
        applyGlobalSettings()
    }

    @objc func toggleShowWhitespace(_ sender: Any?) {
        EditorSettings.shared.showWhitespace.toggle()
        applyGlobalSettings()
    }

    @objc func toggleIndentGuides(_ sender: Any?) {
        EditorSettings.shared.showIndentGuides.toggle()
        applyGlobalSettings()
    }

    // MARK: - Menu Construction

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Xeditor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Xeditor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Xeditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        // ⌘T, matching Terminal's New Tab shortcut.
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newDocument(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        let saveAsItem = NSMenuItem(title: "Save As…", action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Close Other Tabs", action: #selector(closeOtherTabs(_:)), keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        // Line Operations
        editMenu.addItem(withTitle: "Duplicate Line", action: #selector(duplicateLine(_:)), keyEquivalent: "d")
        let deleteLineItem = NSMenuItem(title: "Delete Line", action: #selector(deleteLine(_:)), keyEquivalent: "k")
        deleteLineItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(deleteLineItem)

        let moveUpItem = NSMenuItem(title: "Move Line Up", action: #selector(moveLineUp(_:)), keyEquivalent: String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1))
        moveUpItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(title: "Move Line Down", action: #selector(moveLineDown(_:)), keyEquivalent: String(utf16CodeUnits: [unichar(NSDownArrowFunctionKey)], count: 1))
        moveDownItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveDownItem)

        editMenu.addItem(withTitle: "Join Lines", action: #selector(joinLines(_:)), keyEquivalent: "j")
        editMenu.addItem(withTitle: "Toggle Line Comment", action: #selector(toggleComment(_:)), keyEquivalent: "/")
        editMenu.addItem(NSMenuItem.separator())

        // Text transformations submenu
        let transSub = NSMenu(title: "Text Transformations")
        let upperItem = NSMenuItem(title: "Make Upper Case", action: #selector(makeUpperCase(_:)), keyEquivalent: "U")
        transSub.addItem(upperItem)
        transSub.addItem(withTitle: "Make Lower Case", action: #selector(makeLowerCase(_:)), keyEquivalent: "u")
        transSub.addItem(NSMenuItem.separator())
        transSub.addItem(withTitle: "Sort Lines (Ascending)", action: #selector(sortLinesAscending(_:)), keyEquivalent: "")
        transSub.addItem(withTitle: "Sort Lines (Descending)", action: #selector(sortLinesDescending(_:)), keyEquivalent: "")
        transSub.addItem(NSMenuItem.separator())
        transSub.addItem(withTitle: "Trim Trailing Whitespace", action: #selector(trimTrailingWhitespace(_:)), keyEquivalent: "")

        let transMenuItem = NSMenuItem(title: "Text Transformations", action: nil, keyEquivalent: "")
        transMenuItem.submenu = transSub
        editMenu.addItem(transMenuItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Find Menu
        let findMenuItem = NSMenuItem()
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(withTitle: "Find…", action: #selector(showFind(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: "Find Next", action: #selector(findNext(_:)), keyEquivalent: "g")
        let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(findPrevious(_:)), keyEquivalent: "G")
        findMenu.addItem(findPrevItem)
        let replaceItem = NSMenuItem(title: "Find and Replace…", action: #selector(showReplace(_:)), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(replaceItem)
        let dirFindItem = NSMenuItem(title: "Find in Files…", action: #selector(showDirectoryFind(_:)), keyEquivalent: "F")
        findMenu.addItem(dirFindItem)
        let markItem = NSMenuItem(title: "Mark All…", action: #selector(showMark(_:)), keyEquivalent: "m")
        markItem.keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(markItem)
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: "Find All in Current Document", action: #selector(findAllInCurrentDocument(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: "Find All in Open Documents", action: #selector(findAllInOpenDocuments(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: "Replace All in Open Documents", action: #selector(replaceAllInOpenDocuments(_:)), keyEquivalent: "")
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: "Clear Marks", action: #selector(clearFindMarks(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: "Clear Find History", action: #selector(clearFindHistory(_:)), keyEquivalent: "")
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: "Go to Line…", action: #selector(showGoToLine(_:)), keyEquivalent: "l")
        findMenuItem.submenu = findMenu
        mainMenu.addItem(findMenuItem)

        // 5. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        // Folding Submenu
        let foldSub = NSMenu(title: "Code Folding")
        let toggleFoldItem = NSMenuItem(title: "Toggle Current Fold", action: #selector(toggleFoldCurrent(_:)), keyEquivalent: "o")
        toggleFoldItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(toggleFoldItem)
        let foldAllItem = NSMenuItem(title: "Fold All", action: #selector(foldAll(_:)), keyEquivalent: "[")
        foldAllItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(foldAllItem)
        let unfoldAllItem = NSMenuItem(title: "Unfold All", action: #selector(unfoldAll(_:)), keyEquivalent: "]")
        unfoldAllItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(unfoldAllItem)
        let foldMenuItem = NSMenuItem(title: "Code Folding", action: nil, keyEquivalent: "")
        foldMenuItem.submenu = foldSub
        viewMenu.addItem(foldMenuItem)

        // Bookmarks Submenu
        let bmSub = NSMenu(title: "Bookmarks")
        let f2Key = String(utf16CodeUnits: [unichar(NSF2FunctionKey)], count: 1)
        let toggleBm = NSMenuItem(title: "Toggle Bookmark", action: #selector(toggleBookmark(_:)), keyEquivalent: f2Key)
        toggleBm.keyEquivalentModifierMask = [.command]
        bmSub.addItem(toggleBm)
        let nextBm = NSMenuItem(title: "Next Bookmark", action: #selector(nextBookmark(_:)), keyEquivalent: f2Key)
        nextBm.keyEquivalentModifierMask = []
        bmSub.addItem(nextBm)
        let prevBm = NSMenuItem(title: "Previous Bookmark", action: #selector(previousBookmark(_:)), keyEquivalent: f2Key)
        prevBm.keyEquivalentModifierMask = [.shift]
        bmSub.addItem(prevBm)
        bmSub.addItem(NSMenuItem.separator())
        bmSub.addItem(withTitle: "Clear All Bookmarks", action: #selector(clearAllBookmarks(_:)), keyEquivalent: "")
        let bmMenuItem = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
        bmMenuItem.submenu = bmSub
        viewMenu.addItem(bmMenuItem)

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Bigger Font", action: #selector(makeFontBigger(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Smaller Font", action: #selector(makeFontSmaller(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Default Font Size", action: #selector(resetFontSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Word Wrap", action: #selector(toggleWordWrap(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Show Whitespace", action: #selector(toggleShowWhitespace(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Show Indent Guides", action: #selector(toggleIndentGuides(_:)), keyEquivalent: "")

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 6. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(showNextTab(_:)), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.control]
        windowMenu.addItem(nextTabItem)
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(showPreviousTab(_:)), keyEquivalent: "\t")
        prevTabItem.keyEquivalentModifierMask = [.control, .shift]
        windowMenu.addItem(prevTabItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let settings = EditorSettings.shared
        switch menuItem.action {
        case #selector(toggleWordWrap(_:)):
            menuItem.state = settings.wordWrap ? .on : .off
        case #selector(toggleShowWhitespace(_:)):
            menuItem.state = settings.showWhitespace ? .on : .off
        case #selector(toggleIndentGuides(_:)):
            menuItem.state = settings.showIndentGuides ? .on : .off
        default:
            break
        }
        return true
    }
}
