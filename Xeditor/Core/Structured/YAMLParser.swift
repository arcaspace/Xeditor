import Foundation

/// A pragmatic YAML reader for configuration-style documents: block mappings
/// and sequences, flow collections, quoted scalars, comments and literal /
/// folded block scalars. Anchors, aliases, tags and multiple documents are
/// rejected with a clear message rather than being misread.
enum YAMLParser {
    private struct Line {
        let number: Int
        let indent: Int
        let raw: String
        let content: String
        let leadingTab: Bool
        var isIgnorable: Bool { content.isEmpty }
        var isDocumentMarker: Bool { content == "---" || content == "..." }
    }

    private final class Cursor {
        let lines: [Line]
        var index = 0
        init(_ lines: [Line]) { self.lines = lines }

        func skipIgnorable() {
            while index < lines.count, lines[index].isIgnorable { index += 1 }
        }

        func peek() -> Line? {
            skipIgnorable()
            return index < lines.count ? lines[index] : nil
        }
    }

    static func parse(_ text: String) throws -> StructuredValue {
        let lines = prepare(text)
        let cursor = Cursor(lines)
        cursor.skipIgnorable()
        if let first = cursor.peek(), first.isDocumentMarker, first.content == "---" {
            if first.content == "---" { cursor.index += 1 }
        }
        cursor.skipIgnorable()
        guard let first = cursor.peek() else {
            throw StructuredFormatError("The document is empty.")
        }
        let value = try parseBlock(cursor, indent: first.indent)
        cursor.skipIgnorable()
        if let rest = cursor.peek() {
            if rest.content == "..." {
                cursor.index += 1
                cursor.skipIgnorable()
                if let extra = cursor.peek() {
                    throw error("Multiple YAML documents are not supported.",
                                line: extra.number)
                }
            } else if rest.content == "---" {
                throw error("Multiple YAML documents are not supported.", line: rest.number)
            } else {
                throw error("Unexpected content after the document.", line: rest.number)
            }
        }
        return value
    }

    // MARK: - Line preparation

    private static func prepare(_ text: String) -> [Line] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n").enumerated().map { offset, raw in
            var indent = 0
            for character in raw {
                if character == " " { indent += 1 } else { break }
            }
            let content = stripComment(String(raw.dropFirst(indent)))
            return Line(number: offset + 1,
                        indent: indent,
                        raw: raw,
                        content: content.trimmingCharacters(in: .whitespaces),
                        leadingTab: raw.dropFirst(indent).first == "\t")
        }
    }

    /// Removes a trailing comment. A `#` starts a comment only at the start of
    /// the content or after whitespace, and never inside quotes.
    private static func stripComment(_ text: String) -> String {
        var quote: Character?
        var previous: Character = " "
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let current = quote {
                result.append(character)
                if current == "\"" {
                    if character == "\\" {
                        let next = text.index(after: index)
                        if next < text.endIndex {
                            result.append(text[next])
                            index = next
                        }
                    } else if character == "\"" {
                        quote = nil
                    }
                } else if character == "'" {
                    if let next = text.index(after: index) as String.Index?,
                       next < text.endIndex, text[next] == "'" {
                        result.append(text[next])
                        index = next
                    } else {
                        quote = nil
                    }
                }
            } else {
                if character == "\"" || character == "'" {
                    quote = character
                    result.append(character)
                } else if character == "#", previous == " " || previous == "\t" || result.isEmpty {
                    break
                } else {
                    result.append(character)
                }
            }
            previous = character
            index = text.index(after: index)
        }
        return result
    }

    // MARK: - Block parsing

    private static func parseBlock(_ cursor: Cursor, indent: Int) throws -> StructuredValue {
        cursor.skipIgnorable()
        guard let line = cursor.peek() else {
            throw StructuredFormatError("Unexpected end of document.")
        }
        if line.indent < indent {
            throw error("Unexpected outdent.", line: line.number)
        }
        if line.leadingTab {
            throw error("Tabs cannot be used for indentation.", line: line.number)
        }
        let actualIndent = line.indent
        if isSequenceEntry(line.content) {
            return try parseSequence(cursor, indent: actualIndent)
        }
        if isMappingEntry(line.content) {
            return try parseMapping(cursor, indent: actualIndent)
        }
        // A lone scalar document.
        cursor.index += 1
        return try parseInline(line.content, line: line.number)
    }

    private static func parseMapping(_ cursor: Cursor, indent: Int) throws -> StructuredValue {
        var members: [(String, StructuredValue)] = []
        while true {
            cursor.skipIgnorable()
            guard let line = cursor.peek() else { break }
            if line.isDocumentMarker { break }
            if line.leadingTab {
                throw error("Tabs cannot be used for indentation.", line: line.number)
            }
            if line.indent != indent || isSequenceEntry(line.content) { break }
            guard isMappingEntry(line.content) else {
                throw error("Expected a “key: value” entry.", line: line.number)
            }
            cursor.index += 1
            let (key, rest) = try splitKey(line.content, line: line.number)
            if members.contains(where: { $0.0 == key }) {
                throw error("Duplicate key “\(key)”.", line: line.number)
            }
            let value: StructuredValue
            if rest.isEmpty {
                value = try nestedValue(cursor, parentIndent: indent)
            } else if isBlockScalarHeader(rest) {
                value = .string(readBlockScalar(cursor, indicator: rest, parentIndent: indent))
            } else {
                value = try parseInline(rest, line: line.number)
            }
            members.append((key, value))
        }
        guard !members.isEmpty else {
            throw StructuredFormatError("The document is empty.")
        }
        return .object(members)
    }

    private static func parseSequence(_ cursor: Cursor, indent: Int) throws -> StructuredValue {
        var elements: [StructuredValue] = []
        while true {
            cursor.skipIgnorable()
            guard let line = cursor.peek(), line.indent == indent,
                  isSequenceEntry(line.content) else { break }
            if line.leadingTab {
                throw error("Tabs cannot be used for indentation.", line: line.number)
            }
            cursor.index += 1
            let afterDash = line.content.dropFirst()
            let spaces = afterDash.prefix(while: { $0 == " " }).count
            let content = String(afterDash.dropFirst(spaces))
            let keyColumn = indent + 1 + spaces

            if content.isEmpty {
                elements.append(try nestedValue(cursor, parentIndent: indent))
            } else if isBlockScalarHeader(content) {
                elements.append(.string(readBlockScalar(cursor, indicator: content, parentIndent: indent)))
            } else if isMappingEntry(content) {
                elements.append(try parseCompactMapping(cursor,
                                                        first: content,
                                                        keyColumn: keyColumn,
                                                        seqIndent: indent,
                                                        firstLine: line.number))
            } else if isSequenceEntry(content) {
                throw error("Nested inline sequences are not supported.", line: line.number)
            } else {
                elements.append(try parseInline(content, line: line.number))
            }
        }
        return .array(elements)
    }

    /// Handles `- key: value` and any further keys of that same object.
    private static func parseCompactMapping(_ cursor: Cursor,
                                            first: String,
                                            keyColumn: Int,
                                            seqIndent: Int,
                                            firstLine: Int) throws -> StructuredValue {
        var members: [(String, StructuredValue)] = []
        let firstEntry = try splitKey(first, line: firstLine)
        var pending: (key: String, rest: String, line: Int)? =
            (firstEntry.0, firstEntry.1, firstLine)

        while let entry = pending {
            pending = nil
            if members.contains(where: { $0.0 == entry.key }) {
                throw error("Duplicate key “\(entry.key)”.", line: entry.line)
            }
            let value: StructuredValue
            if entry.rest.isEmpty {
                cursor.skipIgnorable()
                if let next = cursor.peek(), next.indent > keyColumn {
                    value = try parseBlock(cursor, indent: next.indent)
                } else {
                    value = .null
                }
            } else if isBlockScalarHeader(entry.rest) {
                value = .string(readBlockScalar(cursor, indicator: entry.rest, parentIndent: keyColumn))
            } else {
                value = try parseInline(entry.rest, line: entry.line)
            }
            members.append((entry.key, value))

            cursor.skipIgnorable()
            guard let next = cursor.peek(),
                  next.indent == keyColumn,
                  next.indent > seqIndent,
                  isMappingEntry(next.content) else { break }
            cursor.index += 1
            let (key, rest) = try splitKey(next.content, line: next.number)
            pending = (key, rest, next.number)
        }
        return .object(members)
    }

    /// The value under a `key:` or `-` that had nothing after it.
    private static func nestedValue(_ cursor: Cursor, parentIndent: Int) throws -> StructuredValue {
        cursor.skipIgnorable()
        guard let next = cursor.peek(), next.indent > parentIndent else {
            return .null
        }
        return try parseBlock(cursor, indent: next.indent)
    }

    // MARK: - Keys and lines

    private static func isSequenceEntry(_ content: String) -> Bool {
        content == "-" || content.hasPrefix("- ")
    }

    private static func isMappingEntry(_ content: String) -> Bool {
        (try? splitKey(content, line: 0)) != nil
    }

    /// Splits `key: rest` at the first colon followed by a space or the end of
    /// the line, outside quotes. Throws when the line is not a mapping entry.
    private static func splitKey(_ content: String,
                                 line: Int) throws -> (String, String) {
        var quote: Character?
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if let current = quote {
                if current == "\"" {
                    if character == "\\" {
                        index = content.index(after: index)
                    } else if character == "\"" {
                        quote = nil
                    }
                } else if character == "'" {
                    if let next = content.index(index, offsetBy: 1, limitedBy: content.endIndex),
                       next < content.endIndex, content[next] == "'" {
                        index = next
                    } else {
                        quote = nil
                    }
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let next = content.index(after: index)
                if next == content.endIndex || content[next] == " " || content[next] == "\t" {
                    let keyText = String(content[content.startIndex..<index])
                        .trimmingCharacters(in: .whitespaces)
                    guard !keyText.isEmpty else {
                        throw error("Expected a key before “:”.", line: line)
                    }
                    let key = try scalarString(keyText, line: line, allowNumber: true)
                    let rest = String(content[next...]).trimmingCharacters(in: .whitespaces)
                    return (key, rest)
                }
            }
            index = content.index(after: index)
        }
        throw error("Expected “:” after a key.", line: line)
    }

    // MARK: - Block scalars

    private static func isBlockScalarHeader(_ text: String) -> Bool {
        guard let first = text.first, first == "|" || first == ">" else { return false }
        let rest = text.dropFirst()
        return rest.allSatisfy { $0 == "-" || $0 == "+" || $0.isNumber || $0 == " " }
    }

    private static func readBlockScalar(_ cursor: Cursor,
                                        indicator: String,
                                        parentIndent: Int) -> String {
        let style = indicator.first == ">"
        let chomping = indicator.contains("-") ? "strip" : (indicator.contains("+") ? "keep" : "clip")

        var rawLines: [String] = []
        while cursor.index < cursor.lines.count {
            let line = cursor.lines[cursor.index]
            if line.raw.trimmingCharacters(in: .whitespaces).isEmpty {
                rawLines.append("")
                cursor.index += 1
                continue
            }
            if line.indent <= parentIndent { break }
            rawLines.append(line.raw)
            cursor.index += 1
        }

        // Drop trailing blank lines but remember how many there were (+ keeps).
        var trailingBlanks = 0
        while let last = rawLines.last, last.isEmpty {
            rawLines.removeLast()
            trailingBlanks += 1
        }
        guard !rawLines.isEmpty else {
            switch chomping {
            case "keep": return String(repeating: "\n", count: trailingBlanks)
            default: return ""
            }
        }
        let blockIndent = rawLines
            .filter { !$0.isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
            .min() ?? 0
        let stripped = rawLines.map { line -> String in
            guard !line.isEmpty else { return "" }
            return String(line.dropFirst(min(blockIndent, line.count)))
        }

        var body: String
        if style {
            var result = ""
            for (offset, line) in stripped.enumerated() {
                if offset == 0 {
                    result = line
                } else if line.isEmpty || stripped[offset - 1].isEmpty {
                    result += "\n" + line
                } else {
                    result += " " + line
                }
            }
            body = result
        } else {
            body = stripped.joined(separator: "\n")
        }

        switch chomping {
        case "strip":
            return body
        case "keep":
            return body + "\n" + String(repeating: "\n", count: trailingBlanks)
        default:
            return body + "\n"
        }
    }

    // MARK: - Inline values

    private static func parseInline(_ text: String, line: Int) throws -> StructuredValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            var flow = FlowParser(text: trimmed, line: line)
            let value = try flow.parseValue()
            flow.skipSpaces()
            guard flow.isAtEnd else {
                throw error("Unexpected content after a flow collection.", line: line)
            }
            return value
        }
        return try parseScalar(trimmed, line: line)
    }

    private static func parseScalar(_ text: String, line: Int) throws -> StructuredValue {
        guard !text.isEmpty else { return .null }
        if text.hasPrefix("&") || text.hasPrefix("*") || text.hasPrefix("!") {
            throw error("Anchors, aliases and tags are not supported.", line: line)
        }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return .string(try scalarString(text, line: line, allowNumber: false))
        }
        switch text {
        case "~", "null", "Null", "NULL":
            return .null
        case "true", "True", "TRUE":
            return .bool(true)
        case "false", "False", "FALSE":
            return .bool(false)
        default:
            if isNumber(text) {
                return .number(text)
            }
            return .string(text)
        }
    }

    /// Decodes a scalar as a string, honouring single- and double-quoted forms.
    private static func scalarString(_ text: String,
                                     line: Int,
                                     allowNumber: Bool) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("'") {
            guard trimmed.count >= 2, trimmed.hasSuffix("'") else {
                throw error("Unterminated single-quoted string.", line: line)
            }
            let body = String(trimmed.dropFirst().dropLast())
            return body.replacingOccurrences(of: "''", with: "'")
        }
        if trimmed.hasPrefix("\"") {
            guard trimmed.count >= 2, trimmed.hasSuffix("\"") else {
                throw error("Unterminated double-quoted string.", line: line)
            }
            return try decodeDoubleQuoted(String(trimmed.dropFirst().dropLast()), line: line)
        }
        if allowNumber, isNumber(trimmed) {
            return trimmed
        }
        return trimmed
    }

    private static func decodeDoubleQuoted(_ body: String, line: Int) throws -> String {
        var result = ""
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            guard character == "\\" else {
                result.append(character)
                index = body.index(after: index)
                continue
            }
            index = body.index(after: index)
            guard index < body.endIndex else {
                throw error("Unterminated escape sequence.", line: line)
            }
            switch body[index] {
            case "0": result.append("\0")
            case "a": result.append("\u{07}")
            case "b": result.append("\u{08}")
            case "t", "\t": result.append("\t")
            case "n": result.append("\n")
            case "v": result.append("\u{0B}")
            case "f": result.append("\u{0C}")
            case "r": result.append("\r")
            case "e": result.append("\u{1B}")
            case " ": result.append(" ")
            case "\"": result.append("\"")
            case "/": result.append("/")
            case "\\": result.append("\\")
            case "N": result.append("\u{85}")
            case "_": result.append("\u{A0}")
            case "L": result.append("\u{2028}")
            case "P": result.append("\u{2029}")
            case "x", "u", "U":
                let length = body[index] == "x" ? 2 : (body[index] == "u" ? 4 : 8)
                var cursor = body.index(after: index)
                var code: UInt32 = 0
                for _ in 0..<length {
                    guard cursor < body.endIndex, let digit = body[cursor].hexDigitValue else {
                        throw error("Invalid \\\(body[index]) escape sequence.", line: line)
                    }
                    code = code << 4 | UInt32(digit)
                    cursor = body.index(after: cursor)
                }
                if let scalar = UnicodeScalar(code) { result.unicodeScalars.append(scalar) }
                index = cursor
                continue
            default:
                throw error("Invalid escape sequence “\\\(body[index])”.", line: line)
            }
            index = body.index(after: index)
        }
        return result
    }

    /// Decimal integers, floats and exponents only: other YAML numeric forms do
    /// not exist in JSON and are treated as strings.
    static func isNumber(_ text: String) -> Bool {
        var index = text.startIndex
        if index < text.endIndex, text[index] == "-" || text[index] == "+" {
            // JSON has no unary plus.
            if text[index] == "+" { return false }
            index = text.index(after: index)
        }
        var digits = 0
        let firstDigit = index
        while index < text.endIndex, text[index].isNumber, text[index].isASCII {
            digits += 1
            index = text.index(after: index)
        }
        guard digits > 0 else { return false }
        // Leading zeros are fine in YAML but not in JSON, so keep those strings.
        if text[firstDigit] == "0", digits > 1 { return false }
        if index < text.endIndex, text[index] == "." {
            index = text.index(after: index)
            var fraction = 0
            while index < text.endIndex, text[index].isNumber, text[index].isASCII {
                fraction += 1
                index = text.index(after: index)
            }
            guard fraction > 0 else { return false }
        }
        if index < text.endIndex, text[index] == "e" || text[index] == "E" {
            index = text.index(after: index)
            if index < text.endIndex, text[index] == "+" || text[index] == "-" {
                index = text.index(after: index)
            }
            var exponent = 0
            while index < text.endIndex, text[index].isNumber, text[index].isASCII {
                exponent += 1
                index = text.index(after: index)
            }
            guard exponent > 0 else { return false }
        }
        return index == text.endIndex
    }

    private static func error(_ message: String, line: Int) -> StructuredFormatError {
        StructuredFormatError(message, line: max(1, line), column: 1)
    }

    // MARK: - Flow collections

    private struct FlowParser {
        let characters: [Character]
        let line: Int
        var index = 0

        init(text: String, line: Int) {
            characters = Array(text)
            self.line = line
        }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
        }

        mutating func parseValue() throws -> StructuredValue {
            skipSpaces()
            guard index < characters.count else {
                throw YAMLParser.error("Unexpected end of a flow collection.", line: line)
            }
            switch characters[index] {
            case "[":
                return try parseArray()
            case "{":
                return try parseObject()
            case "\"", "'":
                return .string(try parseQuoted())
            default:
                let plain = parsePlain(stopAtColon: false)
                return try YAMLParser.parseScalar(plain, line: line)
            }
        }

        private mutating func parseArray() throws -> StructuredValue {
            index += 1 // "["
            var elements: [StructuredValue] = []
            skipSpaces()
            if index < characters.count, characters[index] == "]" {
                index += 1
                return .array([])
            }
            while true {
                elements.append(try parseValue())
                skipSpaces()
                guard index < characters.count else {
                    throw YAMLParser.error("Unterminated flow sequence.", line: line)
                }
                if characters[index] == "," {
                    index += 1
                    skipSpaces()
                    if index < characters.count, characters[index] == "]" {
                        index += 1
                        return .array(elements)
                    }
                    continue
                }
                if characters[index] == "]" {
                    index += 1
                    return .array(elements)
                }
                throw YAMLParser.error("Expected “,” or “]” in a flow sequence.", line: line)
            }
        }

        private mutating func parseObject() throws -> StructuredValue {
            index += 1 // "{"
            var members: [(String, StructuredValue)] = []
            skipSpaces()
            if index < characters.count, characters[index] == "}" {
                index += 1
                return .object([])
            }
            while true {
                skipSpaces()
                let key: String
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    key = try parseQuoted()
                } else {
                    key = parsePlain(stopAtColon: true).trimmingCharacters(in: .whitespaces)
                }
                skipSpaces()
                guard index < characters.count, characters[index] == ":" else {
                    throw YAMLParser.error("Expected “:” in a flow mapping.", line: line)
                }
                index += 1
                let value = try parseValue()
                if let existing = members.firstIndex(where: { $0.0 == key }) {
                    members[existing].1 = value
                } else {
                    members.append((key, value))
                }
                skipSpaces()
                guard index < characters.count else {
                    throw YAMLParser.error("Unterminated flow mapping.", line: line)
                }
                if characters[index] == "," {
                    index += 1
                    skipSpaces()
                    if index < characters.count, characters[index] == "}" {
                        index += 1
                        return .object(members)
                    }
                    continue
                }
                if characters[index] == "}" {
                    index += 1
                    return .object(members)
                }
                throw YAMLParser.error("Expected “,” or “}” in a flow mapping.", line: line)
            }
        }

        private mutating func parseQuoted() throws -> String {
            let quote = characters[index]
            var result = ""
            index += 1
            while index < characters.count {
                let character = characters[index]
                if quote == "\"" && character == "\\" {
                    let start = index
                    index += 1
                    guard index < characters.count else {
                        throw YAMLParser.error("Unterminated escape sequence.", line: line)
                    }
                    var end = index
                    switch characters[index] {
                    case "x": end = min(characters.count - 1, end + 2)
                    case "u": end = min(characters.count - 1, end + 4)
                    case "U": end = min(characters.count - 1, end + 8)
                    default: break
                    }
                    let escape = String(characters[start...end])
                    result += try YAMLParser.decodeDoubleQuoted(escape, line: line)
                    index = end + 1
                    continue
                }
                if character == quote {
                    if quote == "'", index + 1 < characters.count, characters[index + 1] == "'" {
                        result.append("'")
                        index += 2
                        continue
                    }
                    index += 1
                    return result
                }
                result.append(character)
                index += 1
            }
            throw YAMLParser.error("Unterminated quoted string.", line: line)
        }

        private mutating func parsePlain(stopAtColon: Bool) -> String {
            var result = ""
            while index < characters.count {
                let character = characters[index]
                if character == "," || character == "]" || character == "}" { break }
                if stopAtColon, character == ":" { break }
                result.append(character)
                index += 1
            }
            return result.trimmingCharacters(in: .whitespaces)
        }
    }
}
