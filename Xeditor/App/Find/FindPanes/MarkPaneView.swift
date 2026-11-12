import AppKit

/// Compact colour chip; clicking one becomes the active mark colour.
private final class MarkColorChipView: NSView {
    var color: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    var onSelect: (() -> Void)?

    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 20) }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                    xRadius: 4, yRadius: 4)
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }

        let swatch = NSBezierPath(roundedRect: bounds.insetBy(dx: 3.5, dy: 3.5),
                                  xRadius: 3, yRadius: 3)
        color.setFill()
        swatch.fill()
        NSColor.separatorColor.setStroke()
        swatch.lineWidth = 1
        swatch.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Mark tab: colour the matches with one of five indicators, optionally adding
/// a bookmark per matched line.
final class MarkPaneView: FindPaneBase {
    private var chips: [MarkColorChipView] = []

    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: false, optionsVariant: .mark)

        var chipViews: [NSView] = []
        let selected = FindSettings.shared.markColorIndex
        for index in 0..<5 {
            let chip = MarkColorChipView()
            chip.isSelected = index == selected
            chip.toolTip = "Color \(index + 1)"
            chip.setAccessibilityLabel("Mark color \(index + 1)")
            chip.setAccessibilityRole(.button)
            chip.onSelect = { [weak self] in self?.selectColor(index) }
            chip.widthAnchor.constraint(equalToConstant: 30).isActive = true
            chip.heightAnchor.constraint(equalToConstant: 20).isActive = true
            chips.append(chip)
            chipViews.append(chip)
        }
        let colors = FindUI.horizontal([FindUI.sectionLabel("Color")] + chipViews + [FindUI.spacer()],
                                       spacing: 8)

        let copyMatches = FindUI.footerButton("Copy Matches", target: self, action: #selector(copyMatches))
        let clearThisColor = FindUI.footerButton("Clear This Color", target: self,
                                                  action: #selector(clearThisColor))
        let clearAllMarks = FindUI.footerButton("Clear All Marks", target: self,
                                                action: #selector(clearAllMarks))

        let markBookmarks = FindUI.footerButton("Mark + Bookmark", target: self,
                                                action: #selector(markWithBookmarks))
        let markAll = FindUI.footerButton("Mark All", target: self, action: #selector(markAll),
                                          isDefault: true)

        setFooter(leading: [copyMatches, clearThisColor, clearAllMarks],
                  trailing: [markBookmarks, markAll])

        installCard(extraRows: [colors])
        updateSwatches()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSwatches()
    }

    /// Return marks all matches, matching the default button.
    override func performPrimary(backward: Bool) {
        markAll()
    }

    private func updateSwatches() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for index in 0..<5 {
            chips[index].color = EditorBridge.markColor(index: index, dark: dark)
        }
    }

    private func selectColor(_ index: Int) {
        FindSettings.shared.markColorIndex = index
        for (chipIndex, chip) in chips.enumerated() {
            chip.isSelected = chipIndex == index
        }
    }

    @objc private func markAll() {
        controller?.performMarkAll(colorIndex: FindSettings.shared.markColorIndex, addBookmarks: false)
    }

    @objc private func markWithBookmarks() {
        controller?.performMarkAll(colorIndex: FindSettings.shared.markColorIndex, addBookmarks: true)
    }

    @objc private func clearThisColor() {
        controller?.clearMarks(all: false, colorIndex: FindSettings.shared.markColorIndex)
    }

    @objc private func clearAllMarks() {
        controller?.clearMarks(all: true, colorIndex: FindSettings.shared.markColorIndex)
    }

    @objc private func copyMatches() { controller?.copyMatchedText() }
}
