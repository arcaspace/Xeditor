import AppKit

/// Horizontal tab strip drawn like notepad--'s dialog tabs: flush at the top
/// of the window, the active tab underlined in orange.
final class FindTabStrip: NSView {
    private var tabRects: [NSRect] = []

    var titles: [String] = [] {
        didSet { tabRects = []; needsDisplay = true }
    }

    var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            needsDisplay = true
        }
    }

    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        recomputeRects()
    }

    override func draw(_ dirtyRect: NSRect) {
        recomputeRects()

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // Bottom hairline separating the strip from the pane content.
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let font = NSFont.systemFont(ofSize: 13)
        for (index, title) in titles.enumerated() {
            let rect = tabRects[index]
            if index == selectedIndex {
                NSColor.controlBackgroundColor.setFill()
                rect.fill()
                NSColor.systemOrange.setFill()
                NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2).fill()
            }
            if index > 0 {
                NSColor.separatorColor.withAlphaComponent(0.45).setFill()
                NSRect(x: rect.minX, y: 6, width: 1, height: rect.height - 12).fill()
            }

            let color: NSColor = index == selectedIndex ? .labelColor : .secondaryLabelColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let textHeight = font.ascender - font.descender
            let textRect = NSRect(x: rect.minX,
                                  y: rect.midY - textHeight / 2,
                                  width: rect.width,
                                  height: textHeight + 2)
            (title as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }

    private func recomputeRects() {
        guard tabRects.count != titles.count || tabRects.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 13)
        var rects: [NSRect] = []
        var x: CGFloat = 0
        for title in titles {
            let width = max(88, (title as NSString).size(withAttributes: [.font: font]).width + 40)
            rects.append(NSRect(x: x, y: 0, width: width, height: bounds.height))
            x += width
        }
        tabRects = rects
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in tabRects.enumerated() where rect.contains(point) {
            if index != selectedIndex {
                selectedIndex = index
                onSelect?(index)
            }
            return
        }
        super.mouseDown(with: event)
    }
}
