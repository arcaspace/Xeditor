import AppKit

/// Read-only text view used by the compare tool. It paints the background of
/// every row by diff kind, so changed lines read as solid bands across the whole
/// pane instead of only behind the glyphs.
final class DiffTextView: NSTextView {
    enum Side {
        case left
        case right
    }

    private enum RowBackground {
        case none
        case removed
        case added
        case blankRemoved
        case blankAdded
    }

    private var rowBackgrounds: [RowBackground] = []
    private var lineStarts: [Int] = []
    /// Row bands precomputed outside drawing. Querying the layout manager from
    /// inside `drawBackground` suppressed glyph drawing entirely, so the
    /// geometry is resolved once after the text is set (line wrapping is off,
    /// so the rows never move; only their width changes with the view).
    private var bandRects: [(rect: NSRect, background: RowBackground)] = []

    func show(rows: [DiffRow], side: Side) {
        rowBackgrounds = rows.map { background(for: $0, side: side) }
        let (text, starts) = Self.attributedText(rows: rows, side: side)
        lineStarts = starts
        textStorage?.setAttributedString(text)
        setSelectedRange(NSRange(location: 0, length: 0))
        rebuildBands()
        needsDisplay = true
    }

    func characterIndex(forRow row: Int) -> Int {
        guard row >= 0, row < lineStarts.count else { return 0 }
        return lineStarts[row]
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !bandRects.isEmpty else { return }
        let fullWidth = max(bounds.width, visibleRect.maxX)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for band in bandRects where band.rect.intersects(rect) {
                guard let color = fillColor(band.background) else { continue }
                var fill = band.rect
                fill.origin.x = 0
                fill.size.width = fullWidth
                color.setFill()
                fill.fill()
            }
        }
    }

    private func rebuildBands() {
        bandRects.removeAll()
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return }

        let origin = textContainerOrigin
        var bands: [(rect: NSRect, background: RowBackground)] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: glyphCount)
        ) { fragmentRect, _, _, fragmentGlyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            guard let row = self.rowIndex(forCharacter: characterIndex),
                  row < self.rowBackgrounds.count else { return }
            let background = self.rowBackgrounds[row]
            guard background != .none else { return }
            bands.append((fragmentRect.offsetBy(dx: 0, dy: origin.y), background))
        }
        bandRects = bands
    }

    // MARK: - Rows

    private func rowIndex(forCharacter index: Int) -> Int? {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= index {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return high >= 0 && high < rowBackgrounds.count ? high : nil
    }

    private static func attributedText(rows: [DiffRow], side: Side) -> (NSAttributedString, [Int]) {
        let result = NSMutableAttributedString()
        var starts: [Int] = []
        starts.reserveCapacity(rows.count)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        for (index, row) in rows.enumerated() {
            starts.append(result.length)
            let number = side == .left ? row.leftNumber : row.rightNumber
            let text = side == .left ? row.leftText : row.rightText
            let prefix = number.map { String(format: "%6d  ", $0) }
                ?? String(repeating: " ", count: 8)

            result.append(NSAttributedString(string: prefix, attributes: [
                .font: ToolUI.numberFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraph,
            ]))
            result.append(NSAttributedString(string: text ?? "", attributes: [
                .font: ToolUI.codeFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraph,
            ]))
            if index < rows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: ToolUI.codeFont,
                    .paragraphStyle: paragraph,
                ]))
            }
        }
        return (result, starts)
    }

    private func background(for row: DiffRow, side: Side) -> RowBackground {
        switch row.kind {
        case .same:
            return .none
        case .changed:
            return side == .left ? .removed : .added
        case .deleted:
            return side == .left ? .removed : .blankRemoved
        case .added:
            return side == .left ? .blankAdded : .added
        }
    }

    private func fillColor(_ background: RowBackground) -> NSColor? {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch background {
        case .none:
            return nil
        case .removed:
            return dark
                ? NSColor(srgbRed: 0.36, green: 0.13, blue: 0.15, alpha: 1)
                : NSColor(srgbRed: 1.00, green: 0.88, blue: 0.88, alpha: 1)
        case .added:
            return dark
                ? NSColor(srgbRed: 0.10, green: 0.25, blue: 0.14, alpha: 1)
                : NSColor(srgbRed: 0.86, green: 0.97, blue: 0.86, alpha: 1)
        case .blankRemoved:
            return dark
                ? NSColor(srgbRed: 0.22, green: 0.12, blue: 0.13, alpha: 1)
                : NSColor(srgbRed: 1.00, green: 0.95, blue: 0.95, alpha: 1)
        case .blankAdded:
            return dark
                ? NSColor(srgbRed: 0.10, green: 0.18, blue: 0.12, alpha: 1)
                : NSColor(srgbRed: 0.95, green: 0.99, blue: 0.95, alpha: 1)
        }
    }
}
