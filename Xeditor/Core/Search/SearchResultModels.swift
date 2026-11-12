import Foundation

/// Where a search result lives. Documents are matched by identity so a renamed
/// or moved file still resolves while its tab is open.
enum SearchResultLocation: Equatable {
    case document(EditorDocument.ID)
    case file(URL)
}

struct SearchResultMatch: Equatable {
    let location: SearchResultLocation
    let line: Int            // 1-based
    let byteStart: Int       // UTF-8 offsets for documents, UTF-16 for files
    let byteEnd: Int
    let preview: String
    /// Document content revision at capture time; 0 for files on disk.
    let revision: Int
}

final class SearchResultGroup {
    let location: SearchResultLocation
    let displayName: String
    var matches: [SearchResultMatch]

    init(location: SearchResultLocation, displayName: String, matches: [SearchResultMatch]) {
        self.location = location
        self.displayName = displayName
        self.matches = matches
    }
}

/// Everything the results outline displays for one search.
final class SearchResultsModel {
    let querySummary: String
    var groups: [SearchResultGroup]
    var truncated: Bool
    let isDirectorySearch: Bool

    init(querySummary: String,
         groups: [SearchResultGroup] = [],
         truncated: Bool = false,
         isDirectorySearch: Bool = false) {
        self.querySummary = querySummary
        self.groups = groups
        self.truncated = truncated
        self.isDirectorySearch = isDirectorySearch
    }

    var totalHits: Int {
        groups.reduce(0) { $0 + $1.matches.count }
    }

    /// One-line preview around the match; long lines are clipped unless the
    /// user asked for the whole line in Settings.
    static func preview(lineText: String,
                        matchOffset: Int,
                        limit: Int = 200,
                        fullLine: Bool = false) -> String {
        let text = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        guard !fullLine else { return text }
        guard text.count > limit else { return text }

        let start = max(0, min(matchOffset, text.count - 1))
        let half = limit / 2
        let lower = max(0, start - half)
        let upper = min(text.count, lower + limit)
        let slice = String(text[text.index(text.startIndex, offsetBy: lower)..<text.index(text.startIndex, offsetBy: upper)])
        return (lower > 0 ? "…" : "") + slice + (upper < text.count ? "…" : "")
    }
}
