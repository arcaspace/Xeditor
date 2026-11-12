import AppKit

/// Replace tab: find and replace one match, replace in the current file or in
/// the selection, and replace across open documents.
final class ReplacePaneView: FindPaneBase {
    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: true, optionsVariant: .findReplace)

        let replaceSelection = FindUI.footerButton("Replace in Selection", target: self,
                                                   action: #selector(replaceInSelection))
        let replaceHere = FindUI.footerButton("Replace in Current File", target: self,
                                              action: #selector(replaceAllHere))
        let replaceOpen = FindUI.footerButton("Replace All in Open Documents", target: self,
                                              action: #selector(replaceAllOpen))
        let next = FindUI.footerButton("Find Next", target: self, action: #selector(findNext))
        let replace = FindUI.footerButton("Replace", target: self, action: #selector(replaceCurrent),
                                          isDefault: true)

        setFooter(leading: [replaceSelection, replaceHere, replaceOpen],
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
