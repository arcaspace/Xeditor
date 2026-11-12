import AppKit

/// Find tab: a wide two-column pane with navigation actions on the right.
final class FindPaneView: FindPaneBase {
    private let settings = FindSettings.shared
    private let transparencyBox: NSButton
    private let focusRadio: NSButton
    private let alwaysRadio: NSButton
    private let opacitySlider = NSSlider()

    init(controller: FindWindowController) {
        transparencyBox = FindUI.checkbox("Transparent window",
                                          target: nil, action: nil,
                                          on: FindSettings.shared.opacityEnabled)
        focusRadio = FindUI.radio("When unfocused",
                                  target: nil, action: nil,
                                  on: !FindSettings.shared.opacityAlways)
        alwaysRadio = FindUI.radio("Always",
                                   target: nil, action: nil,
                                   on: FindSettings.shared.opacityAlways)

        super.init(controller: controller, showsReplacement: false, optionsVariant: .findReplace)

        let next = FindUI.actionButton("Find Next", target: self, action: #selector(findNext))
        next.keyEquivalent = "\r"
        let previous = FindUI.actionButton("Find Previous", target: self, action: #selector(findPrevious))
        let count = FindUI.actionButton("Count Matches", target: self, action: #selector(countMatches))
        let findInFile = FindUI.actionButton("Find in Current File", target: self, action: #selector(findAllCurrent))
        let gap = NSView()
        gap.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let findAllOpen = FindUI.actionButton("Find All in Open Documents", target: self, action: #selector(findAllOpen))
        let copyMatches = FindUI.actionButton("Copy Matched Text", target: self, action: #selector(copyMatches))
        let clearResults = FindUI.actionButton("Clear Results", target: self, action: #selector(clearResults))
        let close = FindUI.actionButton("Close", target: self, action: #selector(closePanel))

        let left = FindUI.vertical([searchRow(), flexibleSpacer(), optionsAndTransparency()], spacing: 16)

        install(left: left,
                rightViews: [next, previous, count, findInFile, gap,
                             findAllOpen, copyMatches, clearResults, close])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func optionsAndTransparency() -> NSStackView {
        transparencyBox.target = self
        transparencyBox.action = #selector(opacityToggled)
        focusRadio.target = self
        focusRadio.action = #selector(opacityModeChanged)
        alwaysRadio.target = self
        alwaysRadio.action = #selector(opacityModeChanged)
        opacitySlider.minValue = 0.35
        opacitySlider.maxValue = 1
        opacitySlider.doubleValue = settings.opacity
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged)
        opacitySlider.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let sliderRow = FindUI.horizontal([FindUI.label("Opacity:"), opacitySlider], spacing: 6)
        sliderRow.arrangedSubviews.first?.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let transparencyGroup = FindUI.group("Transparency", [transparencyBox,
                                                               focusRadio,
                                                               alwaysRadio,
                                                               sliderRow])
        updateTransparencyControls()

        let row = NSStackView(views: [optionsView, transparencyGroup])
        row.orientation = .horizontal
        row.spacing = 16
        row.alignment = .top
        row.distribution = .fillEqually
        return row
    }

    private func updateTransparencyControls() {
        let enabled = transparencyBox.state == .on
        focusRadio.isEnabled = enabled
        alwaysRadio.isEnabled = enabled
        opacitySlider.isEnabled = enabled
    }

    @objc private func opacityToggled() {
        settings.opacityEnabled = transparencyBox.state == .on
        updateTransparencyControls()
        controller?.applyOpacity()
    }

    @objc private func opacityModeChanged() {
        settings.opacityAlways = alwaysRadio.state == .on
        focusRadio.state = alwaysRadio.state == .on ? .off : .on
        controller?.applyOpacity()
    }

    @objc private func opacitySliderChanged() {
        settings.opacity = opacitySlider.doubleValue
        controller?.applyOpacity()
    }

    @objc private func findNext() { controller?.performFind(forward: true) }
    @objc private func findPrevious() { controller?.performFind(forward: false) }
    @objc private func countMatches() { controller?.performCount() }
    @objc private func findAllCurrent() { controller?.performFindAll(openDocuments: false) }
    @objc private func findAllOpen() { controller?.performFindAll(openDocuments: true) }
    @objc private func copyMatches() { controller?.copyMatchedText() }
    @objc private func clearResults() { controller?.clearResults() }
    @objc private func closePanel() { controller?.closePanel() }
}
