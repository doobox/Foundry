import AppKit
import Testing
@testable import Foundry

@MainActor
struct ProportionalSplitViewTests {
    @Test
    func splitRestoresItsPreferredRatioAfterBeingConstrainedByMinimumWidth() {
        let splitView = RatioSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        splitView.isVertical = true
        splitView.preferredLeadingRatio = 0.3
        splitView.minimumLeadingWidth = 180
        splitView.minimumTrailingWidth = 300
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.adjustSubviews()
        splitView.layoutSubtreeIfNeeded()

        let preferredWidth = (splitView.bounds.width - splitView.dividerThickness) * 0.3
        #expect(abs(splitView.subviews[0].frame.width - preferredWidth) < 1)

        splitView.setFrameSize(NSSize(width: 560, height: 600))
        splitView.layoutSubtreeIfNeeded()
        #expect(abs(splitView.subviews[0].frame.width - 180) < 2)

        splitView.setFrameSize(NSSize(width: 1_000, height: 600))
        splitView.layoutSubtreeIfNeeded()
        let restoredWidth = (splitView.bounds.width - splitView.dividerThickness) * 0.3
        #expect(abs(splitView.subviews[0].frame.width - restoredWidth) < 1)
    }
}
