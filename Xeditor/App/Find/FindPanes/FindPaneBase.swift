import AppKit

/// Shared scaffolding for the find panes: the search/replacement fields with
/// history, the regex hint menu, Return/Escape handling and the two-column
/// layout (content on the left, wide action buttons on the right).
@MainActor
class FindPaneBase: NSView, NSComboBoxDelegate {
    weak var controller: FindWindowController?

    let searchField: NSComboBox
    let replacementField: NSComboBox?
    let optionsView: SearchOptionsView

    var replacementText: String { replacementField?.stringValue ?? "" }

    private let regexHint = NSPopUpButton(frame: .zero, pullsDown: true)

    private static let regexSnippets: [(String, String)] = [
        ("Any character  .", "."),
        ("Digits  \\d", "\\d"),
        ("Word characters  \\w", "\\w"),
        ("Whitespace  \\s", "\\s"),
        ("Any sequence  .*", ".*"),
        ("One or more  +", "+"),
        ("Zero or one  ?", "?"),
        ("Line start  ^", "^"),
        ("Line end  $", "$"),
        ("Character set  [abc]", "[abc]"),
        ("Negated set  [^abc]", "[^abc]"),
        ("Group  ( )", "()"),
        ("Either  a|b", "|"),
        ("Back-reference  \\1", "\\1")
    ]

    init(controller: FindWindowController,
         showsReplacement: Bool,
         optionsVariant: SearchOptionsView.Variant) {
        self.controller = controller
        self.searchField = FindUI.combo(history: FindSettings.shared.queryHistory)
        self.replacementField = showsReplacement
            ? FindUI.combo(history: FindSettings.shared.replaceHistory)
            : nil
        self.optionsView = SearchOptionsView(variant: optionsVariant)
        super.init(frame: .zero)

        searchField.delegate = self
        replacementField?.delegate = self
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        replacementField?.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        configureRegexHint()
        optionsView.onChange = { [weak self] in
            self?.controller?.optionsDidChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout helpers

    /// "Find:" row with the search field and the regex hint dropdown.
    func searchRow(label: String = "Find:") -> NSStackView {
        regexHint.widthAnchor.constraint(equalToConstant: 108).isActive = true
        let controls = FindUI.horizontal([searchField, regexHint], spacing: 8)
        return FindUI.row(label, controls)
    }

    func replacementRow(label: String = "Replace with:") -> NSStackView {
        guard let replacementField else {
            return FindUI.row(label, NSView())
        }
        return FindUI.row(label, replacementField)
    }

    /// Two-column body: `left` stretches to the pane height, `rightViews` form
    /// the full-width action column.
    func install(left: NSView, rightViews: [NSView]) {
        let right = FindUI.verticalFill(rightViews, spacing: 10)
        addSubview(left)
        addSubview(right)
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            left.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 24),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            right.widthAnchor.constraint(equalToConstant: 220)
        ])
        // Every left-column row spans the pane so fields line up on the right
        // edge, as in notepad--'s dialog.
        if let stack = left as? NSStackView {
            for subview in stack.arrangedSubviews {
                subview.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
            }
        }
    }

    /// Spacer that pushes the options block to the bottom of the left column.
    func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return spacer
    }

    func activate() {
        optionsView.reload()
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
    }

    func reloadHistory() {
        let settings = FindSettings.shared
        searchField.removeAllItems()
        searchField.addItems(withObjectValues: settings.queryHistory)
        replacementField?.removeAllItems()
        replacementField?.addItems(withObjectValues: settings.replaceHistory)
    }

    /// Enter in the search field. Shift-Enter asks for the previous match.
    func performPrimary(backward: Bool) {
        controller?.performFind(forward: !backward)
    }

    /// Enter in the replacement field.
    func performSecondary() {
        controller?.performReplace()
    }

    // MARK: - Regex hint

    private func configureRegexHint() {
        regexHint.addItem(withTitle: "Regex Hint")
        regexHint.menu?.addItem(NSMenuItem.separator())
        for (title, snippet) in Self.regexSnippets {
            let item = NSMenuItem(title: title, action: #selector(regexHintChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = snippet
            regexHint.menu?.addItem(item)
        }
        regexHint.toolTip = "Insert a regular-expression snippet into the search field."
    }

    @objc private func regexHintChosen(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? String else { return }
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.insertText(snippet, replacementRange: editor.selectedRange())
        } else {
            searchField.stringValue += snippet
        }
        window?.makeFirstResponder(searchField)
    }

    // MARK: - NSComboBoxDelegate / NSControlTextEditingDelegate

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
