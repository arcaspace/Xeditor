import AppKit

/// One-line field with a leading icon and a history dropdown, drawn as a
/// single rounded box. Used for both the find and replace inputs.
final class FindFieldBox: NSView {
    let textField = NSTextField()
    private let iconView = NSImageView()
    private let historyButton = NSButton()
    private var history: [String] = []

    var onClearHistory: (() -> Void)?
    var isFocused = false {
        didSet { needsDisplay = true }
    }

    init(symbol: String, toolTip: String, placeholder: String) {
        super.init(frame: .zero)

        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.placeholderString = placeholder
        textField.cell?.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown

        historyButton.bezelStyle = .inline
        historyButton.isBordered = false
        historyButton.image = NSImage(systemSymbolName: "chevron.down",
                                      accessibilityDescription: toolTip)
        historyButton.imagePosition = .imageOnly
        historyButton.contentTintColor = .secondaryLabelColor
        historyButton.toolTip = toolTip
        historyButton.target = self
        historyButton.action = #selector(showHistory)
        historyButton.setContentHuggingPriority(.required, for: .horizontal)

        for view in [iconView, historyButton, textField] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            historyButton.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            historyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            historyButton.widthAnchor.constraint(equalToConstant: 14),

            textField.leadingAnchor.constraint(equalTo: historyButton.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHistory(_ items: [String]) {
        history = items
    }

    override func draw(_ dirtyRect: NSRect) {
        if let editor = textField.currentEditor(), window?.firstResponder === editor {
            isFocused = true
        }
        let focused = isFocused
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: focused ? 1.5 : 1,
                                                           dy: focused ? 1.5 : 1),
                                xRadius: 6, yRadius: 6)
        fillColor.setFill()
        path.fill()
        if focused {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            borderColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }

    private var fillColor: NSColor {
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.12, alpha: 1)
        }
        return NSColor.textBackgroundColor
    }

    private var borderColor: NSColor {
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.42, alpha: 0.8)
        }
        return NSColor(calibratedWhite: 0.8, alpha: 1)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textField)
    }

    @objc private func showHistory(_ sender: NSButton) {
        let menu = NSMenu()
        if history.isEmpty {
            let empty = NSMenuItem(title: "No History", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for value in history {
                let item = NSMenuItem(title: value,
                                      action: #selector(historyChosen(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = value
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History",
                                   action: #selector(clearHistory),
                                   keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: 0),
                   in: sender)
    }

    @objc private func historyChosen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        textField.stringValue = value
        window?.makeFirstResponder(textField)
    }

    @objc private func clearHistory() {
        onClearHistory?()
    }
}

/// Shared scaffolding for the find panes: the find/replace fields with their
/// history lists, the regex hint menu, the options row, Return/Escape handling,
/// and the footer buttons.
@MainActor
class FindPaneBase: NSView, NSTextFieldDelegate {
    weak var controller: FindWindowController?

    let searchBox: FindFieldBox
    let replaceBox: FindFieldBox?
    let optionsView: SearchOptionsView

    var searchField: NSTextField { searchBox.textField }
    var replacementField: NSTextField? { replaceBox?.textField }
    var replacementText: String { replacementField?.stringValue ?? "" }

    /// Footer buttons, left and right of the flexible spacer.
    private(set) var footerLeading: [NSView] = []
    private(set) var footerTrailing: [NSView] = []

    private let regexHintButton = NSButton()
    private lazy var regexHelpPopover = RegexHelpPopover.make()

    init(controller: FindWindowController,
         showsReplacement: Bool,
         optionsVariant: SearchOptionsView.Variant) {
        self.controller = controller
        searchBox = FindFieldBox(symbol: "magnifyingglass",
                                 toolTip: "Search history",
                                 placeholder: "Find")
        replaceBox = showsReplacement
            ? FindFieldBox(symbol: "pencil", toolTip: "Replace history", placeholder: "Replace with")
            : nil
        optionsView = SearchOptionsView(variant: optionsVariant)
        super.init(frame: .zero)

        searchField.delegate = self
        replacementField?.delegate = self
        searchBox.onClearHistory = { [weak self] in self?.controller?.clearHistory() }
        replaceBox?.onClearHistory = { [weak self] in self?.controller?.clearHistory() }

        configureRegexHintButton()
        optionsView.trailingAccessory = regexHintButton
        optionsView.onChange = { [weak self] in
            self?.controller?.optionsDidChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Card layout

    /// Builds the field/options column. No card background: the controls sit
    /// directly on the window, aligned with the footer buttons, so light mode
    /// does not show a white block against the window.
    func installCard(extraRows: [NSView] = []) {
        var rows: [NSView] = [searchBox]
        if let replaceBox { rows.append(replaceBox) }
        rows.append(contentsOf: extraRows)
        rows.append(optionsView)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .width

        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        installContent([container])
    }

    /// Pins the pane content to the top of the pane, inset like the window's
    /// footer so fields line up with it.
    func installContent(_ views: [NSView], spacing: CGFloat = 0) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .width
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// Records which buttons the controller should place in the window footer.
    func setFooter(leading: [NSView] = [], trailing: [NSView] = []) {
        footerLeading = leading
        footerTrailing = trailing
    }

    func activate() {
        optionsView.reload()
        reloadHistory()
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
    }

    func reloadHistory() {
        let settings = FindSettings.shared
        searchBox.setHistory(settings.queryHistory)
        replaceBox?.setHistory(settings.replaceHistory)
    }

    /// Enter in the search field. Shift-Enter asks for the previous match.
    func performPrimary(backward: Bool) {
        controller?.performFind(forward: !backward)
    }

    /// Enter in the replacement field.
    func performSecondary() {
        controller?.performReplace()
    }

    // MARK: - Regular-expression help

    private func configureRegexHintButton() {
        let button = regexHintButton
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "questionmark.circle",
                               accessibilityDescription: "Regular expression syntax")
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Regular expression syntax reference"
        button.target = self
        button.action = #selector(showRegexHelp(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: 17).isActive = true
    }

    @objc private func showRegexHelp(_ sender: NSButton) {
        if regexHelpPopover.isShown {
            regexHelpPopover.close()
        } else {
            regexHelpPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidBeginEditing(_ obj: Notification) {
        box(for: obj.object as? NSTextField)?.isFocused = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        box(for: obj.object as? NSTextField)?.isFocused = false
    }

    private func box(for field: NSTextField?) -> FindFieldBox? {
        guard let field else { return nil }
        if field === searchField { return searchBox }
        if field === replacementField { return replaceBox }
        return nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if control === replacementField {
                performSecondary()
            } else {
                performPrimary(backward: shift)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            controller?.closePanel()
            return true
        }
        return false
    }
}
