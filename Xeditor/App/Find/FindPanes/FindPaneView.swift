import AppKit

/// Find tab: a native search field, one row of options, and the window footer
/// with navigation and result actions.
final class FindPaneView: FindPaneBase {
    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: false, optionsVariant: .findReplace)

        let findAllCurrent = FindUI.footerButton("Find in Current File", target: self,
                                                 action: #selector(findAllCurrent))
        let findAllOpen = FindUI.footerButton("Find All in Open Documents", target: self,
                                              action: #selector(findAllOpen))
        let count = FindUI.footerButton("Count", target: self, action: #selector(countMatches))

        let previous = FindUI.footerButton("Find Previous", target: self, action: #selector(findPrevious))
        let next = FindUI.footerButton("Find Next", target: self, action: #selector(findNext), isDefault: true)

        setFooter(leading: [findAllCurrent, findAllOpen, count],
                  trailing: [previous, next])

        installCard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func findNext() { controller?.performFind(forward: true) }
    @objc private func findPrevious() { controller?.performFind(forward: false) }
    @objc private func countMatches() { controller?.performCount() }
    @objc private func findAllCurrent() { controller?.performFindAll(openDocuments: false) }
    @objc private func findAllOpen() { controller?.performFindAll(openDocuments: true) }
}
