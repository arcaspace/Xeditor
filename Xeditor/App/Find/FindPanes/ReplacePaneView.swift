import AppKit

/// Replace tab: find, replace one match, replace in the current file or in
/// the selection, and replace across open documents.
final class ReplacePaneView: FindPaneBase {
    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: true, optionsVariant: .findReplace)

        let next = FindUI.actionButton("Find Next", target: self, action: #selector(findNext))
        next.keyEquivalent = "\r"
        let replace = FindUI.actionButton("Replace", target: self, action: #selector(replaceCurrent))
        let gap = NSView()
        gap.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let replaceAll = FindUI.actionButton("Replace in Current File", target: self, action: #selector(replaceAllHere))
        let replaceSelection = FindUI.actionButton("Replace in Selection", target: self, action: #selector(replaceInSelection))
        let gap2 = NSView()
        gap2.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let replaceAllOpen = FindUI.actionButton("Replace All in Open Documents", target: self, action: #selector(replaceAllOpen))
        let close = FindUI.actionButton("Close", target: self, action: #selector(closePanel))

        let fields = FindUI.vertical([searchRow(), replacementRow(), flexibleSpacer(), optionsView], spacing: 16)
        install(left: fields,
                rightViews: [next, replace, gap, replaceAll, replaceSelection, gap2,
                             replaceAllOpen, close])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func findNext() { controller?.performFind(forward: true) }
    @objc private func replaceCurrent() { controller?.performReplace() }
    @objc private func replaceAllHere() { controller?.performReplaceAll(openDocuments: false) }
    @objc private func replaceInSelection() { controller?.performReplaceAllInSelection() }
    @objc private func replaceAllOpen() { controller?.performReplaceAll(openDocuments: true) }
    @objc private func closePanel() { controller?.closePanel() }
}
