import AppKit

/// Left-column options for every pane: the vertical option checkboxes and the
/// "Search Mode" group box, matching notepad--'s dialog.
final class SearchOptionsView: NSView {
    enum Variant {
        case findReplace
        case mark
        case directory
    }

    var onChange: (() -> Void)?

    private let settings = FindSettings.shared
    private let variant: Variant
    private let backwardBox: NSButton?
    private let caseBox: NSButton
    private let wordBox: NSButton
    private let wrapBox: NSButton?
    private var modeButtons: [NSButton] = []

    init(variant: Variant) {
        self.variant = variant
        caseBox = FindUI.checkbox("Match case", target: nil, action: nil, on: false)
        wordBox = FindUI.checkbox("Whole word", target: nil, action: nil, on: false)
        if variant == .findReplace {
            backwardBox = FindUI.checkbox("Backward", target: nil, action: nil, on: false)
            wrapBox = FindUI.checkbox("Wrap around", target: nil, action: nil, on: true)
        } else {
            backwardBox = nil
            wrapBox = nil
        }

        super.init(frame: .zero)

        var checkboxes: [NSView] = []
        if let backwardBox { checkboxes.append(backwardBox) }
        checkboxes.append(wordBox)
        checkboxes.append(caseBox)
        if let wrapBox { checkboxes.append(wrapBox) }

        let optionsStack = FindUI.vertical(checkboxes, spacing: 12)

        let modeViews: [NSView] = SearchMode.allCases.map { mode in
            let button = FindUI.radio(mode.title, target: self, action: #selector(modeChanged(_:)), on: false)
            button.tag = SearchMode.allCases.firstIndex(of: mode) ?? 0
            if mode == .extended {
                button.title = "Extended  (\\n, \\r, \\t, \\0, \\x…)"
            }
            modeButtons.append(button)
            return button
        }
        let modeGroup = FindUI.group("Search Mode", modeViews, spacing: 6)

        let stack = FindUI.verticalFill([optionsStack, modeGroup], spacing: 18)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        for view in [backwardBox, caseBox, wordBox, wrapBox].compactMap({ $0 }) {
            view.target = self
            view.action = #selector(optionChanged)
        }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        backwardBox?.state = settings.backward ? .on : .off
        caseBox.state = settings.matchCase ? .on : .off
        wordBox.state = settings.wholeWord ? .on : .off
        wrapBox?.state = settings.wrap ? .on : .off
        for button in modeButtons {
            button.state = button.tag == SearchMode.allCases.firstIndex(of: settings.mode) ? .on : .off
        }
        // Scintilla's regex engine ignores whole-word, so leaving the box
        // enabled would silently lie.
        wordBox.isEnabled = settings.mode != .regex
    }

    @objc private func modeChanged(_ sender: NSButton) {
        guard SearchMode.allCases.indices.contains(sender.tag) else { return }
        settings.mode = SearchMode.allCases[sender.tag]
        reload()
        onChange?()
    }

    @objc private func optionChanged() {
        if let backwardBox { settings.backward = backwardBox.state == .on }
        settings.matchCase = caseBox.state == .on
        settings.wholeWord = wordBox.state == .on
        if let wrapBox { settings.wrap = wrapBox.state == .on }
        onChange?()
    }
}
