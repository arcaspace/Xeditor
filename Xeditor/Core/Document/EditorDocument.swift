import AppKit
import CoreFoundation
import Foundation

struct DocumentEncoding: Identifiable, Hashable {
    let id: UInt
    let name: String
    let stringEncoding: String.Encoding

    init(_ stringEncoding: String.Encoding, name: String) {
        self.id = stringEncoding.rawValue
        self.name = name
        self.stringEncoding = stringEncoding
    }

    static let utf8 = DocumentEncoding(.utf8, name: "UTF-8")
    static let utf16LE = DocumentEncoding(.utf16LittleEndian, name: "UTF-16 LE")
    static let utf16BE = DocumentEncoding(.utf16BigEndian, name: "UTF-16 BE")
    static let isoLatin1 = DocumentEncoding(.isoLatin1, name: "Western (ISO Latin 1)")
    static let windows1252 = DocumentEncoding(.windowsCP1252, name: "Windows (CP1252)")

    static let gb18030: DocumentEncoding = {
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return DocumentEncoding(String.Encoding(rawValue: enc), name: "Chinese Simplified (GB18030 / GBK)")
    }()

    static let big5: DocumentEncoding = {
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        return DocumentEncoding(String.Encoding(rawValue: enc), name: "Chinese Traditional (Big5)")
    }()

    static let shiftJIS = DocumentEncoding(.shiftJIS, name: "Japanese (Shift-JIS)")

    static let allSupported: [DocumentEncoding] = [
        utf8,
        gb18030,
        big5,
        utf16LE,
        utf16BE,
        isoLatin1,
        windows1252,
        shiftJIS
    ]

    static func matching(_ raw: UInt) -> DocumentEncoding {
        if let found = allSupported.first(where: { $0.id == raw }) {
            return found
        }
        return DocumentEncoding(String.Encoding(rawValue: raw), name: "Encoding (\(raw))")
    }
}

/// One open buffer: owns its Scintilla view, path, language, encoding, and cursor state.
@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()
    let editor: EditorBridge

    @Published private(set) var url: URL?
    @Published private(set) var isDirty = false
    @Published private(set) var language: LanguagePreset
    @Published private(set) var encoding: DocumentEncoding = .utf8
    @Published private(set) var lineCount = 1
    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1

    var displayName: String { url?.lastPathComponent ?? "Untitled" }

    init(url: URL? = nil, text: String? = nil) {
        let bridge = EditorBridge(frame: .zero)
        editor = bridge
        language = url.flatMap { LanguagePreset.matching(url: $0) } ?? .plain

        if let url {
            bridge.loadFile(url.path)
            encoding = DocumentEncoding.matching(UInt(bridge.fileEncoding))
        } else if let text {
            bridge.setText(text)
            encoding = .utf8
        }
        bridge.setLexerName(language.lexer)
        bridge.setKeywordSets(LanguageKeywords.sets(for: language.name))
        self.url = url
        lineCount = Int(bridge.lineCount())
        cursorLine = Int(bridge.currentLine())
        cursorColumn = Int(bridge.currentColumn())

        // Apply global editor preferences
        EditorSettings.shared.apply(to: bridge)

        bridge.changeHandler = { [weak self] dirty in
            guard let self else { return }
            if Thread.isMainThread {
                self.isDirty = dirty
            } else {
                DispatchQueue.main.async { self.isDirty = dirty }
            }
        }

        bridge.contentChangeHandler = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.lineCount = Int(self.editor.lineCount())
                self.cursorLine = Int(self.editor.currentLine())
                self.cursorColumn = Int(self.editor.currentColumn())
            }
        }
    }

    func updateCursorPosition() {
        cursorLine = Int(editor.currentLine())
        cursorColumn = Int(editor.currentColumn())
    }

    func setLanguage(_ preset: LanguagePreset) {
        language = preset
        editor.setLexerName(preset.lexer)
        editor.setKeywordSets(LanguageKeywords.sets(for: preset.name))
        editor.restyleAll()
    }

    func reload(withEncoding targetEncoding: DocumentEncoding) {
        guard url != nil else {
            encoding = targetEncoding
            return
        }
        editor.reload(withEncoding: targetEncoding.id)
        encoding = targetEncoding
        lineCount = Int(editor.lineCount())
        cursorLine = Int(editor.currentLine())
        cursorColumn = Int(editor.currentColumn())
        isDirty = editor.isDirty
    }

    /// Writes the buffer, optionally to a new path (Save As).
    @discardableResult
    func save(to destination: URL? = nil) -> Bool {
        guard let target = destination ?? url else { return false }
        guard editor.writeFile(target.path) else { return false }

        let moved = destination != nil
        url = target
        isDirty = editor.isDirty

        if moved, let preset = LanguagePreset.matching(url: target) {
            setLanguage(preset)
        }
        return true
    }

    var isEmpty: Bool {
        (editor.text() as NSString).length == 0
    }

    // MARK: - Bookmarks

    func toggleBookmark() { editor.toggleBookmarkAtCurrentLine() }
    func nextBookmark() { editor.nextBookmark(); updateCursorPosition() }
    func previousBookmark() { editor.previousBookmark(); updateCursorPosition() }
    func clearAllBookmarks() { editor.clearAllBookmarks() }

    // MARK: - Code Folding

    func foldAll() { editor.foldAll() }
    func unfoldAll() { editor.unfoldAll() }
    func toggleFoldCurrent() { editor.toggleFoldCurrent() }

    // MARK: - Line Operations & Text Transformation

    func duplicateLine() { editor.duplicateLine(); updateCursorPosition() }
    func deleteLine() { editor.deleteLine(); updateCursorPosition() }
    func moveLineUp() { editor.moveLineUp(); updateCursorPosition() }
    func moveLineDown() { editor.moveLineDown(); updateCursorPosition() }
    func joinLines() { editor.joinLines(); updateCursorPosition() }
    func toUpperCase() { editor.toUpperCase() }
    func toLowerCase() { editor.toLowerCase() }
    func toggleComment() {
        guard let pfx = language.commentPrefix else { return }
        editor.toggleComment(withPrefix: pfx)
        updateCursorPosition()
    }
    func trimTrailingWhitespace() { editor.trimTrailingWhitespace() }
    func sortLines(ascending: Bool) { editor.sortSelectedLinesAscending(ascending) }
}
