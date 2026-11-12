import Foundation

/// Search logic shared by every pane of the Find window. All Scintilla access
/// happens on the main actor; directory search lives in `DirFinder`.
@MainActor
final class FindSession {
    private let store: DocumentStore
    private let settings: FindSettings

    /// Last zero-length match, so ^ / $ searches do not stand still.
    private var lastZeroMatch: (document: EditorDocument.ID, position: Int)?
    /// Fixed span for "In selection", captured on the first search.
    private var restrictedRange: (document: EditorDocument.ID, key: String, start: Int, end: Int)?

    init(store: DocumentStore, settings: FindSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    var activeDocument: EditorDocument? { store.activeDocument }
    var documents: [EditorDocument] { store.documents }

    // MARK: - Query construction

    func makeQuery(text: String,
                   replacement: String = "",
                   mode: SearchMode? = nil,
                   inSelectionOverride: Bool? = nil) -> SearchQuery {
        SearchQuery(text: text,
                    replacement: replacement,
                    mode: mode ?? settings.mode,
                    matchCase: settings.matchCase,
                    wholeWord: settings.wholeWord,
                    wrap: settings.wrap,
                    backward: settings.backward,
                    inSelection: inSelectionOverride ?? false)
    }

    // MARK: - Find

    func find(query: SearchQuery, forward: Bool) -> XEditorFindResult? {
        guard let doc = activeDocument else { return nil }
        let editor = doc.editor
        let needle = query.needleData
        guard !needle.isEmpty else {
            return XEditorFindResult(status: .notFound, wrapped: false, match: nil)
        }

        resetRestrictionIfNeeded(query: query, document: doc)

        if query.inSelection, let restricted = restrictedRange, restricted.document == doc.id {
            return findWithin(query: query, document: doc, range: restricted, forward: forward)
        }

        var start = forward ? editor.selectionEnd : editor.selectionStart
        if let zero = lastZeroMatch, zero.document == doc.id, zero.position == start {
            let advanced = forward
                ? editor.positionAfterPosition(start)
                : editor.positionBeforePosition(start)
            if advanced != start { start = advanced }
        }

        let result = editor.findBytes(needle,
                                      flags: query.flags,
                                      startPosition: start,
                                      forward: forward,
                                      wrap: query.wrap)
        recordZeroMatch(result.match, document: doc)
        if let match = result.match {
            editor.selectRange(start: match.start, end: match.end)
        }
        return result
    }

    private func findWithin(query: SearchQuery,
                            document: EditorDocument,
                            range: (document: EditorDocument.ID, key: String, start: Int, end: Int),
                            forward: Bool) -> XEditorFindResult? {
        let editor = document.editor
        let all = editor.findAllBytes(query.needleData,
                                      flags: query.flags,
                                      inStart: range.start,
                                      inEnd: range.end,
                                      maxCount: 0)
        if all.status == .invalidRegex {
            return XEditorFindResult(status: .invalidRegex, wrapped: false, match: nil)
        }
        let matches = all.matches
        guard !matches.isEmpty else {
            return XEditorFindResult(status: .notFound, wrapped: false, match: nil)
        }

        let selStart = editor.selectionStart
        let selEnd = editor.selectionEnd
        var picked: XEditorFindMatch?
        var wrapped = false
        if forward {
            picked = matches.first { $0.start >= selEnd }
            if picked == nil {
                picked = matches.first
                wrapped = true
            }
        } else {
            picked = matches.last { $0.end <= selStart }
            if picked == nil {
                picked = matches.last
                wrapped = true
            }
        }
        guard let match = picked else {
            return XEditorFindResult(status: .notFound, wrapped: false, match: nil)
        }
        recordZeroMatch(match, document: document)
        editor.selectRange(start: match.start, end: match.end)
        return XEditorFindResult(status: .ok, wrapped: wrapped, match: match)
    }

    private func resetRestrictionIfNeeded(query: SearchQuery, document: EditorDocument) {
        guard query.inSelection else {
            restrictedRange = nil
            return
        }
        let key = "\(query.text)|\(query.mode.rawValue)|\(query.matchCase)|\(query.wholeWord)"
        if let existing = restrictedRange, existing.document == document.id, existing.key == key {
            return
        }
        restrictedRange = (document.id, key, document.editor.selectionStart, document.editor.selectionEnd)
    }

    private func recordZeroMatch(_ match: XEditorFindMatch?, document: EditorDocument) {
        if let match, match.end == match.start {
            lastZeroMatch = (document.id, Int(match.start))
        } else {
            lastZeroMatch = nil
        }
    }

    // MARK: - Count / Find All

    func count(query: SearchQuery) -> XEditorCountResult? {
        guard let doc = activeDocument else { return nil }
        let (start, end) = currentRange(query: query, document: doc)
        return doc.editor.countBytes(query.needleData, flags: query.flags, inStart: start, inEnd: end)
    }

    func findAll(query: SearchQuery, document: EditorDocument, maxCount: Int) -> XEditorFindAllResult {
        let (start, end) = currentRange(query: query, document: document)
        return document.editor.findAllBytes(query.needleData,
                                            flags: query.flags,
                                            inStart: start,
                                            inEnd: end,
                                            maxCount: maxCount)
    }

    private func currentRange(query: SearchQuery, document: EditorDocument) -> (Int, Int) {
        guard query.inSelection else { return (0, -1) }
        if let restricted = restrictedRange, restricted.document == document.id {
            return (restricted.start, restricted.end)
        }
        return (document.editor.selectionStart, document.editor.selectionEnd)
    }

    /// Converts bridge matches into result rows for the results outline.
    func resultMatches(for document: EditorDocument,
                       matches: [XEditorFindMatch],
                       location: SearchResultLocation) -> [SearchResultMatch] {
        matches.map { match in
            let line = Int(match.line)
            let lineText = document.editor.lineText(line)
            let lineStart = Int(document.editor.lineStartPosition(line))
            let offset = max(0, Int(match.start) - lineStart)
            return SearchResultMatch(location: location,
                                     line: line,
                                     byteStart: Int(match.start),
                                     byteEnd: Int(match.end),
                                     preview: SearchResultsModel.preview(lineText: lineText,
                                                                        matchOffset: offset,
                                                                        limit: settings.resultPreviewLength,
                                                                        fullLine: settings.resultFullLine),
                                     revision: document.contentRevision)
        }
    }

    // MARK: - Replace

    func replaceCurrent(query: SearchQuery) -> XEditorReplaceResult? {
        guard let doc = activeDocument else { return nil }
        return doc.editor.replaceCurrentBytes(query.needleData,
                                              replacement: query.replacementData,
                                              flags: query.flags)
    }

    func replaceAll(query: SearchQuery, document: EditorDocument) -> XEditorReplaceResult {
        let (start, end) = currentRange(query: query, document: document)
        return document.editor.replaceAllBytes(query.needleData,
                                               replacement: query.replacementData,
                                               flags: query.flags,
                                               inStart: start,
                                               inEnd: end)
    }

    // MARK: - Marks

    func markAll(query: SearchQuery, colorIndex: Int, addBookmarks: Bool) -> XEditorCountResult? {
        guard let doc = activeDocument else { return nil }
        let indicator = 21 + max(0, min(4, colorIndex))
        let result = doc.editor.markAllBytes(query.needleData,
                                             flags: query.flags,
                                             indicator: indicator,
                                             maxCount: 200_000)

        if addBookmarks, result.status == .ok {
            let (start, end) = currentRange(query: query, document: doc)
            let all = doc.editor.findAllBytes(query.needleData,
                                              flags: query.flags,
                                              inStart: start,
                                              inEnd: end,
                                              maxCount: 200_000)
            var seenLines = Set<Int>()
            for match in all.matches where seenLines.insert(Int(match.line)).inserted {
                doc.editor.addBookmark(atLine: Int(match.line))
            }
        }
        return result
    }

    func clearMarks(all: Bool, colorIndex: Int) {
        guard let doc = activeDocument else { return }
        if all {
            doc.editor.clearAllMarkIndicators()
        } else {
            doc.editor.clearIndicatorRange(21 + max(0, min(4, colorIndex)))
        }
    }
}
