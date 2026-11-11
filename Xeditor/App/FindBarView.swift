import AppKit

protocol FindBarDelegate: AnyObject {
    func findBarDidFindNext(text: String, flags: XEditorSearchFlags)
    func findBarDidFindPrevious(text: String, flags: XEditorSearchFlags)
    func findBarDidReplace(text: String, replacement: String, flags: XEditorSearchFlags)
    func findBarDidReplaceAll(text: String, replacement: String, flags: XEditorSearchFlags)
    func findBarDidChangeSearchText(text: String, flags: XEditorSearchFlags)
    func findBarDidDismiss()
}

final class FindBarView: NSView, NSSearchFieldDelegate {
    weak var delegate: FindBarDelegate?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let matchCountLabel = NSTextField(labelWithString: "")

    private let caseButton = NSButton()
    private let regexButton = NSButton()
    private let wordButton = NSButton()

    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let closeButton = NSButton()
    private let bottomBorder = NSView()

    var searchFlags: XEditorSearchFlags {
        var flags: XEditorSearchFlags = [.wrap]
        if caseButton.state == .on { flags.insert(.caseSensitive) }
        if regexButton.state == .on { flags.insert(.regex) }
        if wordButton.state == .on { flags.insert(.wholeWord) }
        return flags
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Find Field
        findField.placeholderString = "Find…"
        findField.font = NSFont.systemFont(ofSize: 12)
        findField.delegate = self
        findField.target = self
        findField.action = #selector(onFindNext)
        addSubview(findField)

        // Match count label
        matchCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        matchCountLabel.textColor = .secondaryLabelColor
        matchCountLabel.alignment = .right
        addSubview(matchCountLabel)

        // Case toggle
        configureToggle(caseButton, title: "Aa", tooltip: "Match Case")
        // Regex toggle
        configureToggle(regexButton, title: ".*", tooltip: "Regular Expression")
        // Whole word toggle
        configureToggle(wordButton, title: "\\b", tooltip: "Whole Word")

        // Previous button
        configureIconButton(prevButton, symbolName: "chevron.up", tooltip: "Previous Match (⇧⌘G)", action: #selector(onFindPrev))
        // Next button
        configureIconButton(nextButton, symbolName: "chevron.down", tooltip: "Next Match (⌘G)", action: #selector(onFindNext))

        // Replace Field
        replaceField.placeholderString = "Replace…"
        replaceField.font = NSFont.systemFont(ofSize: 12)
        replaceField.delegate = self
        replaceField.target = self
        replaceField.action = #selector(onReplace)
        addSubview(replaceField)

        // Replace Button
        replaceButton.bezelStyle = .rounded
        replaceButton.title = "Replace"
        replaceButton.font = NSFont.systemFont(ofSize: 11)
        replaceButton.target = self
        replaceButton.action = #selector(onReplace)
        addSubview(replaceButton)

        // Replace All Button
        replaceAllButton.bezelStyle = .rounded
        replaceAllButton.title = "All"
        replaceAllButton.font = NSFont.systemFont(ofSize: 11)
        replaceAllButton.target = self
        replaceAllButton.action = #selector(onReplaceAll)
        addSubview(replaceAllButton)

        // Close button
        configureIconButton(closeButton, symbolName: "xmark", tooltip: "Done (Esc)", action: #selector(onClose))

        // Bottom border line
        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(bottomBorder)
    }

    private func configureToggle(_ button: NSButton, title: String, tooltip: String) {
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .inline
        button.title = title
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(onOptionChanged)
        addSubview(button)
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String, action: Selector) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            let conf = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            button.image = img.withSymbolConfiguration(conf)
        }
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        addSubview(button)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Resolve inside the new appearance: NSAppearance.current is still the
        // old one here, so a bare `.cgColor` would keep the old colours.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            bottomBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let y: CGFloat = (h - 22) / 2

        var x: CGFloat = 10

        // Find field
        findField.frame = NSRect(x: x, y: y, width: 170, height: 22)
        x += 175

        // Match count
        matchCountLabel.frame = NSRect(x: x, y: y + 2, width: 44, height: 18)
        x += 48

        // Option toggles
        caseButton.frame = NSRect(x: x, y: y, width: 26, height: 22)
        x += 28
        regexButton.frame = NSRect(x: x, y: y, width: 26, height: 22)
        x += 28
        wordButton.frame = NSRect(x: x, y: y, width: 26, height: 22)
        x += 32

        // Prev / Next
        prevButton.frame = NSRect(x: x, y: y, width: 20, height: 22)
        x += 22
        nextButton.frame = NSRect(x: x, y: y, width: 20, height: 22)
        x += 28

        // Replace field
        replaceField.frame = NSRect(x: x, y: y, width: 150, height: 22)
        x += 155

        // Replace buttons
        replaceButton.frame = NSRect(x: x, y: y - 1, width: 68, height: 24)
        x += 72
        replaceAllButton.frame = NSRect(x: x, y: y - 1, width: 46, height: 24)
        x += 50

        // Close button (pinned right)
        closeButton.frame = NSRect(x: bounds.width - 26, y: y, width: 20, height: 22)

        bottomBorder.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    func setInitialText(_ text: String) {
        if !text.isEmpty {
            findField.stringValue = text
        }
        window?.makeFirstResponder(findField)
        onOptionChanged()
    }

    func updateMatchCount(_ count: Int) {
        if findField.stringValue.isEmpty {
            matchCountLabel.stringValue = ""
        } else {
            matchCountLabel.stringValue = "\(count)"
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        delegate?.findBarDidChangeSearchText(text: findField.stringValue, flags: searchFlags)
    }

    @objc private func onFindNext() {
        delegate?.findBarDidFindNext(text: findField.stringValue, flags: searchFlags)
    }

    @objc private func onFindPrev() {
        delegate?.findBarDidFindPrevious(text: findField.stringValue, flags: searchFlags)
    }

    @objc private func onReplace() {
        delegate?.findBarDidReplace(text: findField.stringValue, replacement: replaceField.stringValue, flags: searchFlags)
    }

    @objc private func onReplaceAll() {
        delegate?.findBarDidReplaceAll(text: findField.stringValue, replacement: replaceField.stringValue, flags: searchFlags)
    }

    @objc private func onOptionChanged() {
        delegate?.findBarDidChangeSearchText(text: findField.stringValue, flags: searchFlags)
    }

    @objc private func onClose() {
        delegate?.findBarDidDismiss()
    }
}
