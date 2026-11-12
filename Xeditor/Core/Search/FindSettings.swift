import AppKit
import Foundation

/// How the search text is interpreted. Mirrors notepad--'s three modes.
enum SearchMode: String, CaseIterable {
    case normal
    case regex
    case extended

    var title: String {
        switch self {
        case .normal:   return "Normal"
        case .regex:    return "Regular Expression"
        case .extended: return "Extended"
        }
    }
}

/// Persisted Find/Replace window state, following the `EditorSettings` pattern.
final class FindSettings {
    static let shared = FindSettings()

    private let defaults = UserDefaults.standard

    private static let historyMaxLength = 100

    var mode: SearchMode {
        get { SearchMode(rawValue: defaults.string(forKey: "find.mode") ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "find.mode") }
    }

    var matchCase: Bool {
        get { defaults.bool(forKey: "find.matchCase") }
        set { defaults.set(newValue, forKey: "find.matchCase") }
    }

    var wholeWord: Bool {
        get { defaults.bool(forKey: "find.wholeWord") }
        set { defaults.set(newValue, forKey: "find.wholeWord") }
    }

    var wrap: Bool {
        get {
            if defaults.object(forKey: "find.wrap") == nil { return true }
            return defaults.bool(forKey: "find.wrap")
        }
        set { defaults.set(newValue, forKey: "find.wrap") }
    }

    var backward: Bool {
        get { defaults.bool(forKey: "find.backward") }
        set { defaults.set(newValue, forKey: "find.backward") }
    }

    var inSelection: Bool {
        get { defaults.bool(forKey: "find.inSelection") }
        set { defaults.set(newValue, forKey: "find.inSelection") }
    }

    var lastQuery: String {
        get { defaults.string(forKey: "find.lastQuery") ?? "" }
        set { defaults.set(newValue, forKey: "find.lastQuery") }
    }

    var lastReplacement: String {
        get { defaults.string(forKey: "find.lastReplacement") ?? "" }
        set { defaults.set(newValue, forKey: "find.lastReplacement") }
    }

    var lastTab: Int {
        get { defaults.integer(forKey: "find.lastTab") }
        set { defaults.set(newValue, forKey: "find.lastTab") }
    }

    var markColorIndex: Int {
        get { defaults.integer(forKey: "find.mark.colorIndex") }
        set { defaults.set(newValue, forKey: "find.mark.colorIndex") }
    }

    var markAddBookmarks: Bool {
        get { defaults.bool(forKey: "find.mark.addBookmarks") }
        set { defaults.set(newValue, forKey: "find.mark.addBookmarks") }
    }

    // MARK: - Window transparency

    var opacityEnabled: Bool {
        get { defaults.bool(forKey: "find.opacityEnabled") }
        set { defaults.set(newValue, forKey: "find.opacityEnabled") }
    }

    /// true = always transparent at `opacity`; false = only while unfocused.
    var opacityAlways: Bool {
        get { defaults.bool(forKey: "find.opacityAlways") }
        set { defaults.set(newValue, forKey: "find.opacityAlways") }
    }

    var opacity: Double {
        get {
            let value = defaults.double(forKey: "find.opacity")
            return value > 0 ? min(1, max(0.25, value)) : 0.85
        }
        set { defaults.set(min(1, max(0.25, newValue)), forKey: "find.opacity") }
    }

    // MARK: - Results / history preferences

    var historyLimit: Int {
        get {
            let value = defaults.integer(forKey: "find.historyLimit")
            return value >= 5 ? min(100, value) : 15
        }
        set { defaults.set(min(100, max(5, newValue)), forKey: "find.historyLimit") }
    }

    var resultFullLine: Bool {
        get { defaults.bool(forKey: "find.resultFullLine") }
        set { defaults.set(newValue, forKey: "find.resultFullLine") }
    }

    var resultPreviewLength: Int {
        get {
            let value = defaults.integer(forKey: "find.resultPreviewLength")
            return value >= 20 ? min(2000, value) : 260
        }
        set { defaults.set(min(2000, max(20, newValue)), forKey: "find.resultPreviewLength") }
    }

    /// ⌘G / ⇧⌘G use the selected text instead of the last query.
    var hotkeyFollowsSelection: Bool {
        get { defaults.bool(forKey: "find.hotkeyFollowsSelection") }
        set { defaults.set(newValue, forKey: "find.hotkeyFollowsSelection") }
    }

    // MARK: - Directory search

    var dirPath: String {
        get { defaults.string(forKey: "find.dir.lastPath") ?? "" }
        set { defaults.set(newValue, forKey: "find.dir.lastPath") }
    }

    var dirFileTypes: String {
        get { defaults.string(forKey: "find.dir.fileTypes") ?? "*.c:*.cpp:*.h" }
        set { defaults.set(newValue, forKey: "find.dir.fileTypes") }
    }

    var dirFileNameRegex: String {
        get { defaults.string(forKey: "find.dir.fileNameRegex") ?? "" }
        set { defaults.set(newValue, forKey: "find.dir.fileNameRegex") }
    }

    var dirSkipFolders: String {
        get { defaults.string(forKey: "find.dir.skipFolders") ?? "debug:Debug:.vs:.git:.svn" }
        set { defaults.set(newValue, forKey: "find.dir.skipFolders") }
    }

    var dirSkipHidden: Bool {
        get {
            if defaults.object(forKey: "find.dir.skipHidden") == nil { return true }
            return defaults.bool(forKey: "find.dir.skipHidden")
        }
        set { defaults.set(newValue, forKey: "find.dir.skipHidden") }
    }

    var dirSkipBinary: Bool {
        get {
            if defaults.object(forKey: "find.dir.skipBinary") == nil { return true }
            return defaults.bool(forKey: "find.dir.skipBinary")
        }
        set { defaults.set(newValue, forKey: "find.dir.skipBinary") }
    }

    var dirSkipLarge: Bool {
        get {
            if defaults.object(forKey: "find.dir.skipLarge") == nil { return true }
            return defaults.bool(forKey: "find.dir.skipLarge")
        }
        set { defaults.set(newValue, forKey: "find.dir.skipLarge") }
    }

    var dirMaxSizeMB: Int {
        get {
            let value = defaults.integer(forKey: "find.dir.maxSizeMB")
            return value > 0 ? value : 20
        }
        set { defaults.set(newValue, forKey: "find.dir.maxSizeMB") }
    }

    var dirSkipSubdirectories: Bool {
        get { defaults.bool(forKey: "find.dir.skipSubdirectories") }
        set { defaults.set(newValue, forKey: "find.dir.skipSubdirectories") }
    }

    // MARK: - History

    var queryHistory: [String] {
        get { defaults.stringArray(forKey: "find.queryHistory") ?? [] }
        set { defaults.set(newValue, forKey: "find.queryHistory") }
    }

    var replaceHistory: [String] {
        get { defaults.stringArray(forKey: "find.replaceHistory") ?? [] }
        set { defaults.set(newValue, forKey: "find.replaceHistory") }
    }

    func recordQuery(_ text: String) {
        guard !text.isEmpty, text.count <= Self.historyMaxLength else { return }
        lastQuery = text
        var list = queryHistory.filter { $0 != text }
        list.insert(text, at: 0)
        if list.count > historyLimit { list.removeLast(list.count - historyLimit) }
        queryHistory = list
    }

    func recordReplacement(_ text: String) {
        guard !text.isEmpty, text.count <= Self.historyMaxLength else { return }
        lastReplacement = text
        var list = replaceHistory.filter { $0 != text }
        list.insert(text, at: 0)
        if list.count > historyLimit { list.removeLast(list.count - historyLimit) }
        replaceHistory = list
    }

    func clearHistory() {
        queryHistory = []
        replaceHistory = []
        lastQuery = ""
        lastReplacement = ""
    }

    /// Trims stored history after the limit was lowered in Settings.
    func applyHistoryLimit() {
        let limit = historyLimit
        if queryHistory.count > limit { queryHistory = Array(queryHistory.prefix(limit)) }
        if replaceHistory.count > limit { replaceHistory = Array(replaceHistory.prefix(limit)) }
    }
}
