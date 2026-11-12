import Foundation

/// Normalizes hand-written YAML: expands indentation tabs, rebases every
/// nesting level onto a two-space grid, trims trailing whitespace and collapses
/// runs of blank lines. Comments, key order and scalar text are preserved.
enum YAMLFormatter {
    private static let indentUnit = "  "

    static func format(_ text: String) throws -> String {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Original indentation width of each currently open level.
        var levelIndents: [Int] = []
        var output: [String] = []
        var previousWasBlank = true

        for rawLine in rawLines {
            var line = rawLine
            if line.hasSuffix("\r") { line.removeLast() }
            line = StructuredFormatSupport.trimmingTrailingWhitespace(line)

            var indentWidth = 0
            var characterIndex = line.startIndex
            while characterIndex < line.endIndex {
                let character = line[characterIndex]
                if character == " " {
                    indentWidth += 1
                } else if character == "\t" {
                    indentWidth += 2
                } else {
                    break
                }
                characterIndex = line.index(after: characterIndex)
            }
            let content = String(line[characterIndex...])
            // "-\titem" and "-   item" become "- item"; "---" stays untouched.
            let normalizedContent: String
            if content.hasPrefix("- "), !content.hasPrefix("---") {
                let rest = content.dropFirst(2).drop(while: { $0 == " " })
                normalizedContent = rest.isEmpty ? "-" : "- " + rest
            } else {
                normalizedContent = content
            }

            if normalizedContent.isEmpty {
                if !previousWasBlank {
                    output.append("")
                    previousWasBlank = true
                }
                continue
            }
            previousWasBlank = false

            if levelIndents.isEmpty {
                levelIndents = [indentWidth]
            } else if indentWidth > levelIndents[levelIndents.count - 1] {
                levelIndents.append(indentWidth)
            } else {
                while levelIndents.count > 1 && indentWidth < levelIndents[levelIndents.count - 1] {
                    levelIndents.removeLast()
                }
                if indentWidth > levelIndents[levelIndents.count - 1] {
                    // Inconsistent dedent: treat it as one level deeper.
                    levelIndents.append(indentWidth)
                } else if indentWidth < levelIndents[0] {
                    levelIndents = [indentWidth]
                }
            }

            let level = max(0, levelIndents.count - 1)
            output.append(String(repeating: indentUnit, count: level) + normalizedContent)
        }

        // Drop leading blank lines, keep exactly one trailing newline.
        while let first = output.first, first.isEmpty { output.removeFirst() }
        while let last = output.last, last.isEmpty { output.removeLast() }

        guard !output.isEmpty else {
            throw StructuredFormatError("The document is empty.")
        }
        return output.joined(separator: "\n") + "\n"
    }
}
