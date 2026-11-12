import AppKit

/// Shared chrome for the windows in the Tools menu: a normal resizable window
/// that its owner keeps alive, restores its frame from the previous session and
/// comes to the front when the menu item is chosen again.
@MainActor
class ToolWindowController: NSWindowController {
    init(title: String, size: NSSize, minSize: NSSize, autosaveName: String) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.tabbingMode = .disallowed
        window.center()
        _ = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let first = firstResponderView() {
            window?.makeFirstResponder(first)
        }
    }

    /// Subclasses override to focus their primary input when the window opens.
    func firstResponderView() -> NSView? { nil }
}

/// Small view factories shared by the tool windows, so the three tools look and
/// behave the same.
@MainActor
enum ToolUI {
    static var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    static var numberFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    static func label(_ text: String,
                      size: CGFloat = 12,
                      weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .left
        return label
    }

    static func sectionLabel(_ text: String) -> NSTextField {
        label(text, size: 11, weight: .semibold, color: .secondaryLabelColor)
    }

    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        return button
    }

    /// A code-friendly text view: no smart quotes, dashes or spell checking, so
    /// pasted snippets stay byte-for-byte what the user copied.
    static func makeTextView(editable: Bool) -> NSTextView {
        let textView = NSTextView()
        textView.font = codeFont
        textView.isEditable = editable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        return textView
    }

    static func wrap(_ textView: NSTextView, horizontal: Bool = false) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = horizontal
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
}
