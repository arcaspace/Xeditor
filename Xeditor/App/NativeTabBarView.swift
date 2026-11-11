import AppKit

protocol NativeTabBarDelegate: AnyObject {
    func tabBarDidSelect(document: EditorDocument)
    func tabBarDidClose(document: EditorDocument)
    func tabBarDidCloseOthers(document: EditorDocument)
    func tabBarDidClickNewTab()
}

// MARK: - Single Tab View

final class NativeTabItemView: NSView {
    let document: EditorDocument
    weak var delegate: NativeTabBarDelegate?

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private var isHovered: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let dirtyIndicator = NSView()
    private let separatorView = NSView()
    private var trackingAreaRef: NSTrackingArea?

    /// Vertical "|" divider drawn at the trailing edge, like Terminal's tab bar.
    var showsSeparator: Bool = false {
        didSet { separatorView.isHidden = !showsSeparator }
    }

    init(document: EditorDocument, delegate: NativeTabBarDelegate?) {
        self.document = document
        self.delegate = delegate
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 32))

        wantsLayer = true

        setupViews()
        updateContent()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 140, height: 32)
    }

    private func setupViews() {
        // Close button (Left)
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab") {
            let conf = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            closeButton.image = img.withSymbolConfiguration(conf)
        }
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(didClickClose)
        closeButton.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        addSubview(closeButton)

        // Dirty indicator dot (Left, under/replace close button)
        dirtyIndicator.wantsLayer = true
        dirtyIndicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dirtyIndicator.layer?.cornerRadius = 3.5
        dirtyIndicator.frame = NSRect(x: 10, y: 10, width: 7, height: 7)
        addSubview(dirtyIndicator)

        // Title Label
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .left
        titleLabel.isSelectable = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.frame = NSRect(x: 26, y: 5, width: bounds.width - 34, height: 18)
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        // Thin divider between tabs (hidden on the last tab).
        separatorView.wantsLayer = true
        separatorView.isHidden = true
        addSubview(separatorView)
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16)
        dirtyIndicator.frame = NSRect(x: 10, y: (bounds.height - 7) / 2, width: 7, height: 7)
        titleLabel.frame = NSRect(x: 26, y: (bounds.height - 18) / 2, width: max(10, bounds.width - 32), height: 18)
        separatorView.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
    }

    func updateContent() {
        titleLabel.stringValue = document.displayName
        toolTip = document.displayName
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Title font weight
        titleLabel.font = isSelected ? NSFont.systemFont(ofSize: 12, weight: .medium)
                                     : NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor

        // Flat tab backgrounds, Terminal style: selected is lighter than the bar,
        // hovered tabs get a subtle lift.
        if isSelected {
            layer?.backgroundColor = (isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.85)).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.06 : 0.04).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Full-height hairline divider, low contrast so it reads as a tab boundary
        // rather than a floating black dash.
        separatorView.layer?.backgroundColor =
            NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.08).cgColor

        // Close button appears only while hovering; otherwise show the dirty dot.
        closeButton.isHidden = !isHovered
        dirtyIndicator.isHidden = isHovered || !document.isDirty
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingAreaRef {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(point) && !closeButton.isHidden {
            didClickClose()
        } else {
            delegate?.tabBarDidSelect(document: document)
        }
    }

    @objc private func didClickClose() {
        delegate?.tabBarDidClose(document: document)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Tab")
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(menuClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        let closeOthersItem = NSMenuItem(title: "Close Other Tabs", action: #selector(menuCloseOthers), keyEquivalent: "")
        closeOthersItem.target = self
        menu.addItem(closeOthersItem)
        return menu
    }

    @objc private func menuClose() {
        delegate?.tabBarDidClose(document: document)
    }

    @objc private func menuCloseOthers() {
        delegate?.tabBarDidCloseOthers(document: document)
    }
}

// MARK: - Tab Bar Container View

final class NativeTabBarView: NSView {
    weak var delegate: NativeTabBarDelegate?

    private let stackView = NSStackView()
    private let newTabButton = NSButton()
    private let bottomBorder = NSView()

    private var tabViews: [NativeTabItemView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Stack view for tab items
        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        addSubview(stackView)

        // Plus button (New Tab)
        newTabButton.bezelStyle = .regularSquare
        newTabButton.isBordered = false
        newTabButton.imagePosition = .imageOnly
        if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab") {
            let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            newTabButton.image = img.withSymbolConfiguration(conf)
        }
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.target = self
        newTabButton.action = #selector(didClickNewTab)
        newTabButton.toolTip = "New Tab (⌘N)"
        addSubview(newTabButton)

        // Bottom border line
        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(bottomBorder)
    }

    override func layout() {
        super.layout()
        let btnWidth: CGFloat = 28
        let h = bounds.height

        newTabButton.frame = NSRect(x: bounds.width - btnWidth - 4, y: (h - 24) / 2, width: btnWidth, height: 24)
        stackView.frame = NSRect(x: 0, y: 0, width: bounds.width - btnWidth - 10, height: h)
        bottomBorder.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    func reloadTabs(store: DocumentStore) {
        // Clear old tab views
        for tab in tabViews {
            stackView.removeArrangedSubview(tab)
            tab.removeFromSuperview()
        }
        tabViews.removeAll()

        // Build new tab views
        for (index, doc) in store.documents.enumerated() {
            let tab = NativeTabItemView(document: doc, delegate: delegate)
            tab.isSelected = (doc.id == store.activeID)
            tab.showsSeparator = index < store.documents.count - 1
            tabViews.append(tab)
            stackView.addArrangedSubview(tab)
        }

        // Layout stack
        stackView.layoutSubtreeIfNeeded()
    }

    func updateActiveTab(activeID: EditorDocument.ID?) {
        for tab in tabViews {
            tab.isSelected = (tab.document.id == activeID)
        }
    }

    func updateDocument(id: EditorDocument.ID) {
        if let tab = tabViews.first(where: { $0.document.id == id }) {
            tab.updateContent()
        }
    }

    @objc private func didClickNewTab() {
        delegate?.tabBarDidClickNewTab()
    }
}
