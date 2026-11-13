import AppKit

/// Find tab: a native search field, one row of options, and the window footer
/// with navigation and result actions.
final class FindPaneView: FindPaneBase {
    init(controller: FindWindowController) {
        super.init(controller: controller, showsReplacement: false, optionsVariant: .findReplace)

        let findAllCurrent = FindUI.footerButton("Current File", target: self,
                                                 action: #selector(findAllCurrent),
                                                 toolTip: "Find all matches in the current file")
        let findAllOpen = FindUI.footerButton("Open Files", target: self,
                                              action: #selector(findAllOpen),
                                              toolTip: "Find all matches in all open documents")
        let count = FindUI.footerButton("Count", target: self, action: #selector(countMatches),
                                        toolTip: "Count matches")

        let previous = FindUI.footerButton("Find Previous", target: self, action: #selector(findPrevious),
                                           toolTip: "Find the previous match (Shift-Return)")
        let next = FindUI.footerButton("Find Next", target: self, action: #selector(findNext),
                                       isDefault: true, toolTip: "Find the next match (Return)")

        setFooter(leading: [FindUI.inlineLabel("Find All in"), findAllCurrent, findAllOpen, count],
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
