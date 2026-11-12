import AppKit

/// Dir Find tab: search (and replace) across a directory tree on disk.
final class DirFindPaneView: FindPaneBase {
    private let settings = FindSettings.shared
    private let directoryField = FindUI.field("/path/to/folder")
    private let fileTypesField = FindUI.field("*.c:*.cpp:*.h")
    private let fileNameRegexField = FindUI.field("optional regular expression")
    private let skipFoldersField = FindUI.field("debug:Debug:.git:.svn")
    private let maxSizeField = FindUI.field("20")
    private let maxSizeStepper = NSStepper()
    private let hiddenBox: NSButton
    private let binaryBox: NSButton
    private let largeBox: NSButton
    private let subdirsBox: NSButton
    private let progress = NSProgressIndicator()
    private let cancelButton: NSButton

    private(set) var isRunning = false

    init(controller: FindWindowController) {
        hiddenBox = FindUI.checkbox("Skip hidden files", target: nil, action: nil, on: settings.dirSkipHidden)
        binaryBox = FindUI.checkbox("Skip binary files", target: nil, action: nil, on: settings.dirSkipBinary)
        largeBox = FindUI.checkbox("Skip files over", target: nil, action: nil, on: settings.dirSkipLarge)
        subdirsBox = FindUI.checkbox("Skip subdirectories", target: nil, action: nil, on: settings.dirSkipSubdirectories)
        cancelButton = FindUI.button("Cancel", target: nil, action: nil)
        super.init(controller: controller, showsReplacement: true, optionsVariant: .directory)

        for box in [hiddenBox, binaryBox, largeBox, subdirsBox] {
            box.target = self
            box.action = #selector(optionChanged)
        }
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.isHidden = true

        directoryField.stringValue = settings.dirPath
        fileTypesField.stringValue = settings.dirFileTypes
        fileNameRegexField.stringValue = settings.dirFileNameRegex
        skipFoldersField.stringValue = settings.dirSkipFolders
        maxSizeField.stringValue = String(settings.dirMaxSizeMB)
        maxSizeField.alignment = .right
        maxSizeField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        maxSizeField.target = self
        maxSizeField.action = #selector(maxSizeChanged)

        maxSizeStepper.minValue = 1
        maxSizeStepper.maxValue = 2048
        maxSizeStepper.increment = 1
        maxSizeStepper.integerValue = settings.dirMaxSizeMB
        maxSizeStepper.target = self
        maxSizeStepper.action = #selector(stepperChanged)

        let choose = FindUI.button("Choose…", target: self, action: #selector(chooseDirectory))
        directoryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let dirRow = FindUI.row("Directory:", FindUI.horizontal([directoryField, choose]))
        fileTypesField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        fileNameRegexField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        skipFoldersField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let largeRow = FindUI.vertical([
            largeBox,
            FindUI.horizontal([maxSizeField, maxSizeStepper, FindUI.label("MB")], spacing: 6)
        ], spacing: 6)
        largeRow.arrangedSubviews[1].widthAnchor.constraint(equalTo: largeRow.widthAnchor).isActive = true
        let optionsGroup = FindUI.group("Options", [subdirsBox, hiddenBox, binaryBox, largeRow], spacing: 8)

        let findButton = FindUI.actionButton("Find All", target: self, action: #selector(findAll))
        findButton.keyEquivalent = "\r"
        let replaceButton = FindUI.actionButton("Replace in Directory", target: self, action: #selector(replaceAll))
        let clearResults = FindUI.actionButton("Clear Results", target: self, action: #selector(clearResults))
        let close = FindUI.actionButton("Close", target: self, action: #selector(closePanel))

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        progress.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let filters = FindUI.vertical([
            FindUI.row("File types:", fileTypesField),
            FindUI.row("File name regex:", fileNameRegexField),
            FindUI.row("Skip folders:", skipFoldersField)
        ], spacing: 10)

        let left = FindUI.vertical([
            dirRow,
            searchRow(),
            replacementRow(),
            filters,
            flexibleSpacer(),
            optionsView
        ], spacing: 12)

        install(left: left,
                rightViews: [findButton, replaceButton, clearResults, close,
                             progress, cancelButton, optionsGroup])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func activate() {
        super.activate()
        // Keep the on-disk fields in sync with whatever another tab saved.
        directoryField.stringValue = settings.dirPath
        fileTypesField.stringValue = settings.dirFileTypes
        fileNameRegexField.stringValue = settings.dirFileNameRegex
        skipFoldersField.stringValue = settings.dirSkipFolders
    }

    /// Return searches the directory, matching the default button.
    override func performPrimary(backward: Bool) {
        controller?.performDirSearch(replace: false)
    }

    override func performSecondary() {
        controller?.performDirSearch(replace: true)
    }

    func makeOptions() -> DirSearchOptions? {
        persistOptions()
        let path = directoryField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        guard !searchField.stringValue.isEmpty else { return nil }

        let query = controller?.makeQuery(text: searchField.stringValue,
                                          replacement: replacementText) ?? SearchQuery(
            text: searchField.stringValue,
            replacement: replacementText,
            mode: settings.mode,
            matchCase: settings.matchCase,
            wholeWord: settings.wholeWord,
            wrap: settings.wrap,
            backward: settings.backward,
            inSelection: false)

        return DirSearchOptions(directory: url,
                                query: query,
                                fileTypes: fileTypesField.stringValue,
                                fileNameRegex: fileNameRegexField.stringValue,
                                skipFolders: skipFoldersField.stringValue,
                                skipHidden: hiddenBox.state == .on,
                                skipBinary: binaryBox.state == .on,
                                skipLargeFiles: largeBox.state == .on,
                                maxFileSize: max(1, Int(maxSizeField.stringValue) ?? 20) * 1024 * 1024,
                                skipSubdirectories: subdirsBox.state == .on)
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        cancelButton.isHidden = !running
        progress.isHidden = !running
        if !running {
            progress.doubleValue = 0
        }
    }

    func updateProgress(scanned: Int, total: Int, hits: Int) {
        progress.maxValue = Double(max(1, total))
        progress.doubleValue = Double(min(scanned, total))
        controller?.setStatus("Scanning \(scanned) / \(total) files — \(hits) matches",
                              kind: .info)
    }

    private func persistOptions() {
        settings.dirPath = directoryField.stringValue
        settings.dirFileTypes = fileTypesField.stringValue
        settings.dirFileNameRegex = fileNameRegexField.stringValue
        settings.dirSkipFolders = skipFoldersField.stringValue
        settings.dirSkipHidden = hiddenBox.state == .on
        settings.dirSkipBinary = binaryBox.state == .on
        settings.dirSkipLarge = largeBox.state == .on
        settings.dirMaxSizeMB = max(1, Int(maxSizeField.stringValue) ?? 20)
        settings.dirSkipSubdirectories = subdirsBox.state == .on
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directoryField.stringValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directoryField.stringValue = url.path
        persistOptions()
    }

    @objc private func optionChanged() {
        persistOptions()
    }

    @objc private func stepperChanged() {
        maxSizeField.stringValue = String(maxSizeStepper.integerValue)
        persistOptions()
    }

    @objc private func maxSizeChanged() {
        maxSizeStepper.integerValue = max(1, Int(maxSizeField.stringValue) ?? 20)
        persistOptions()
    }

    @objc private func findAll() {
        controller?.performDirSearch(replace: false)
    }

    @objc private func replaceAll() {
        controller?.performDirSearch(replace: true)
    }

    @objc private func clearResults() {
        controller?.clearResults()
    }

    @objc private func cancel() {
        controller?.cancelDirSearch()
    }

    @objc private func closePanel() { controller?.closePanel() }
}
