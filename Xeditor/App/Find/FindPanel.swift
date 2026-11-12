import AppKit

/// Utility panel for Find/Replace. Escape closes it like notepad--'s dialog.
final class FindPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Small builders shared by the find panes. The layout mirrors notepad--'s
/// dialog: a two-column pane with a wide action-button column on the right.
enum FindUI {
    static let actionButtonHeight: CGFloat = 36
    static let labelWidth: CGFloat = 96

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

    static func combo(history: [String]) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = true
        combo.completes = false
        combo.numberOfVisibleItems = 12
        combo.font = .systemFont(ofSize: 13)
        combo.addItems(withObjectValues: history)
        return combo
    }

    static func field(_ placeholder: String = "") -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        return field
    }

    static func button(_ title: String,
                       target: AnyObject?,
                       action: Selector?,
                       keyEquivalent: String = "") -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = keyEquivalent
        return button
    }

    /// Full-width action button for the right-hand column.
    static func actionButton(_ title: String,
                             target: AnyObject?,
                             action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13)
        button.heightAnchor.constraint(equalToConstant: actionButtonHeight).isActive = true
        return button
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

    /// A label/control row whose label column has a fixed width so all panes
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

    /// Group box with a title, like the "查找模式" box in notepad--.
    static func group(_ title: String, _ views: [NSView], spacing: CGFloat = 8) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 12, weight: .medium)
        box.titlePosition = .atTop
        box.boxType = .primary

        let stack = vertical(views, spacing: spacing)
        box.contentView?.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = box.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
            ])
        }
        return box
    }

    /// Puts content in a two-column layout: flexible left side, fixed-width
    /// action column on the right.
    static func twoColumn(left: NSView, right: NSView, rightWidth: CGFloat = 220) -> NSStackView {
        right.widthAnchor.constraint(equalToConstant: rightWidth).isActive = true
        let stack = horizontal([left, right], spacing: 24)
        stack.alignment = .top
        stack.distribution = .fill
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }
}
