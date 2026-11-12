import Foundation

/// A small, dependency-free JSON tokenizer, validator and pretty-printer.
/// Token order is preserved exactly, so key order in the output matches the
/// input (Foundation's JSONSerialization does not guarantee that).
enum JSONFormatter {
    private struct Token {
        enum Kind {
            case objectOpen
            case objectClose
            case arrayOpen
            case arrayClose
            case colon
            case comma
            case string
            case number
            case literal
        }

        let kind: Kind
        let range: Range<Int>
    }

    // MARK: - Public API

    static func format(_ text: String, indent: String = "  ") throws -> String {
        let bytes = Array(text.utf8)
        let tokens = try tokenize(bytes)
        try validate(tokens, bytes: bytes)

        var output = ""
        var depth = 0
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token.kind {
            case .objectOpen, .arrayOpen:
                let closeKind: Token.Kind = token.kind == .objectOpen ? .objectClose : .arrayClose
                if index + 1 < tokens.count, tokens[index + 1].kind == closeKind {
                    output += raw(token, bytes) + raw(tokens[index + 1], bytes)
                    index += 2
                    continue
                }
                output += raw(token, bytes)
                depth += 1
                output += "\n" + String(repeating: indent, count: depth)
            case .objectClose, .arrayClose:
                depth = max(0, depth - 1)
                output += "\n" + String(repeating: indent, count: depth) + raw(token, bytes)
            case .comma:
                output += ",\n" + String(repeating: indent, count: depth)
            case .colon:
                output += ": "
            case .string, .number, .literal:
                output += raw(token, bytes)
            }
            index += 1
        }
        return output + "\n"
    }

    static func minify(_ text: String) throws -> String {
        let bytes = Array(text.utf8)
        let tokens = try tokenize(bytes)
        try validate(tokens, bytes: bytes)

        var output = ""
        for token in tokens {
            output += raw(token, bytes)
        }
        return output + "\n"
    }

    /// Parses JSON into the ordered value tree used by the converters.
    static func parse(_ text: String) throws -> StructuredValue {
        let bytes = Array(text.utf8)
        let tokens = try tokenize(bytes)
        var index = 0

        func fail(_ message: String) -> StructuredFormatError {
            let offset = index < tokens.count ? tokens[index].range.lowerBound : bytes.count
            return StructuredFormatSupport.error(message, byteOffset: offset, in: bytes)
        }

        func parseValue(depth: Int) throws -> StructuredValue {
            guard depth < 512 else { throw fail("The value is nested too deeply.") }
            guard index < tokens.count else { throw fail("Unexpected end of input.") }
            switch tokens[index].kind {
            case .objectOpen:
                index += 1
                var members: [(String, StructuredValue)] = []
                if index < tokens.count, tokens[index].kind == .objectClose {
                    index += 1
                    return .object([])
                }
                while true {
                    guard index < tokens.count, tokens[index].kind == .string else {
                        throw fail("Expected a property name in double quotes.")
                    }
                    let key = decoded(token: tokens[index], bytes: bytes)
                    index += 1
                    guard index < tokens.count, tokens[index].kind == .colon else {
                        throw fail("Expected “:” after a property name.")
                    }
                    index += 1
                    let value = try parseValue(depth: depth + 1)
                    // Duplicate names keep the last value at their first position.
                    if let existing = members.firstIndex(where: { $0.0 == key }) {
                        members[existing].1 = value
                    } else {
                        members.append((key, value))
                    }
                    guard index < tokens.count else { throw fail("Unexpected end of input.") }
                    if tokens[index].kind == .comma {
                        index += 1
                        continue
                    }
                    if tokens[index].kind == .objectClose {
                        index += 1
                        return .object(members)
                    }
                    throw fail("Expected “,” or “}”.")
                }
            case .arrayOpen:
                index += 1
                var elements: [StructuredValue] = []
                if index < tokens.count, tokens[index].kind == .arrayClose {
                    index += 1
                    return .array([])
                }
                while true {
                    elements.append(try parseValue(depth: depth + 1))
                    guard index < tokens.count else { throw fail("Unexpected end of input.") }
                    if tokens[index].kind == .comma {
                        index += 1
                        continue
                    }
                    if tokens[index].kind == .arrayClose {
                        index += 1
                        return .array(elements)
                    }
                    throw fail("Expected “,” or “]”.")
                }
            case .string:
                let value = decoded(token: tokens[index], bytes: bytes)
                index += 1
                return .string(value)
            case .number:
                let value = raw(tokens[index], bytes)
                index += 1
                return .number(value)
            case .literal:
                let value = raw(tokens[index], bytes)
                index += 1
                switch value {
                case "true": return .bool(true)
                case "false": return .bool(false)
                default: return .null
                }
            default:
                throw fail("Expected a JSON value.")
            }
        }

        let value = try parseValue(depth: 0)
        if index < tokens.count {
            throw fail("Unexpected content after the top-level value.")
        }
        return value
    }

    /// Turns a validated string token (quotes included) into its value.
    private static func decoded(token: Token, bytes: [UInt8]) -> String {
        var scalars: [UnicodeScalar] = []
        var index = token.range.lowerBound + 1
        let end = token.range.upperBound - 1
        while index < end {
            let byte = bytes[index]
            if byte != 0x5C {
                // Copy one UTF-8 sequence verbatim.
                var length = 1
                if byte >= 0xF0 { length = 4 }
                else if byte >= 0xE0 { length = 3 }
                else if byte >= 0xC0 { length = 2 }
                let slice = Array(bytes[index..<min(index + length, end)])
                if let text = String(bytes: slice, encoding: .utf8), let scalar = text.unicodeScalars.first {
                    scalars.append(scalar)
                }
                index += length
                continue
            }
            index += 1
            switch bytes[index] {
            case 0x22: scalars.append("\""); index += 1
            case 0x5C: scalars.append("\\"); index += 1
            case 0x2F: scalars.append("/"); index += 1
            case 0x62: scalars.append("\u{08}"); index += 1
            case 0x66: scalars.append("\u{0C}"); index += 1
            case 0x6E: scalars.append("\n"); index += 1
            case 0x72: scalars.append("\r"); index += 1
            case 0x74: scalars.append("\t"); index += 1
            case 0x75:
                var code: UInt32 = 0
                for offset in 1...4 {
                    code = code << 4 | UInt32(hexValue(bytes[index + offset]))
                }
                index += 5
                if code >= 0xD800, code <= 0xDBFF,
                   index + 5 < end, bytes[index] == 0x5C, bytes[index + 1] == 0x75 {
                    var low: UInt32 = 0
                    for offset in 2...5 {
                        low = low << 4 | UInt32(hexValue(bytes[index + offset]))
                    }
                    if low >= 0xDC00, low <= 0xDFFF {
                        let combined = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        if let scalar = UnicodeScalar(combined) { scalars.append(scalar) }
                        index += 6
                        continue
                    }
                }
                if let scalar = UnicodeScalar(code) {
                    scalars.append(scalar)
                }
            default:
                index += 1
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func hexValue(_ byte: UInt8) -> Int {
        switch byte {
        case 0x30...0x39: return Int(byte - 0x30)
        case 0x41...0x46: return Int(byte - 0x41 + 10)
        default: return Int(byte - 0x61 + 10)
        }
    }

    // MARK: - Tokenizing

    private static func raw(_ token: Token, _ bytes: [UInt8]) -> String {
        String(decoding: bytes[token.range], as: UTF8.self)
    }

    private static func tokenize(_ bytes: [UInt8]) throws -> [Token] {
        var tokens: [Token] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            case 0x7B:
                tokens.append(Token(kind: .objectOpen, range: index..<index + 1)); index += 1
            case 0x7D:
                tokens.append(Token(kind: .objectClose, range: index..<index + 1)); index += 1
            case 0x5B:
                tokens.append(Token(kind: .arrayOpen, range: index..<index + 1)); index += 1
            case 0x5D:
                tokens.append(Token(kind: .arrayClose, range: index..<index + 1)); index += 1
            case 0x3A:
                tokens.append(Token(kind: .colon, range: index..<index + 1)); index += 1
            case 0x2C:
                tokens.append(Token(kind: .comma, range: index..<index + 1)); index += 1
            case 0x22:
                let start = index
                index += 1
                var closed = false
                while index < bytes.count {
                    let character = bytes[index]
                    if character == 0x22 {
                        index += 1
                        closed = true
                        break
                    }
                    if character == 0x5C {
                        index += 1
                        guard index < bytes.count else {
                            throw StructuredFormatSupport.error("Unterminated escape sequence.", byteOffset: index - 1, in: bytes)
                        }
                        switch bytes[index] {
                        case 0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74:
                            index += 1
                        case 0x75:
                            guard index + 4 < bytes.count else {
                                throw StructuredFormatSupport.error("Incomplete \\u escape sequence.", byteOffset: index, in: bytes)
                            }
                            for offset in 1...4 where !isHexDigit(bytes[index + offset]) {
                                throw StructuredFormatSupport.error("Invalid \\u escape sequence.", byteOffset: index + offset, in: bytes)
                            }
                            index += 5
                        default:
                            throw StructuredFormatSupport.error("Invalid escape sequence in a string.", byteOffset: index, in: bytes)
                        }
                        continue
                    }
                    if character < 0x20 {
                        throw StructuredFormatSupport.error("Control character inside a string.", byteOffset: index, in: bytes)
                    }
                    index += 1
                }
                guard closed else {
                    throw StructuredFormatSupport.error("Unterminated string.", byteOffset: start, in: bytes)
                }
                tokens.append(Token(kind: .string, range: start..<index))
            case 0x2D, 0x30...0x39:
                let start = index
                if bytes[index] == 0x2D { index += 1 }
                guard index < bytes.count else {
                    throw StructuredFormatSupport.error("Incomplete number.", byteOffset: index, in: bytes)
                }
                if bytes[index] == 0x30 {
                    index += 1
                } else if isDigit(bytes[index]) {
                    while index < bytes.count, isDigit(bytes[index]) { index += 1 }
                } else {
                    throw StructuredFormatSupport.error("Invalid number.", byteOffset: index, in: bytes)
                }
                if index < bytes.count, bytes[index] == 0x2E {
                    index += 1
                    guard index < bytes.count, isDigit(bytes[index]) else {
                        throw StructuredFormatSupport.error("A decimal point must be followed by a digit.", byteOffset: index, in: bytes)
                    }
                    while index < bytes.count, isDigit(bytes[index]) { index += 1 }
                }
                if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
                    index += 1
                    if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
                    guard index < bytes.count, isDigit(bytes[index]) else {
                        throw StructuredFormatSupport.error("An exponent must contain a digit.", byteOffset: index, in: bytes)
                    }
                    while index < bytes.count, isDigit(bytes[index]) { index += 1 }
                }
                tokens.append(Token(kind: .number, range: start..<index))
            case 0x74: // t
                index = try scanLiteral("true", at: index, bytes: bytes)
                tokens.append(Token(kind: .literal, range: index - 4..<index))
            case 0x66: // f
                index = try scanLiteral("false", at: index, bytes: bytes)
                tokens.append(Token(kind: .literal, range: index - 5..<index))
            case 0x6E: // n
                index = try scanLiteral("null", at: index, bytes: bytes)
                tokens.append(Token(kind: .literal, range: index - 4..<index))
            default:
                let character = String(UnicodeScalar(byte))
                throw StructuredFormatSupport.error("Unexpected character “\(character)”.",
                                                     byteOffset: index, in: bytes)
            }
        }
        return tokens
    }

    private static func scanLiteral(_ literal: String, at start: Int, bytes: [UInt8]) throws -> Int {
        let expected = Array(literal.utf8)
        guard start + expected.count <= bytes.count,
              Array(bytes[start..<start + expected.count]) == expected else {
            throw StructuredFormatSupport.error("Expected “\(literal)”.",
                                                 byteOffset: start, in: bytes)
        }
        return start + expected.count
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }

    // MARK: - Validating

    private static func validate(_ tokens: [Token], bytes: [UInt8]) throws {
        var index = 0

        func fail(_ message: String) -> StructuredFormatError {
            let offset = index < tokens.count ? tokens[index].range.lowerBound : bytes.count
            return StructuredFormatSupport.error(message, byteOffset: offset, in: bytes)
        }

        func parseValue(depth: Int) throws {
            guard depth < 512 else { throw fail("The value is nested too deeply.") }
            guard index < tokens.count else { throw fail("Unexpected end of input.") }
            switch tokens[index].kind {
            case .objectOpen:
                index += 1
                if index < tokens.count, tokens[index].kind == .objectClose {
                    index += 1
                    return
                }
                while true {
                    guard index < tokens.count, tokens[index].kind == .string else {
                        throw fail("Expected a property name in double quotes.")
                    }
                    index += 1
                    guard index < tokens.count, tokens[index].kind == .colon else {
                        throw fail("Expected “:” after a property name.")
                    }
                    index += 1
                    try parseValue(depth: depth + 1)
                    guard index < tokens.count else { throw fail("Unexpected end of input.") }
                    if tokens[index].kind == .comma {
                        index += 1
                        continue
                    }
                    if tokens[index].kind == .objectClose {
                        index += 1
                        return
                    }
                    throw fail("Expected “,” or “}”.")
                }
            case .arrayOpen:
                index += 1
                if index < tokens.count, tokens[index].kind == .arrayClose {
                    index += 1
                    return
                }
                while true {
                    try parseValue(depth: depth + 1)
                    guard index < tokens.count else { throw fail("Unexpected end of input.") }
                    if tokens[index].kind == .comma {
                        index += 1
                        continue
                    }
                    if tokens[index].kind == .arrayClose {
                        index += 1
                        return
                    }
                    throw fail("Expected “,” or “]”.")
                }
            case .string, .number, .literal:
                index += 1
            default:
                throw fail("Expected a JSON value.")
            }
        }

        try parseValue(depth: 0)
        if index < tokens.count {
            throw fail("Unexpected content after the top-level value.")
        }
    }
}
