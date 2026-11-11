import AppKit

protocol GoToLineDelegate: AnyObject {
    func goToLineDidSelect(line: Int)
}

final class GoToLineWindowController: NSWindowController {
    weak var delegate: GoToLineDelegate?
    private let maxLine: Int
    private let currentLine: Int

    private let inputField = NSTextField()
    private let infoLabel = NSTextField(labelWithString: "")
    private let goButton = NSButton()
    private let cancelButton = NSButton()

    init(maxLine: Int, currentLine: Int, delegate: GoToLineDelegate?) {
        self.maxLine = max(1, maxLine)
        self.currentLine = currentLine
        self.delegate = delegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Go to Line"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Go to Line")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 20, y: 92, width: 220, height: 20)
        contentView.addSubview(titleLabel)

        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.stringValue = "\(currentLine)"
        inputField.frame = NSRect(x: 20, y: 60, width: 100, height: 22)
        inputField.target = self
        inputField.action = #selector(onGo)
        contentView.addSubview(inputField)

        infoLabel.font = NSFont.systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.stringValue = "of \(maxLine)"
        infoLabel.frame = NSRect(x: 126, y: 60, width: 110, height: 20)
        contentView.addSubview(infoLabel)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.target = self
        cancelButton.action = #selector(onCancel)
        cancelButton.frame = NSRect(x: 80, y: 14, width: 80, height: 28)
        contentView.addSubview(cancelButton)

        goButton.title = "Go"
        goButton.bezelStyle = .rounded
        goButton.keyEquivalent = "\r" // Enter
        goButton.target = self
        goButton.action = #selector(onGo)
        goButton.frame = NSRect(x: 164, y: 14, width: 76, height: 28)
        contentView.addSubview(goButton)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(inputField)
        inputField.selectText(nil)
    }

    @objc private func onGo() {
        if let line = Int(inputField.stringValue), line >= 1, line <= maxLine {
            delegate?.goToLineDidSelect(line: line)
            close()
        } else {
            NSSound.beep()
        }
    }

    @objc private func onCancel() {
        close()
    }
}
