import AppKit

protocol StatusBarDelegate: AnyObject {
    func statusBarDidChangeLanguage(_ preset: LanguagePreset)
    func statusBarDidChangeEncoding(_ encoding: DocumentEncoding)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarDelegate?

    private let positionLabel = NSTextField(labelWithString: "")
    private let lineCountLabel = NSTextField(labelWithString: "")
    private let languageButton = NSPopUpButton()
    private let encodingButton = NSPopUpButton()
    private let topBorder = NSView()

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

        // Top border
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(topBorder)

        // Labels
        configureLabel(positionLabel)
        configureLabel(lineCountLabel)

        // Language PopUp
        configurePopUp(languageButton, action: #selector(onLanguageSelected))
        for preset in LanguagePreset.all {
            languageButton.addItem(withTitle: preset.title)
        }

        // Encoding PopUp
        configurePopUp(encodingButton, action: #selector(onEncodingSelected))
        for enc in DocumentEncoding.allSupported {
            encodingButton.addItem(withTitle: enc.name)
        }
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        addSubview(label)
    }

    private func configurePopUp(_ button: NSPopUpButton, action: Selector) {
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11)
        button.target = self
        button.action = action
        addSubview(button)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let y: CGFloat = (h - 18) / 2

        topBorder.frame = NSRect(x: 0, y: h - 1, width: bounds.width, height: 1)

        // Right-aligned items
        var x = bounds.width - 12

        // Encoding button
        let encSize = encodingButton.sizeThatFits(NSSize(width: 300, height: 18))
        x -= encSize.width
        encodingButton.frame = NSRect(x: x, y: y, width: encSize.width, height: 18)
        x -= 12

        // Language button
        let langSize = languageButton.sizeThatFits(NSSize(width: 300, height: 18))
        x -= langSize.width
        languageButton.frame = NSRect(x: x, y: y, width: langSize.width, height: 18)
        x -= 16

        // Line count
        let linesWidth: CGFloat = 80
        x -= linesWidth
        lineCountLabel.frame = NSRect(x: x, y: y, width: linesWidth, height: 18)
        x -= 12

        // Position label
        let posWidth: CGFloat = 110
        x -= posWidth
        positionLabel.frame = NSRect(x: x, y: y, width: posWidth, height: 18)
    }

    func update(document: EditorDocument?) {
        guard let doc = document else {
            positionLabel.stringValue = ""
            lineCountLabel.stringValue = ""
            languageButton.isHidden = true
            encodingButton.isHidden = true
            return
        }

        languageButton.isHidden = false
        encodingButton.isHidden = false

        positionLabel.stringValue = "Ln \(doc.cursorLine), Col \(doc.cursorColumn)"
        lineCountLabel.stringValue = "\(doc.lineCount) lines"

        languageButton.selectItem(withTitle: doc.language.title)
        encodingButton.selectItem(withTitle: doc.encoding.name)

        needsLayout = true
    }

    @objc private func onLanguageSelected() {
        guard let title = languageButton.titleOfSelectedItem,
              let preset = LanguagePreset.all.first(where: { $0.title == title }) else { return }
        delegate?.statusBarDidChangeLanguage(preset)
    }

    @objc private func onEncodingSelected() {
        guard let title = encodingButton.titleOfSelectedItem,
              let enc = DocumentEncoding.allSupported.first(where: { $0.name == title }) else { return }
        delegate?.statusBarDidChangeEncoding(enc)
    }
}
