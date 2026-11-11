import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let mainVC: MainViewController

    init(store: DocumentStore) {
        self.mainVC = MainViewController(store: store)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 920, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.setFrameAutosaveName("XeditorMainWindow")
        window.tabbingMode = .disallowed
        window.contentViewController = mainVC

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        for doc in mainVC.store.documents {
            if doc.isDirty {
                mainVC.closeDocumentWithConfirmation(doc)
                if mainVC.store.documents.contains(where: { $0.id == doc.id }) {
                    return false
                }
            }
        }
        return true
    }
}
