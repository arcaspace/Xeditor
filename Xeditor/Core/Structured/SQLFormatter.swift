import Foundation

/// A pragmatic SQL formatter: uppercases recognized keywords, puts the main
/// clauses on their own lines and breaks boolean conditions, while leaving
/// strings, quoted identifiers and comments untouched.
enum SQLFormatter {
    private struct Token {
        enum Kind {
            case word
            case number
            case string
            case quotedIdentifier
            case comment
            case symbol
        }

        let kind: Kind
        let text: String
    }

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "BY", "HAVING", "LIMIT", "OFFSET",
        "UNION", "INTERSECT", "EXCEPT", "ALL", "DISTINCT", "AS", "AND", "OR", "NOT",
        "IN", "IS", "NULL", "LIKE", "ILIKE", "BETWEEN", "EXISTS", "CASE", "WHEN",
        "THEN", "ELSE", "END", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL",
        "CROSS", "NATURAL", "ON", "USING", "INSERT", "INTO", "VALUES", "UPDATE",
        "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "TRUNCATE", "INDEX",
        "VIEW", "PRIMARY", "FOREIGN", "KEY", "REFERENCES", "DEFAULT", "UNIQUE",
        "CHECK", "CONSTRAINT", "WITH", "RECURSIVE", "RETURNING", "MERGE", "ASC",
        "DESC", "OVER", "PARTITION", "WINDOW", "FETCH", "REPLACE", "CALL",
        "TRUE", "FALSE", "CAST", "IF", "GRANT", "REVOKE", "BEGIN", "COMMIT",
        "ROLLBACK", "SAVEPOINT", "EXPLAIN", "ANALYZE", "VACUUM"
    ]

    /// Keywords that start a new line.
    private static let clauseKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "INTERSECT", "EXCEPT", "INSERT", "UPDATE", "DELETE", "VALUES",
        "SET", "RETURNING", "WITH", "CREATE", "ALTER", "DROP", "TRUNCATE", "MERGE",
        "REPLACE", "CALL", "WINDOW", "FETCH", "LEFT", "RIGHT", "INNER", "OUTER",
        "FULL", "CROSS", "NATURAL", "JOIN"
    ]

    private static let joinPrefixes: Set<String> = [
        "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "NATURAL"
    ]

    /// Words that want a space before an opening parenthesis ("IN ("), as
    /// opposed to function calls ("COUNT(").
    private static let spacedBeforeParen: Set<String> = [
        "IN", "NOT", "VALUES", "EXISTS", "ON", "AND", "OR", "AS", "WHEN", "THEN",
        "ELSE", "OVER", "USING", "BY"
    ]

    static func format(_ text: String) throws -> String {
        let tokens = try tokenize(text)
        guard !tokens.isEmpty else {
            throw StructuredFormatError("The document is empty.")
        }

        let writer = Writer()
        var depth = 0
        var previousWord: String?

        for token in tokens {
            switch token.kind {
            case .comment:
                if !writer.lineHasContent {
                    writer.append(token.text, spaceBefore: false)
                } else if token.text.hasPrefix("--") {
                    writer.newline(indent: depth * 2)
                    writer.append(token.text, spaceBefore: false)
                } else {
                    writer.append(token.text)
                }
                if token.text.hasPrefix("--") || token.text.contains("\n") {
                    writer.newline(indent: depth * 2)
                }
                previousWord = nil

            case .word:
                let upper = token.text.uppercased()
                let isKeyword = keywords.contains(upper)
                let word = isKeyword ? upper : token.text

                if isKeyword, clauseKeywords.contains(upper) {
                    // "LEFT JOIN" stays on one line: only the prefix breaks.
                    if upper == "JOIN", let previous = previousWord, joinPrefixes.contains(previous) {
                        writer.spaceIfNeeded()
                    } else {
                        writer.newline(indent: depth * 2)
                    }
                } else if isKeyword, upper == "AND" || upper == "OR" {
                    writer.newline(indent: depth * 2 + 2)
                } else {
                    writer.spaceIfNeeded()
                }
                writer.raw(word)
                previousWord = isKeyword ? upper : nil

            case .symbol:
                switch token.text {
                case "(":
                    let previousIsSpacedKeyword = previousWord.map(spacedBeforeParen.contains) ?? false
                    writer.append("(", spaceBefore: previousIsSpacedKeyword)
                    depth += 1
                    writer.needsSpace = false
                case ")":
                    depth = max(0, depth - 1)
                    writer.append(")", spaceBefore: false)
                case ",":
                    writer.append(",", spaceBefore: false)
                case ".":
                    writer.append(".", spaceBefore: false)
                    writer.needsSpace = false
                case ";":
                    writer.append(";", spaceBefore: false)
                    writer.newline(indent: 0)
                case "::":
                    writer.append("::", spaceBefore: false)
                    writer.needsSpace = false
                default:
                    writer.append(token.text)
                }
                previousWord = nil

            case .number, .string, .quotedIdentifier:
                writer.append(token.text)
                previousWord = nil
            }
        }

        return writer.finish()
    }

    // MARK: - Writer

    private final class Writer {
        private(set) var text = ""
        var needsSpace = false
        var lineHasContent = false

        func spaceIfNeeded() {
            guard needsSpace, !text.isEmpty, !text.hasSuffix("\n"), !text.hasSuffix(" ") else { return }
            text += " "
        }

        func append(_ value: String, spaceBefore: Bool = true) {
            if spaceBefore { spaceIfNeeded() }
            else { trimTrailingSpace() }
            text += value
            needsSpace = true
            lineHasContent = true
        }

        func raw(_ value: String) {
            text += value
            needsSpace = true
            lineHasContent = true
        }

        func newline(indent: Int) {
            guard lineHasContent || !text.isEmpty else { return }
            trimTrailingSpace()
            if !text.hasSuffix("\n") { text += "\n" }
            if indent > 0 { text += String(repeating: " ", count: indent) }
            needsSpace = false
            lineHasContent = false
        }

        private func trimTrailingSpace() {
            while text.hasSuffix(" ") { text.removeLast() }
        }

        func finish() -> String {
            trimTrailingSpace()
            while text.hasSuffix("\n\n") { text.removeLast() }
            if !text.hasSuffix("\n") { text += "\n" }
            return text
        }
    }

    // MARK: - Lexing

    private static func tokenize(_ text: String) throws -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0

        func error(_ message: String, at offset: Int) -> StructuredFormatError {
            let prefix = String(characters[0..<max(0, min(offset, characters.count))])
            var line = 1
            var column = 1
            for character in prefix {
                if character == "\n" { line += 1; column = 1 }
                else { column += 1 }
            }
            return StructuredFormatError(message, line: line, column: column)
        }

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }

            // Line comment
            if character == "-", index + 1 < characters.count, characters[index + 1] == "-" {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                tokens.append(Token(kind: .comment, text: String(characters[start..<index])))
                continue
            }

            // Block comment
            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let start = index
                index += 2
                var closed = false
                while index + 1 < characters.count {
                    if characters[index] == "*", characters[index + 1] == "/" {
                        index += 2
                        closed = true
                        break
                    }
                    index += 1
                }
                guard closed else {
                    throw error("Unterminated block comment.", at: start)
                }
                tokens.append(Token(kind: .comment, text: String(characters[start..<index])))
                continue
            }

            // Single-quoted string, with '' as the escape for a quote.
            if character == "'" {
                let start = index
                index += 1
                var closed = false
                while index < characters.count {
                    if characters[index] == "'" {
                        if index + 1 < characters.count, characters[index + 1] == "'" {
                            index += 2
                            continue
                        }
                        index += 1
                        closed = true
                        break
                    }
                    index += 1
                }
                guard closed else { throw error("Unterminated string literal.", at: start) }
                tokens.append(Token(kind: .string, text: String(characters[start..<index])))
                continue
            }

            // Double-quoted or backtick-quoted identifier.
            if character == "\"" || character == "`" {
                let quote = character
                let start = index
                index += 1
                var closed = false
                while index < characters.count {
                    if characters[index] == quote { index += 1; closed = true; break }
                    index += 1
                }
                guard closed else { throw error("Unterminated quoted identifier.", at: start) }
                tokens.append(Token(kind: .quotedIdentifier, text: String(characters[start..<index])))
                continue
            }

            // Numbers
            if character.isNumber {
                let start = index
                while index < characters.count,
                      characters[index].isNumber || characters[index] == "." || characters[index] == "e" || characters[index] == "E" {
                    // Stop an exponent scan at a + or - that follows e/E.
                    if characters[index] == "e" || characters[index] == "E",
                       index + 1 < characters.count,
                       (characters[index + 1] == "+" || characters[index + 1] == "-") {
                        index += 2
                        continue
                    }
                    if characters[index] == "e" || characters[index] == "E",
                       index + 1 >= characters.count {
                        break
                    }
                    index += 1
                }
                tokens.append(Token(kind: .number, text: String(characters[start..<index])))
                continue
            }

            // Words (identifiers and keywords)
            if character.isLetter || character == "_" {
                let start = index
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "$" {
                    index += 1
                }
                tokens.append(Token(kind: .word, text: String(characters[start..<index])))
                continue
            }

            // Two-character operators
            if index + 1 < characters.count {
                let pair = String([characters[index], characters[index + 1]])
                if ["<=", ">=", "<>", "!=", "||", "::", "->", "=>", ":=", "!<", "!>"].contains(pair) {
                    tokens.append(Token(kind: .symbol, text: pair))
                    index += 2
                    continue
                }
            }

            tokens.append(Token(kind: .symbol, text: String(character)))
            index += 1
        }

        return tokens
    }
}
