import Foundation

/// Owns the open documents and the active tab.
@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var documents: [EditorDocument] = []
    @Published var activeID: EditorDocument.ID?

    var activeDocument: EditorDocument? {
        documents.first { $0.id == activeID }
    }

    init() {
        let document = EditorDocument()
        documents = [document]
        activeID = document.id
    }

    @discardableResult
    func newDocument() -> EditorDocument {
        let document = EditorDocument()
        documents.append(document)
        activeID = document.id
        return document
    }

    @discardableResult
    func open(url: URL) -> EditorDocument {
        let standardized = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url?.standardizedFileURL == standardized }) {
            activeID = existing.id
            return existing
        }

        let document = EditorDocument(url: url)
        if documents.count == 1,
           let placeholder = documents.first,
           placeholder.url == nil,
           !placeholder.isDirty,
           placeholder.isEmpty {
            documents = [document]
        } else {
            documents.append(document)
        }
        activeID = document.id
        return document
    }

    func close(_ document: EditorDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents.remove(at: index)

        if documents.isEmpty {
            newDocument()
        } else if activeID == document.id {
            let nextIndex = min(index, documents.count - 1)
            activeID = documents[nextIndex].id
            documents[nextIndex].updateCursorPosition()
        }
    }

    func select(_ document: EditorDocument) {
        activeID = document.id
        document.updateCursorPosition()
    }

    func selectTab(at index: Int) {
        guard documents.indices.contains(index) else { return }
        activeID = documents[index].id
        documents[index].updateCursorPosition()
    }

    func selectNext() {
        guard !documents.isEmpty else { return }
        guard let id = activeID, let index = documents.firstIndex(where: { $0.id == id }) else {
            activeID = documents.first?.id
            return
        }
        let nextIndex = (index + 1) % documents.count
        activeID = documents[nextIndex].id
        documents[nextIndex].updateCursorPosition()
    }

    func selectPrevious() {
        guard !documents.isEmpty else { return }
        guard let id = activeID, let index = documents.firstIndex(where: { $0.id == id }) else {
            activeID = documents.last?.id
            return
        }
        let prevIndex = (index - 1 + documents.count) % documents.count
        activeID = documents[prevIndex].id
        documents[prevIndex].updateCursorPosition()
    }

    /// Reorders a document tab from one position to another.
    func moveDocument(from sourceID: EditorDocument.ID, to destinationID: EditorDocument.ID) {
        guard sourceID != destinationID,
              let sourceIndex = documents.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = documents.firstIndex(where: { $0.id == destinationID }) else {
            return
        }
        let doc = documents.remove(at: sourceIndex)
        documents.insert(doc, at: destinationIndex)
    }
}
