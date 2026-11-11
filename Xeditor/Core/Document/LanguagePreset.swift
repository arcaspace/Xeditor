import Foundation

/// A user-selectable language and the Lexilla lexer that implements it.
struct LanguagePreset: Hashable {
    let name: String
    let title: String
    let lexer: String
    let extensions: [String]
    let commentPrefix: String?

    init(name: String, title: String, lexer: String, extensions: [String], commentPrefix: String? = "//") {
        self.name = name
        self.title = title
        self.lexer = lexer
        self.extensions = extensions
        self.commentPrefix = commentPrefix
    }

    static let plain = LanguagePreset(
        name: "plain", title: "Plain Text", lexer: "null",
        extensions: ["txt", "log", "text"], commentPrefix: nil)

    static let all: [LanguagePreset] = [
        plain,
        .init(name: "cpp", title: "C / C++", lexer: "cpp",
              extensions: ["c", "h", "cpp", "hpp", "cc", "cxx", "hxx"], commentPrefix: "//"),
        .init(name: "objc", title: "Objective-C", lexer: "cpp",
              extensions: ["m", "mm"], commentPrefix: "//"),
        .init(name: "swift", title: "Swift", lexer: "cpp",
              extensions: ["swift"], commentPrefix: "//"),
        .init(name: "python", title: "Python", lexer: "python",
              extensions: ["py", "pyw"], commentPrefix: "#"),
        .init(name: "javascript", title: "JavaScript", lexer: "cpp",
              extensions: ["js", "mjs", "cjs"], commentPrefix: "//"),
        .init(name: "typescript", title: "TypeScript", lexer: "cpp",
              extensions: ["ts", "tsx"], commentPrefix: "//"),
        .init(name: "json", title: "JSON", lexer: "json",
              extensions: ["json"], commentPrefix: "//"),
        .init(name: "xml", title: "XML", lexer: "xml",
              extensions: ["xml", "plist", "svg"], commentPrefix: nil),
        .init(name: "html", title: "HTML", lexer: "hypertext",
              extensions: ["html", "htm", "xhtml"], commentPrefix: nil),
        .init(name: "css", title: "CSS", lexer: "css",
              extensions: ["css", "scss"], commentPrefix: "/*"),
        .init(name: "markdown", title: "Markdown", lexer: "markdown",
              extensions: ["md", "markdown"], commentPrefix: nil),
        .init(name: "shell", title: "Shell", lexer: "bash",
              extensions: ["sh", "bash", "zsh"], commentPrefix: "#"),
        .init(name: "sql", title: "SQL", lexer: "sql",
              extensions: ["sql"], commentPrefix: "--"),
        .init(name: "yaml", title: "YAML", lexer: "yaml",
              extensions: ["yml", "yaml"], commentPrefix: "#"),
        .init(name: "rust", title: "Rust", lexer: "rust",
              extensions: ["rs"], commentPrefix: "//"),
        .init(name: "go", title: "Go", lexer: "cpp",
              extensions: ["go"], commentPrefix: "//"),
        .init(name: "java", title: "Java", lexer: "cpp",
              extensions: ["java"], commentPrefix: "//"),
        .init(name: "makefile", title: "Makefile", lexer: "makefile",
              extensions: ["mk", "mak"], commentPrefix: "#"),
        .init(name: "diff", title: "Diff / Patch", lexer: "diff",
              extensions: ["diff", "patch"], commentPrefix: nil),
        .init(name: "lua", title: "Lua", lexer: "lua",
              extensions: ["lua"], commentPrefix: "--"),
        .init(name: "ruby", title: "Ruby", lexer: "ruby",
              extensions: ["rb"], commentPrefix: "#"),
        .init(name: "perl", title: "Perl", lexer: "perl",
              extensions: ["pl", "pm"], commentPrefix: "#"),
        .init(name: "php", title: "PHP", lexer: "hypertext",
              extensions: ["php"], commentPrefix: "//"),
        .init(name: "cmake", title: "CMake", lexer: "cmake",
              extensions: ["cmake"], commentPrefix: "#"),
        .init(name: "ini", title: "INI / Configuration", lexer: "conf",
              extensions: ["ini", "cfg", "conf"], commentPrefix: "#"),
        .init(name: "batch", title: "Batch", lexer: "batch",
              extensions: ["bat", "cmd"], commentPrefix: "REM"),
    ]

    static func matching(_ pathExtension: String) -> LanguagePreset? {
        let ext = pathExtension.lowercased()
        return all.first { $0.extensions.contains(ext) }
    }

    /// Detects a language from a full URL, covering files whose name carries the
    /// language rather than a usable extension (Makefile, CMakeLists.txt).
    static func matching(url: URL) -> LanguagePreset? {
        let fileName = url.lastPathComponent.lowercased()
        switch fileName {
        case "makefile", "gnumakefile", "bsdmakefile", "makefile.am":
            return all.first { $0.name == "makefile" }
        case "cmakelists.txt":
            return all.first { $0.name == "cmake" }
        default:
            if fileName.hasSuffix(".cmake.in") {
                return all.first { $0.name == "cmake" }
            }
            return matching(url.pathExtension)
        }
    }
}
