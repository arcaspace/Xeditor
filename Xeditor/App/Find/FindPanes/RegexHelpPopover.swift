import AppKit

/// Regular-expression cheat sheet shown by the "?" button in the options row.
/// A two-column reference: characters and anchors on the left, quantifiers,
/// groups and back-references on the right.
@MainActor
final class RegexHelpPopover: NSPopover {
    static func make() -> RegexHelpPopover {
        let popover = RegexHelpPopover()
        let controller = NSViewController()
        let content = RegexHelpView()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        content.layoutSubtreeIfNeeded()
        popover.contentSize = content.fittingSize
        return popover
    }
}

@MainActor
private final class RegexHelpView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let title = NSTextField(labelWithString: L("Basic Regular Expression Syntax"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let characters = Self.section(L("Characters"), [
            (".", L("Any character")),
            ("\\R", L("Line break")),
            ("\\n", L("Line feed")),
            ("\\r", L("Carriage return")),
            ("\\t", L("Tab character")),
            ("\\w", L("Word character")),
            ("\\s", L("Whitespace")),
            ("\\S", L("Non-whitespace")),
            ("\\d", L("Digit")),
            ("[A-Z]", L("Any character from A to Z")),
            ("[^A-Z]", L("Any character not from A to Z"))
        ], tokenWidth: 56)

        let anchors = Self.section(L("Anchors"), [
            ("^", L("Start of line")),
            ("$", L("End of line")),
            ("\\b", L("Word boundary"))
        ], tokenWidth: 56)

        let quantities = Self.section(L("Quantities"), [
            ("?", L("One time or none")),
            ("*", L("Zero or more")),
            ("+", L("One or more")),
            ("{n,m}", L("At least n, at most m")),
            ("{n,}", L("At least n")),
            ("{,n}", L("None up to n")),
            ("{n}", L("Exactly n times"))
        ], tokenWidth: 86)

        let groups = Self.section(L("Extended groups"), [
            ("(?=subexp)", L("Lookahead")),
            ("(?<=subexp)", L("Lookbehind"))
        ], tokenWidth: 86)

        let backRefs = Self.section(L("Back references"), [
            ("$1", L("First matched group"))
        ], tokenWidth: 86)

        let left = NSStackView(views: [characters, anchors])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 16

        let right = NSStackView(views: [quantities, groups, backRefs])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 16

        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 44

        let footerText = NSMutableAttributedString(
            string: L("Syntax follows the "),
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor])
        footerText.append(NSAttributedString(
            string: L("ICU regular expression syntax."),
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.controlAccentColor,
                         .link: URL(string: "https://unicode-org.github.io/icu/userguide/strings/regexp.html")!]))
        let footer = NSTextField(labelWithAttributedString: footerText)
        footer.isSelectable = true

        let footerRow = NSStackView(views: [NSView(), footer])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 5

        let root = NSStackView(views: [title, columns, footerRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setCustomSpacing(18, after: title)
        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor),
            footerRow.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    /// One titled group of "token — description" rows.
    private static func section(_ title: String,
                                _ rows: [(String, String)],
                                tokenWidth: CGFloat) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let gridRows: [[NSView]] = rows.map { token, description in
            let tokenLabel = NSTextField(labelWithString: token)
            tokenLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tokenLabel.textColor = .secondaryLabelColor
            tokenLabel.widthAnchor.constraint(equalToConstant: tokenWidth).isActive = true

            let descriptionLabel = NSTextField(labelWithString: description)
            descriptionLabel.font = .systemFont(ofSize: 12)
            descriptionLabel.textColor = .labelColor
            return [tokenLabel, descriptionLabel]
        }
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 5
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading

        let stack = NSStackView(views: [titleLabel, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }
}
