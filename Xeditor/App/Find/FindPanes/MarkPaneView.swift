import AppKit

/// Mark tab: colour the matches with one of five indicators, optionally adding
/// a bookmark per matched line.
final class MarkPaneView: FindPaneBase {
    private var colorRadios: [NSButton] = []
    private var swatches: [NSImageView] = []

    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: false, optionsVariant: .mark)

        var colorRows: [NSView] = []
        let selected = FindSettings.shared.markColorIndex
        for index in 0..<5 {
            let radio = FindUI.radio("Color \(index + 1)", target: self,
                                     action: #selector(colorChanged(_:)),
                                     on: index == selected)
            radio.tag = index
            colorRadios.append(radio)

            let swatch = NSImageView()
            swatch.imageScaling = .scaleProportionallyUpOrDown
            swatch.widthAnchor.constraint(equalToConstant: 26).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatches.append(swatch)

            colorRows.append(FindUI.horizontal([radio, swatch], spacing: 8))
        }
        let colors = FindUI.vertical(colorRows, spacing: 12)

        let markAll = FindUI.actionButton("Mark All", target: self, action: #selector(markAll))
        markAll.keyEquivalent = "\r"
        let markBookmarks = FindUI.actionButton("Mark + Bookmark", target: self, action: #selector(markWithBookmarks))
        let gap = NSView()
        gap.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let clearOne = FindUI.actionButton("Clear This Color", target: self, action: #selector(clearThisColor))
        let clearAll = FindUI.actionButton("Clear All Marks", target: self, action: #selector(clearAllMarks))
        let copyMatches = FindUI.actionButton("Copy Matched Text", target: self, action: #selector(copyMatches))
        let close = FindUI.actionButton("Close", target: self, action: #selector(closePanel))

        let left = FindUI.vertical([searchRow(), colors, flexibleSpacer(), optionsView], spacing: 18)

        install(left: left,
                rightViews: [markAll, markBookmarks, gap, clearOne, clearAll,
                             copyMatches, close])
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
            swatches[index].image = swatchImage(color: EditorBridge.markColor(index: index, dark: dark))
        }
    }

    private func swatchImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 26, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    @objc private func colorChanged(_ sender: NSButton) {
        FindSettings.shared.markColorIndex = sender.tag
        for radio in colorRadios {
            radio.state = radio.tag == sender.tag ? .on : .off
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
    @objc private func closePanel() { controller?.closePanel() }
}
