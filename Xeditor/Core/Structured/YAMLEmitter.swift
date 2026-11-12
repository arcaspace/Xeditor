import Foundation

/// Emits a `StructuredValue` as block-style YAML with two-space indentation.
/// Output is deliberately plain: no anchors, tags or flow collections except
/// for empty objects and arrays, which are written as `{}` and `[]`.
enum YAMLEmitter {
    static func emit(_ value: StructuredValue) -> String {
        var lines: [String] = []
        append(value, indent: 0, lines: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func append(_ value: StructuredValue, indent: Int, lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        switch value {
        case .object(let members):
            if members.isEmpty {
                lines.append(pad + "{}")
                return
            }
            for (key, member) in members {
                let name = scalarText(key, indent: indent)
                switch member {
                case .object(let children) where !children.isEmpty:
                    lines.append(pad + name + ":")
                    append(member, indent: indent + 2, lines: &lines)
                case .array(let children) where !children.isEmpty:
                    lines.append(pad + name + ":")
                    append(member, indent: indent + 2, lines: &lines)
                case .string(let text) where text.contains("\n"):
                    appendBlockScalar(text, header: pad + name + ":", indent: indent + 2, lines: &lines)
                default:
                    lines.append(pad + name + ": " + inlineText(member, indent: indent))
                }
            }
        case .array(let elements):
            if elements.isEmpty {
                lines.append(pad + "[]")
                return
            }
            for element in elements {
                switch element {
                case .object(let members) where !members.isEmpty:
                    appendObjectInSequence(members, indent: indent, lines: &lines)
                case .array(let children) where !children.isEmpty:
                    lines.append(pad + "-")
                    append(element, indent: indent + 2, lines: &lines)
                case .string(let text) where text.contains("\n"):
                    appendBlockScalar(text, header: pad + "-", indent: indent + 2, lines: &lines)
                default:
                    lines.append(pad + "- " + inlineText(element, indent: indent))
                }
            }
        case .string(let text) where text.contains("\n"):
            appendBlockScalar(text, header: pad, indent: indent + 2, lines: &lines)
        default:
            lines.append(pad + inlineText(value, indent: indent))
        }
    }

    /// The first key of an object inside a sequence shares the dash's line.
    private static func appendObjectInSequence(_ members: [(String, StructuredValue)],
                                               indent: Int,
                                               lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        let childPad = String(repeating: " ", count: indent + 2)
        var first = true
        for (key, member) in members {
            let prefix = first ? pad + "- " : childPad
            first = false
            let name = scalarText(key, indent: indent + 2)
            switch member {
            case .object(let children) where !children.isEmpty:
                lines.append(prefix + name + ":")
                append(member, indent: indent + 4, lines: &lines)
            case .array(let children) where !children.isEmpty:
                lines.append(prefix + name + ":")
                append(member, indent: indent + 4, lines: &lines)
            case .string(let text) where text.contains("\n"):
                appendBlockScalar(text, header: prefix + name + ":", indent: indent + 4, lines: &lines)
            default:
                lines.append(prefix + name + ": " + inlineText(member, indent: indent + 2))
            }
        }
    }

    // MARK: - Scalars

    private static func inlineText(_ value: StructuredValue, indent: Int) -> String {
        switch value {
        case .string(let text):
            return scalarText(text, indent: indent)
        case .number(let text):
            return text
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .object:
            return "{}"
        case .array:
            return "[]"
        }
    }

    /// Quotes a scalar unless it can be written safely as plain text.
    static func scalarText(_ text: String, indent: Int) -> String {
        if isPlainSafe(text) { return text }
        var escaped = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped + "\""
    }

    private static let reservedWords: Set<String> = [
        "null", "Null", "NULL", "~", "true", "True", "TRUE",
        "false", "False", "FALSE", "yes", "Yes", "YES", "no", "No", "NO",
        "on", "On", "ON", "off", "Off", "OFF", ".nan", ".NaN", ".NAN",
        ".inf", ".Inf", ".INF", "-.inf", "+.inf"
    ]

    private static func isPlainSafe(_ text: String) -> Bool {
        guard !text.isEmpty, !reservedWords.contains(text) else { return false }
        guard let first = text.unicodeScalars.first else { return false }
        // A leading indicator would change the meaning of the scalar.
        if "-?:,[]{}#&*!|>'\"%@`".unicodeScalars.contains(first) { return false }
        if first == " " || first == "\t" { return false }
        if text.hasSuffix(" ") || text.hasSuffix("\t") { return false }
        if text.contains(": ") || text.contains(" #") { return false }
        if text.hasPrefix("- ") { return false }
        for scalar in text.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if scalar == ":" || scalar == "#" {
                // Mid-token punctuation is fine in YAML ("a:b", "C#") but we
                // keep the emitter predictable and quote these.
                return false
            }
        }
        if looksNumeric(text) { return false }
        return true
    }

    /// Numbers and number-like strings are quoted so they stay strings.
    private static func looksNumeric(_ text: String) -> Bool {
        var index = text.startIndex
        if index < text.endIndex, text[index] == "-" || text[index] == "+" {
            index = text.index(after: index)
        }
        var sawDigit = false
        var sawDot = false
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber {
                sawDigit = true
            } else if character == "." && !sawDot {
                sawDot = true
            } else if character == "e" || character == "E" {
                index = text.index(after: index)
                if index < text.endIndex, text[index] == "+" || text[index] == "-" {
                    index = text.index(after: index)
                }
                continue
            } else {
                return false
            }
            index = text.index(after: index)
        }
        return sawDigit
    }

    // MARK: - Block scalars

    private static func appendBlockScalar(_ text: String,
                                          header: String,
                                          indent: Int,
                                          lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        let hasTrailingNewline = text.hasSuffix("\n")
        lines.append(header + " " + (hasTrailingNewline ? "|" : "|-"))
        var body = text
        if hasTrailingNewline { body.removeLast() }
        for line in body.components(separatedBy: "\n") {
            lines.append(line.isEmpty ? "" : pad + line)
        }
    }
}
