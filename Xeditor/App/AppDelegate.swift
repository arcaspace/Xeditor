import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, PreferencesDelegate, GoToLineDelegate {
    let store = DocumentStore()
    private var windowController: MainWindowController?
    private var preferencesController: PreferencesWindowController?
    private var goToLineController: GoToLineWindowController?
    private var findController: FindWindowController?
    private var compareToolController: CompareToolWindowController?
    private var hashToolController: HashToolWindowController?
    private var codecToolController: CodecToolWindowController?
    private var structuredToolController: StructuredToolWindowController?
    private var conversionToolController: ConversionToolWindowController?
    private var appearanceObservation: NSKeyValueObservation?

    private static let sessionFilesKey = "session.files"
    private static let sessionActiveKey = "session.activeIndex"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Build Menu Bar
        buildMainMenu()

        // Rebuild the chrome when the UI language changes in Preferences.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(languageDidChange),
                                               name: Localization.didChangeNotification,
                                               object: nil)

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
        applyApplicationIcon()
    }

    /// The standard About panel does not consult CFBundleIconFile in this
    /// build, so the icon is loaded explicitly and handed to it.
    private func applyApplicationIcon() {
        guard let icon = bundledAppIcon else { return }
        NSApp.applicationIconImage = icon
    }

    private var bundledAppIcon: NSImage? {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
            ?? "AppIcon"
        let resource = name.hasSuffix(".icns") ? String(name.dropLast(5)) : name
        guard let url = Bundle.main.url(forResource: resource, withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    @objc private func showAboutPanel(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let icon = bundledAppIcon ?? NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        }
        // The panel appends the build number as "0.2.0 (2)" when CFBundleVersion
        // is present; the build number is release bookkeeping, not part of the
        // version users should read, so keep the Version line to the marketing
        // version alone.
        options[.version] = ""
        NSApp.orderFrontStandardAboutPanel(options: options)
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
        // The delegate must acknowledge the open request, or Finder reports
        // that the document could not be opened.
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let mainVC = windowController?.mainVC else { return .terminateNow }
        for document in store.documents where document.isDirty {
            guard mainVC.confirmSaveIfNeeded(document) else { return .terminateCancel }
        }
        return .terminateNow
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
        panel.title = L("Open File")
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

    /// Applies a language picked in Preferences to everything that is already
    /// on screen. Tool windows are closed rather than rebuilt in place: they
    /// are transient, and a fresh window picks up the new strings on open.
    @objc private func languageDidChange() {
        buildMainMenu()
        windowController?.mainVC.applyLocalization()
        findController?.applyLocalization()
        preferencesController?.applyLocalization()
        closeToolWindows()
    }

    private func closeToolWindows() {
        compareToolController?.close()
        hashToolController?.close()
        codecToolController?.close()
        structuredToolController?.close()
        conversionToolController?.close()
        goToLineController?.close()
        compareToolController = nil
        hashToolController = nil
        codecToolController = nil
        structuredToolController = nil
        conversionToolController = nil
        goToLineController = nil
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(delegate: self)
        }
        preferencesController?.showWindow(nil)
    }

    // MARK: - Tools

    @objc func showCompareTool(_ sender: Any?) {
        if compareToolController == nil {
            compareToolController = CompareToolWindowController(store: store)
        }
        compareToolController?.present()
    }

    @objc func showHashTool(_ sender: Any?) {
        if hashToolController == nil {
            hashToolController = HashToolWindowController(store: store)
        }
        hashToolController?.present()
    }

    @objc func showCodecTool(_ sender: Any?) {
        if codecToolController == nil {
            codecToolController = CodecToolWindowController(store: store)
        }
        codecToolController?.present()
    }

    @objc func showStructuredTool(_ sender: Any?) {
        if structuredToolController == nil {
            let controller = StructuredToolWindowController(store: store)
            controller.onEditorChanged = { [weak self] in
                self?.windowController?.mainVC.updateActiveDocumentContent()
            }
            structuredToolController = controller
        }
        structuredToolController?.present()
    }

    @objc func showConversionTool(_ sender: Any?) {
        if conversionToolController == nil {
            let controller = ConversionToolWindowController(store: store)
            controller.onEditorChanged = { [weak self] in
                self?.windowController?.mainVC.updateActiveDocumentContent()
            }
            conversionToolController = controller
        }
        conversionToolController?.present()
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
        appMenu.addItem(withTitle: L("About Xeditor"), action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("Preferences…"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("Hide Xeditor"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("Quit Xeditor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File"))
        // ⌘T, matching Terminal's New Tab shortcut.
        fileMenu.addItem(withTitle: L("New Tab"), action: #selector(newDocument(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: L("Open…"), action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L("Save"), action: #selector(saveDocument(_:)), keyEquivalent: "s")
        let saveAsItem = NSMenuItem(title: L("Save As…"), action: #selector(saveDocumentAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L("Close Tab"), action: #selector(closeTab(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: L("Close Other Tabs"), action: #selector(closeOtherTabs(_:)), keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L("Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        // Line Operations
        editMenu.addItem(withTitle: L("Duplicate Line"), action: #selector(duplicateLine(_:)), keyEquivalent: "d")
        let deleteLineItem = NSMenuItem(title: L("Delete Line"), action: #selector(deleteLine(_:)), keyEquivalent: "k")
        deleteLineItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(deleteLineItem)

        let moveUpItem = NSMenuItem(title: L("Move Line Up"), action: #selector(moveLineUp(_:)), keyEquivalent: String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1))
        moveUpItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(title: L("Move Line Down"), action: #selector(moveLineDown(_:)), keyEquivalent: String(utf16CodeUnits: [unichar(NSDownArrowFunctionKey)], count: 1))
        moveDownItem.keyEquivalentModifierMask = [.option]
        editMenu.addItem(moveDownItem)

        editMenu.addItem(withTitle: L("Join Lines"), action: #selector(joinLines(_:)), keyEquivalent: "j")
        editMenu.addItem(withTitle: L("Toggle Line Comment"), action: #selector(toggleComment(_:)), keyEquivalent: "/")
        editMenu.addItem(NSMenuItem.separator())

        // Text transformations submenu
        let transSub = NSMenu(title: L("Text Transformations"))
        let upperItem = NSMenuItem(title: L("Make Upper Case"), action: #selector(makeUpperCase(_:)), keyEquivalent: "U")
        transSub.addItem(upperItem)
        transSub.addItem(withTitle: L("Make Lower Case"), action: #selector(makeLowerCase(_:)), keyEquivalent: "u")
        transSub.addItem(NSMenuItem.separator())
        transSub.addItem(withTitle: L("Sort Lines (Ascending)"), action: #selector(sortLinesAscending(_:)), keyEquivalent: "")
        transSub.addItem(withTitle: L("Sort Lines (Descending)"), action: #selector(sortLinesDescending(_:)), keyEquivalent: "")
        transSub.addItem(NSMenuItem.separator())
        transSub.addItem(withTitle: L("Trim Trailing Whitespace"), action: #selector(trimTrailingWhitespace(_:)), keyEquivalent: "")

        let transMenuItem = NSMenuItem(title: L("Text Transformations"), action: nil, keyEquivalent: "")
        transMenuItem.submenu = transSub
        editMenu.addItem(transMenuItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Find Menu
        let findMenuItem = NSMenuItem()
        let findMenu = NSMenu(title: L("Find"))
        findMenu.addItem(withTitle: L("Find…"), action: #selector(showFind(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: L("Find Next"), action: #selector(findNext(_:)), keyEquivalent: "g")
        let findPrevItem = NSMenuItem(title: L("Find Previous"), action: #selector(findPrevious(_:)), keyEquivalent: "G")
        findMenu.addItem(findPrevItem)
        let replaceItem = NSMenuItem(title: L("Find and Replace…"), action: #selector(showReplace(_:)), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(replaceItem)
        let markItem = NSMenuItem(title: L("Mark All…"), action: #selector(showMark(_:)), keyEquivalent: "m")
        markItem.keyEquivalentModifierMask = [.command, .option]
        findMenu.addItem(markItem)
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: L("Find All in Current Document"), action: #selector(findAllInCurrentDocument(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: L("Find All in Open Documents"), action: #selector(findAllInOpenDocuments(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: L("Replace All in Open Documents"), action: #selector(replaceAllInOpenDocuments(_:)), keyEquivalent: "")
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: L("Clear Marks"), action: #selector(clearFindMarks(_:)), keyEquivalent: "")
        findMenu.addItem(withTitle: L("Clear Find History"), action: #selector(clearFindHistory(_:)), keyEquivalent: "")
        findMenu.addItem(NSMenuItem.separator())
        findMenu.addItem(withTitle: L("Go to Line…"), action: #selector(showGoToLine(_:)), keyEquivalent: "l")
        findMenuItem.submenu = findMenu
        mainMenu.addItem(findMenuItem)

        // 5. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: L("View"))

        // Folding Submenu
        let foldSub = NSMenu(title: L("Code Folding"))
        let toggleFoldItem = NSMenuItem(title: L("Toggle Current Fold"), action: #selector(toggleFoldCurrent(_:)), keyEquivalent: "o")
        toggleFoldItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(toggleFoldItem)
        let foldAllItem = NSMenuItem(title: L("Fold All"), action: #selector(foldAll(_:)), keyEquivalent: "[")
        foldAllItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(foldAllItem)
        let unfoldAllItem = NSMenuItem(title: L("Unfold All"), action: #selector(unfoldAll(_:)), keyEquivalent: "]")
        unfoldAllItem.keyEquivalentModifierMask = [.command, .option]
        foldSub.addItem(unfoldAllItem)
        let foldMenuItem = NSMenuItem(title: L("Code Folding"), action: nil, keyEquivalent: "")
        foldMenuItem.submenu = foldSub
        viewMenu.addItem(foldMenuItem)

        // Bookmarks Submenu
        let bmSub = NSMenu(title: L("Bookmarks"))
        let f2Key = String(utf16CodeUnits: [unichar(NSF2FunctionKey)], count: 1)
        let toggleBm = NSMenuItem(title: L("Toggle Bookmark"), action: #selector(toggleBookmark(_:)), keyEquivalent: f2Key)
        toggleBm.keyEquivalentModifierMask = [.command]
        bmSub.addItem(toggleBm)
        let nextBm = NSMenuItem(title: L("Next Bookmark"), action: #selector(nextBookmark(_:)), keyEquivalent: f2Key)
        nextBm.keyEquivalentModifierMask = []
        bmSub.addItem(nextBm)
        let prevBm = NSMenuItem(title: L("Previous Bookmark"), action: #selector(previousBookmark(_:)), keyEquivalent: f2Key)
        prevBm.keyEquivalentModifierMask = [.shift]
        bmSub.addItem(prevBm)
        bmSub.addItem(NSMenuItem.separator())
        bmSub.addItem(withTitle: L("Clear All Bookmarks"), action: #selector(clearAllBookmarks(_:)), keyEquivalent: "")
        let bmMenuItem = NSMenuItem(title: L("Bookmarks"), action: nil, keyEquivalent: "")
        bmMenuItem.submenu = bmSub
        viewMenu.addItem(bmMenuItem)

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: L("Bigger Font"), action: #selector(makeFontBigger(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: L("Smaller Font"), action: #selector(makeFontSmaller(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: L("Default Font Size"), action: #selector(resetFontSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: L("Toggle Word Wrap"), action: #selector(toggleWordWrap(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: L("Show Whitespace"), action: #selector(toggleShowWhitespace(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: L("Show Indent Guides"), action: #selector(toggleIndentGuides(_:)), keyEquivalent: "")

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 6. Tools Menu
        let toolsMenuItem = NSMenuItem()
        let toolsMenu = NSMenu(title: L("Tools"))
        let compareItem = NSMenuItem(title: L("Compare Files…"), action: #selector(showCompareTool(_:)), keyEquivalent: "D")
        toolsMenu.addItem(compareItem)
        toolsMenu.addItem(NSMenuItem.separator())
        toolsMenu.addItem(withTitle: L("MD5 / SHA…"), action: #selector(showHashTool(_:)), keyEquivalent: "")
        toolsMenu.addItem(withTitle: L("Base64 / URL…"), action: #selector(showCodecTool(_:)), keyEquivalent: "")
        toolsMenu.addItem(withTitle: L("Structured Data…"), action: #selector(showStructuredTool(_:)), keyEquivalent: "")
        toolsMenu.addItem(withTitle: L("JSON ⇄ YAML…"), action: #selector(showConversionTool(_:)), keyEquivalent: "")
        toolsMenuItem.submenu = toolsMenu
        mainMenu.addItem(toolsMenuItem)

        // 7. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("Zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        let nextTabItem = NSMenuItem(title: L("Show Next Tab"), action: #selector(showNextTab(_:)), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.control]
        windowMenu.addItem(nextTabItem)
        let prevTabItem = NSMenuItem(title: L("Show Previous Tab"), action: #selector(showPreviousTab(_:)), keyEquivalent: "\t")
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
