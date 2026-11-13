import AppKit

protocol PreferencesDelegate: AnyObject {
    func preferencesDidChange()
}

final class PreferencesWindowController: NSWindowController {
    weak var delegate: PreferencesDelegate?

    private let languagePopUp = NSPopUpButton()
    private let themePopUp = NSPopUpButton()
    private let fontPopUp = NSPopUpButton()
    private let fontSizeSlider = NSSlider()
    private let fontSizeLabel = NSTextField(labelWithString: "13 pt")
    private let tabWidthStepper = NSStepper()
    private let tabWidthLabel = NSTextField(labelWithString: "4")
    private let useTabsCheckbox = NSButton()
    private let wordWrapCheckbox = NSButton()
    private let showWhitespaceCheckbox = NSButton()
    private let showIndentGuidesCheckbox = NSButton()
    private let autoIndentCheckbox = NSButton()

    init(delegate: PreferencesDelegate?) {
        self.delegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Preferences")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        var y: CGFloat = 410

        // ── Language Section ──
        let languageTitle = sectionLabel(L("Language"))
        languageTitle.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        contentView.addSubview(languageTitle)
        y -= 30

        // The popup always lists languages in their own script so they can be
        // found regardless of the current UI language.
        languagePopUp.removeAllItems()
        languagePopUp.addItems(withTitles: AppLanguage.allCases.map(\.nativeName))
        languagePopUp.target = self
        languagePopUp.action = #selector(onLanguageChanged)
        languagePopUp.frame = NSRect(x: 20, y: y, width: 220, height: 24)
        contentView.addSubview(languagePopUp)
        y -= 40

        // ── Theme Section ──
        let themeTitle = sectionLabel(L("Theme"))
        themeTitle.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        contentView.addSubview(themeTitle)
        y -= 30

        themePopUp.removeAllItems()
        themePopUp.addItems(withTitles: EditorTheme.allCases.map(\.title))
        themePopUp.target = self
        themePopUp.action = #selector(onSettingChanged)
        themePopUp.frame = NSRect(x: 20, y: y, width: 220, height: 24)
        contentView.addSubview(themePopUp)
        y -= 40

        // ── Font Section ──
        let fontTitle = sectionLabel(L("Editor Font"))
        fontTitle.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        contentView.addSubview(fontTitle)
        y -= 30

        let fontFamilies = availableMonospacedFonts()
        fontPopUp.removeAllItems()
        fontPopUp.addItems(withTitles: fontFamilies)
        fontPopUp.target = self
        fontPopUp.action = #selector(onSettingChanged)
        fontPopUp.frame = NSRect(x: 20, y: y, width: 220, height: 24)
        contentView.addSubview(fontPopUp)

        fontSizeSlider.minValue = 8
        fontSizeSlider.maxValue = 32
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(onFontSizeSliderChanged)
        fontSizeSlider.frame = NSRect(x: 250, y: y + 2, width: 80, height: 20)
        contentView.addSubview(fontSizeSlider)

        fontSizeLabel.frame = NSRect(x: 334, y: y + 2, width: 40, height: 18)
        contentView.addSubview(fontSizeLabel)
        y -= 40

        // ── Tabs & Indent Section ──
        let indentTitle = sectionLabel(L("Tabs & Indentation"))
        indentTitle.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        contentView.addSubview(indentTitle)
        y -= 28

        let tabWidthText = NSTextField(labelWithString: L("Tab Width:"))
        tabWidthText.frame = NSRect(x: 20, y: y, width: 80, height: 18)
        contentView.addSubview(tabWidthText)

        tabWidthLabel.frame = NSRect(x: 105, y: y, width: 24, height: 18)
        contentView.addSubview(tabWidthLabel)

        tabWidthStepper.minValue = 1
        tabWidthStepper.maxValue = 16
        tabWidthStepper.target = self
        tabWidthStepper.action = #selector(onTabWidthChanged)
        tabWidthStepper.frame = NSRect(x: 130, y: y, width: 16, height: 20)
        contentView.addSubview(tabWidthStepper)
        y -= 28

        configureCheckbox(useTabsCheckbox, title: L("Use tabs instead of spaces"), y: y)
        y -= 24
        configureCheckbox(autoIndentCheckbox, title: L("Auto-indent new lines"), y: y)
        y -= 40

        // ── Display Section ──
        let displayTitle = sectionLabel(L("Display"))
        displayTitle.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        contentView.addSubview(displayTitle)
        y -= 28

        configureCheckbox(wordWrapCheckbox, title: L("Word wrap"), y: y)
        y -= 24
        configureCheckbox(showWhitespaceCheckbox, title: L("Show whitespace characters"), y: y)
        y -= 24
        configureCheckbox(showIndentGuidesCheckbox, title: L("Show indentation guide lines"), y: y)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configureCheckbox(_ button: NSButton, title: String, y: CGFloat) {
        button.setButtonType(.switch)
        button.title = title
        button.font = NSFont.systemFont(ofSize: 12)
        button.target = self
        button.action = #selector(onSettingChanged)
        button.frame = NSRect(x: 20, y: y, width: 340, height: 18)
        window?.contentView?.addSubview(button)
    }

    private func availableMonospacedFonts() -> [String] {
        let fm = NSFontManager.shared
        var fonts: [String] = []
        for family in fm.availableFontFamilies {
            if family.localizedCaseInsensitiveContains("mono") ||
               family.localizedCaseInsensitiveContains("courier") ||
               family.localizedCaseInsensitiveContains("menlo") ||
               family.localizedCaseInsensitiveContains("consol") {
                fonts.append(family)
            }
        }
        // Only offer faces that CoreText can actually resolve; unavailable names
        // fall back to Helvetica and break bold/italic styles.
        if NSFont(name: "SF Mono", size: 13) != nil && !fonts.contains("SF Mono") {
            fonts.insert("SF Mono", at: 0)
        }
        return fonts.sorted()
    }

    private func loadSettings() {
        let settings = EditorSettings.shared
        if let index = AppLanguage.allCases.firstIndex(of: Localization.shared.language) {
            languagePopUp.selectItem(at: index)
        }
        themePopUp.selectItem(withTitle: settings.theme.title)
        if fontPopUp.indexOfItem(withTitle: settings.fontName) >= 0 {
            fontPopUp.selectItem(withTitle: settings.fontName)
        } else if fontPopUp.indexOfItem(withTitle: "Menlo") >= 0 {
            // A previously stored face may no longer be installed (for example
            // the old "SF Mono" default, which CoreText resolves to Helvetica).
            fontPopUp.selectItem(withTitle: "Menlo")
        }
        fontSizeSlider.doubleValue = Double(settings.fontSize)
        fontSizeLabel.stringValue = "\(Int(settings.fontSize)) pt"

        tabWidthStepper.integerValue = settings.tabWidth
        tabWidthLabel.stringValue = "\(settings.tabWidth)"

        useTabsCheckbox.state = settings.useTabs ? .on : .off
        autoIndentCheckbox.state = settings.autoIndent ? .on : .off
        wordWrapCheckbox.state = settings.wordWrap ? .on : .off
        showWhitespaceCheckbox.state = settings.showWhitespace ? .on : .off
        showIndentGuidesCheckbox.state = settings.showIndentGuides ? .on : .off
    }

    /// Rebuilds every label after a language switch. The window is small and
    /// laid out with fixed frames, so recreating the content is simpler and
    /// safer than tracking each label individually.
    func applyLocalization() {
        window?.title = L("Preferences")
        for subview in window?.contentView?.subviews ?? [] {
            subview.removeFromSuperview()
        }
        setupUI()
        loadSettings()
    }

    @objc private func onLanguageChanged() {
        let index = languagePopUp.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else { return }
        Localization.shared.language = AppLanguage.allCases[index]
        applyLocalization()
        delegate?.preferencesDidChange()
    }

    @objc private func onFontSizeSliderChanged() {
        let sz = CGFloat(fontSizeSlider.integerValue)
        fontSizeLabel.stringValue = "\(Int(sz)) pt"
        EditorSettings.shared.fontSize = sz
        delegate?.preferencesDidChange()
    }

    @objc private func onTabWidthChanged() {
        let w = tabWidthStepper.integerValue
        tabWidthLabel.stringValue = "\(w)"
        EditorSettings.shared.tabWidth = w
        delegate?.preferencesDidChange()
    }

    @objc private func onSettingChanged() {
        let settings = EditorSettings.shared
        if let title = themePopUp.titleOfSelectedItem,
           let theme = EditorTheme.allCases.first(where: { $0.title == title }) {
            settings.theme = theme
        }
        if let font = fontPopUp.titleOfSelectedItem {
            settings.fontName = font
        }
        settings.useTabs = (useTabsCheckbox.state == .on)
        settings.autoIndent = (autoIndentCheckbox.state == .on)
        settings.wordWrap = (wordWrapCheckbox.state == .on)
        settings.showWhitespace = (showWhitespaceCheckbox.state == .on)
        settings.showIndentGuides = (showIndentGuidesCheckbox.state == .on)

        delegate?.preferencesDidChange()
    }

    override func showWindow(_ sender: Any?) {
        loadSettings()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }
}
