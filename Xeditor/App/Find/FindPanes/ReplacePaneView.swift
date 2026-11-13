import AppKit

/// Replace tab: find and replace one match, replace in the current file or in
/// the selection, and replace across open documents.
final class ReplacePaneView: FindPaneBase {
    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: true, optionsVariant: .findReplace)

        let replaceSelection = FindUI.footerButton("Selection", target: self,
                                                   action: #selector(replaceInSelection),
                                                   toolTip: "Replace all matches in the selection")
        let replaceHere = FindUI.footerButton("Current File", target: self,
                                              action: #selector(replaceAllHere),
                                              toolTip: "Replace all matches in the current file")
        let replaceOpen = FindUI.footerButton("Open Files", target: self,
                                              action: #selector(replaceAllOpen),
                                              toolTip: "Replace all matches in all open documents")
        let next = FindUI.footerButton("Find Next", target: self, action: #selector(findNext),
                                       toolTip: "Find the next match")
        let replace = FindUI.footerButton("Replace", target: self, action: #selector(replaceCurrent),
                                          isDefault: true, toolTip: "Replace the current match")

        setFooter(leading: [FindUI.inlineLabel("Replace All in"), replaceSelection, replaceHere, replaceOpen],
                  trailing: [next, replace])

        installCard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func findNext() { controller?.performFind(forward: true) }
    @objc private func replaceCurrent() { controller?.performReplace() }
    @objc private func replaceAllHere() { controller?.performReplaceAll(openDocuments: false) }
    @objc private func replaceInSelection() { controller?.performReplaceAllInSelection() }
    @objc private func replaceAllOpen() { controller?.performReplaceAll(openDocuments: true) }
}
