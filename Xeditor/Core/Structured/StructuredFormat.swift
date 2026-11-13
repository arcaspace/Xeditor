import Foundation

/// A problem found while structuring JSON, YAML or SQL text. The position is
/// 1-based and points at the offending character when the parser knows it.
struct StructuredFormatError: Error {
    let message: String
    let line: Int?
    let column: Int?

    var displayText: String {
        if let line, let column {
            return LF("Line %d, column %d: %@", line, column, message)
        }
        return message
    }

    init(_ message: String, line: Int? = nil, column: Int? = nil) {
        self.message = message
        self.line = line
        self.column = column
    }
}

/// The three text formats the Structured Data tool understands.
enum StructuredDataFormat: Int, CaseIterable {
    case json
    case yaml
    case sql

    var title: String {
        switch self {
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .sql: return "SQL"
        }
    }

    /// The file extensions this format usually appears in.
    var fileExtensions: [String] {
        switch self {
        case .json: return ["json"]
        case .yaml: return ["yaml", "yml"]
        case .sql: return ["sql"]
        }
    }

    /// Pretty-prints the text in this format.
    func format(_ text: String) throws -> String {
        switch self {
        case .json:
            return try JSONFormatter.format(text)
        case .yaml:
            return try YAMLFormatter.format(text)
        case .sql:
            return try SQLFormatter.format(text)
        }
    }

    /// Collapses the text onto a single line. Only JSON has an unambiguous
    /// compact form; YAML and SQL keep their formatting.
    var supportsMinify: Bool { self == .json }

    func minify(_ text: String) throws -> String {
        switch self {
        case .json:
            return try JSONFormatter.minify(text)
        case .yaml, .sql:
            return text
        }
    }

    /// Guesses the format from the first meaningful characters and a few
    /// distinctive keywords. Used to preselect the segmented control.
    static func detect(_ text: String) -> StructuredDataFormat {
        let trimmed = text.drop(while: { $0.isWhitespace })
        if trimmed.first == "{" || trimmed.first == "[" {
            return .json
        }
        let head = text.prefix(4000).uppercased()
        let sqlKeywords = ["SELECT ", "INSERT ", "UPDATE ", "DELETE ", "CREATE ", "ALTER ",
                           "DROP ", "WITH ", "MERGE "]
        for keyword in sqlKeywords where head.contains(keyword) {
            return .sql
        }
        return .yaml
    }
}

/// Shared helpers for the formatters.
enum StructuredFormatSupport {
    /// Builds a positioned error from a byte offset in UTF-8 data.
    static func error(_ message: String, byteOffset: Int, in bytes: [UInt8]) -> StructuredFormatError {
        let clamped = max(0, min(byteOffset, bytes.count))
        let prefix = String(decoding: bytes[0..<clamped], as: UTF8.self)
        var line = 1
        var column = 1
        for character in prefix {
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return StructuredFormatError(message, line: line, column: column)
    }

    /// Removes trailing spaces and tabs from a line.
    static func trimmingTrailingWhitespace(_ line: String) -> String {
        var result = line
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}
