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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Plain NSViews are ignored by the accessibility tree unless told
        // otherwise; the role/label set by MarkPaneView would not surface.
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 22) }

    /// The Find window is often not key when the user reaches for a chip;
    /// without this the first click only activates the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let swatchRect = bounds.insetBy(dx: 3, dy: 2)
        let swatch = NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4)
        color.setFill()
        swatch.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        swatch.lineWidth = 0.5
        swatch.stroke()

        if isSelected {
            // Ring sits outside the swatch with a gap, in the label colour, so
            // it stays visible on every swatch hue (accent blue vanished on blue).
            let ringRect = bounds.insetBy(dx: 0.75, dy: 0.75)
            let ring = NSBezierPath(roundedRect: ringRect, xRadius: 6, yRadius: 6)
            NSColor.labelColor.setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
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
            chip.toolTip = LF("Color %d", index + 1)
            chip.setAccessibilityLabel(LF("Color %d", index + 1))
            chip.setAccessibilityRole(.button)
            chip.onSelect = { [weak self] in self?.selectColor(index) }
            chip.widthAnchor.constraint(equalToConstant: 28).isActive = true
            chip.heightAnchor.constraint(equalToConstant: 22).isActive = true
            chips.append(chip)
            chipViews.append(chip)
        }
        let colorLabel = bindTitle(FindUI.inlineLabel("Color"), "Color")
        let colors = FindUI.horizontal([colorLabel] + chipViews + [FindUI.spacer()],
                                       spacing: 8)

        let copyMatches = bindToolTip(bindTitle(FindUI.footerButton("Copy Matches", target: self,
                                                                    action: #selector(copyMatches)),
                                                "Copy Matches"),
                                      "Copy all matched text to the clipboard")
        let clearThisColor = bindToolTip(bindTitle(FindUI.footerButton("Clear Color", target: self,
                                                                       action: #selector(clearThisColor)),
                                                   "Clear Color"),
                                         "Remove marks of the selected color")
        let clearAllMarks = bindToolTip(bindTitle(FindUI.footerButton("Clear All", target: self,
                                                                      action: #selector(clearAllMarks)),
                                                  "Clear All"),
                                        "Remove all marks")

        let markBookmarks = bindToolTip(bindTitle(FindUI.footerButton("Mark + Bookmark", target: self,
                                                                      action: #selector(markWithBookmarks)),
                                                  "Mark + Bookmark"),
                                        "Mark all matches and add bookmarks on their lines")
        let markAll = bindToolTip(bindTitle(FindUI.footerButton("Mark All", target: self,
                                                                action: #selector(markAll),
                                                                isDefault: true),
                                            "Mark All"),
                                  "Mark all matches")

        setFooter(leading: [copyMatches, clearThisColor, clearAllMarks],
                  trailing: [markBookmarks, markAll])

        installCard(extraRows: [colors])
        updateSwatches()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyLocalization() {
        super.applyLocalization()
        for (index, chip) in chips.enumerated() {
            chip.toolTip = LF("Color %d", index + 1)
            chip.setAccessibilityLabel(LF("Color %d", index + 1))
        }
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
