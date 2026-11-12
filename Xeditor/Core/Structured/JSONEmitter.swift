import Foundation

/// Emits a `StructuredValue` as pretty-printed JSON with two-space indentation.
enum JSONEmitter {
    static func emit(_ value: StructuredValue, indent: String = "  ") -> String {
        var output = ""
        append(value, depth: 0, indent: indent, output: &output)
        return output + "\n"
    }

    private static func append(_ value: StructuredValue,
                               depth: Int,
                               indent: String,
                               output: inout String) {
        let pad = String(repeating: indent, count: depth)
        let innerPad = String(repeating: indent, count: depth + 1)
        switch value {
        case .object(let members):
            if members.isEmpty {
                output += "{}"
                return
            }
            output += "{\n"
            for (offset, member) in members.enumerated() {
                output += innerPad + quoted(member.0) + ": "
                append(member.1, depth: depth + 1, indent: indent, output: &output)
                if offset < members.count - 1 { output += "," }
                output += "\n"
            }
            output += pad + "}"
        case .array(let elements):
            if elements.isEmpty {
                output += "[]"
                return
            }
            output += "[\n"
            for (offset, element) in elements.enumerated() {
                output += innerPad
                append(element, depth: depth + 1, indent: indent, output: &output)
                if offset < elements.count - 1 { output += "," }
                output += "\n"
            }
            output += pad + "]"
        case .string(let text):
            output += quoted(text)
        case .number(let text):
            output += text
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
