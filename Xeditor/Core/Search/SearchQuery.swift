import Foundation

/// One search action's query and options, converted to the bridge's flags.
struct SearchQuery {
    let text: String
    let replacement: String
    let mode: SearchMode
    let matchCase: Bool
    let wholeWord: Bool
    let wrap: Bool
    let backward: Bool
    let inSelection: Bool

    var isRegex: Bool { mode == .regex }

    /// The literal / pattern bytes handed to Scintilla.
    var needleData: Data {
        Data(text.utf8)
    }

    var replacementData: Data {
        Data(replacement.utf8)
    }

    var flags: XEditorSearchFlags {
        var flags: XEditorSearchFlags = []
        if matchCase { flags.insert(.caseSensitive) }
        if mode == .regex { flags.insert(.regex) }
        // Scintilla's C++11 regex path ignores whole-word matching, so keeping
        // it on would silently do nothing.
        if wholeWord && mode != .regex { flags.insert(.wholeWord) }
        if wrap { flags.insert(.wrap) }
        return flags
    }

    /// Pattern used by the Foundation (directory search) implementation.
    /// ICU replacement syntax is `$1`; the current-document path uses `\1`.
    var foundationPattern: String {
        switch mode {
        case .regex:
            return text
        case .normal:
            return NSRegularExpression.escapedPattern(for: text)
        }
    }

    var foundationOptions: NSRegularExpression.Options {
        matchCase ? [] : [.caseInsensitive]
    }

    /// Directory replace always uses ICU; translate Scintilla's `\1`..`\9`
    /// back-references to `$1`..`$9` and leave other escapes alone.
    var foundationReplacement: String {
        guard isRegex else { return replacement }
        var result = ""
        let chars = Array(replacement)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count, chars[i + 1].isNumber,
               let digit = Int(String(chars[i + 1])) {
                result += "$\(digit)"
                i += 2
                continue
            }
            result.append(ch)
            i += 1
        }
        return result
    }
}
