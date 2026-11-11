import AppKit
import Foundation

/// Editor colour scheme. `system` follows the current macOS appearance.
enum EditorTheme: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "Follow System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

final class EditorSettings {
    static let shared = EditorSettings()

    private let defaults = UserDefaults.standard

    var theme: EditorTheme {
        get {
            guard let raw = defaults.string(forKey: "editor.theme"),
                  let theme = EditorTheme(rawValue: raw) else {
                return .system
            }
            return theme
        }
        set { defaults.set(newValue.rawValue, forKey: "editor.theme") }
    }

    /// Resolves the selected theme against the current system appearance.
    var isDarkAppearance: Bool {
        switch theme {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            let match = NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
        }
    }

    var fontName: String {
        get { defaults.string(forKey: "editor.fontName") ?? "Menlo" }
        set { defaults.set(newValue, forKey: "editor.fontName") }
    }

    var fontSize: CGFloat {
        get {
            let val = defaults.double(forKey: "editor.fontSize")
            return val > 0 ? CGFloat(val) : 13.0
        }
        set { defaults.set(Double(newValue), forKey: "editor.fontSize") }
    }

    var tabWidth: Int {
        get {
            let val = defaults.integer(forKey: "editor.tabWidth")
            return val > 0 ? val : 4
        }
        set { defaults.set(newValue, forKey: "editor.tabWidth") }
    }

    var useTabs: Bool {
        get { defaults.bool(forKey: "editor.useTabs") }
        set { defaults.set(newValue, forKey: "editor.useTabs") }
    }

    var wordWrap: Bool {
        get { defaults.bool(forKey: "editor.wordWrap") }
        set { defaults.set(newValue, forKey: "editor.wordWrap") }
    }

    var showWhitespace: Bool {
        get { defaults.bool(forKey: "editor.showWhitespace") }
        set { defaults.set(newValue, forKey: "editor.showWhitespace") }
    }

    var showIndentGuides: Bool {
        get { defaults.bool(forKey: "editor.showIndentGuides") }
        set { defaults.set(newValue, forKey: "editor.showIndentGuides") }
    }

    var autoIndent: Bool {
        get {
            if defaults.object(forKey: "editor.autoIndent") == nil { return true }
            return defaults.bool(forKey: "editor.autoIndent")
        }
        set { defaults.set(newValue, forKey: "editor.autoIndent") }
    }

    func apply(to bridge: EditorBridge) {
        bridge.applyThemeDark(isDarkAppearance)
        bridge.setEditorFont(fontName, size: fontSize)
        bridge.setTabWidth(tabWidth)
        bridge.setUseTabs(useTabs)
        bridge.setWordWrap(wordWrap)
        bridge.setShowWhitespace(showWhitespace)
        bridge.setShowIndentGuides(showIndentGuides)
    }
}
