import Foundation

/// Expands "Extended" mode escapes the way notepad-- does.
enum ExtendedEscape {
    /// `\n`, `\r`, `\t`, `\0`, `\\`, `\xHH`, `\oNNN`, `\dNNN`, `\uHHHH`.
    /// Unknown escapes are kept verbatim.
    static func expand(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        var output = String.UnicodeScalarView()
        var i = 0

        while i < scalars.count {
            let scalar = scalars[i]
            guard scalar == "\\", i + 1 < scalars.count else {
                output.append(scalar)
                i += 1
                continue
            }

            let next = scalars[i + 1]
            switch next {
            case "n":
                output.append("\n"); i += 2
            case "r":
                output.append("\r"); i += 2
            case "t":
                output.append("\t"); i += 2
            case "0":
                output.append(Unicode.Scalar(0)); i += 2
            case "\\":
                output.append("\\"); i += 2
            case "x", "o", "d", "u":
                let radix: Int
                let maxDigits: Int
                switch next {
                case "x": radix = 16; maxDigits = 2
                case "o": radix = 8;  maxDigits = 3
                case "d": radix = 10; maxDigits = 3
                default:  radix = 16; maxDigits = 4
                }
                var value = 0
                var consumed = 0
                var j = i + 2
                while j < scalars.count && consumed < maxDigits,
                      let digit = Int(String(scalars[j]), radix: radix) {
                    value = value * radix + digit
                    consumed += 1
                    j += 1
                }
                if consumed > 0, let unicode = Unicode.Scalar(UInt32(value)) {
                    output.append(unicode)
                    i = j
                } else {
                    output.append(scalar)
                    i += 1
                }
            default:
                output.append(scalar)
                i += 1
            }
        }
        return String(output)
    }
}

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
        let expanded = mode == .extended ? ExtendedEscape.expand(text) : text
        return Data(expanded.utf8)
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
        case .normal, .extended:
            let literal = mode == .extended ? ExtendedEscape.expand(text) : text
            return NSRegularExpression.escapedPattern(for: literal)
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
