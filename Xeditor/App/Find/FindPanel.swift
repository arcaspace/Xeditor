import AppKit

/// Utility panel for Find/Replace. Escape closes it like notepad--'s dialog.
final class FindPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Small builders shared by the find panes. The layout follows macOS
/// conventions: full-width fields, a single row of options, and a footer with
/// standard push buttons.
enum FindUI {
    static let labelWidth: CGFloat = 96
    static let defaultButtonKey = "\r"

    static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Right-aligned label in front of a card field ("Find:", "Replace with:").
    static func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 84).isActive = true
        return label
    }

    static func field(_ placeholder: String = "") -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        return field
    }

    static func button(_ title: String,
                       target: AnyObject?,
                       action: Selector?,
                       keyEquivalent: String = "") -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = keyEquivalent
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    /// Footer push button; the one carrying Return becomes the default button.
    static func footerButton(_ title: String,
                             target: AnyObject?,
                             action: Selector,
                             isDefault: Bool = false,
                             toolTip: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        if isDefault { button.keyEquivalent = defaultButtonKey }
        if let toolTip {
            button.toolTip = toolTip
            button.setAccessibilityLabel(toolTip)
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    /// Small secondary caption used in the footer ("Find All in").
    static func inlineLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// Settings section heading (12pt semibold).
    static func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    /// 1pt hairline separator.
    static func rule() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Pull-down menu button (e.g. "All Find ▾"). The first menu item is the
    /// title shown on the button, as AppKit expects for pull-down buttons.
    static func pullDown(_ title: String,
                         target: AnyObject,
                         items: [(title: String, action: Selector)]) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.addItem(withTitle: title)
        popup.menu?.addItem(.separator())
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "")
            menuItem.target = target
            popup.menu?.addItem(menuItem)
        }
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 12)
        popup.setContentHuggingPriority(.required, for: .horizontal)
        return popup
    }

    static func checkbox(_ title: String,
                         target: AnyObject?,
                         action: Selector?,
                         on: Bool) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: target, action: action)
        box.state = on ? .on : .off
        box.font = .systemFont(ofSize: 12)
        return box
    }

    static func radio(_ title: String,
                      target: AnyObject?,
                      action: Selector?,
                      on: Bool) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: target, action: action)
        button.state = on ? .on : .off
        button.font = .systemFont(ofSize: 12)
        return button
    }

    static func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        return stack
    }

    static func vertical(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .leading
        return stack
    }

    /// Vertical stack whose children all stretch to the stack width.
    static func verticalFill(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .width
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// A label/control row whose label column has a fixed width so all fields
    /// line up.
    static func row(_ label: String,
                    _ control: NSView,
                    labelWidth: CGFloat = FindUI.labelWidth) -> NSStackView {
        let title = FindUI.label(label)
        title.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        let stack = horizontal([title, control])
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    /// Horizontal spacer for footers.
    static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
