import AppKit

/// One row of search options — the checkboxes (including Regular Expression)
/// in one left-aligned group, matching macOS find windows.
final class SearchOptionsView: NSView {
    enum Variant {
        case findReplace
        case mark
    }

    var onChange: (() -> Void)?

    private let settings = FindSettings.shared
    private let variant: Variant
    private let backwardBox: NSButton?
    private let caseBox: NSButton
    private let wordBox: NSButton
    private let wrapBox: NSButton?
    private let regexBox: NSButton
    private let optionsRow = NSStackView()
    private let row = NSStackView()

    /// Optional control placed right after the Regular Expression checkbox
    /// (regex help).
    var trailingAccessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let trailingAccessory {
                optionsRow.setCustomSpacing(-4, after: regexBox)
                optionsRow.addArrangedSubview(trailingAccessory)
            }
        }
    }

    init(variant: Variant) {
        self.variant = variant
        caseBox = FindUI.checkbox("Match case", target: nil, action: nil, on: false)
        wordBox = FindUI.checkbox("Whole word", target: nil, action: nil, on: false)
        regexBox = FindUI.checkbox("Regular Expression", target: nil, action: nil, on: false)
        if variant == .findReplace {
            backwardBox = FindUI.checkbox("Backward", target: nil, action: nil, on: false)
            wrapBox = FindUI.checkbox("Wrap around", target: nil, action: nil, on: true)
        } else {
            backwardBox = nil
            wrapBox = nil
        }

        super.init(frame: .zero)

        var options: [NSView] = [wordBox, caseBox]
        if let wrapBox { options.append(wrapBox) }
        if let backwardBox { options.append(backwardBox) }
        options.append(regexBox)
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 12
        for view in options {
            optionsRow.addArrangedSubview(view)
        }

        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(optionsRow)
        row.addArrangedSubview(FindUI.spacer())
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for view in [backwardBox, caseBox, wordBox, wrapBox, regexBox].compactMap({ $0 }) {
            view.target = self
            view.action = #selector(optionChanged)
        }
        regexBox.action = #selector(regexChanged)
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
        regexBox.state = settings.mode == .regex ? .on : .off
        // Scintilla's regex engine ignores whole-word, so leaving the box
        // enabled would silently lie.
        wordBox.isEnabled = settings.mode != .regex
    }

    @objc private func regexChanged() {
        settings.mode = regexBox.state == .on ? .regex : .normal
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
