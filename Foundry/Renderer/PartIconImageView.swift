import AppKit

/// An AppKit part icon whose backing follows the view's effective appearance.
final class PartIconImageView: NSImageView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundColor()
    }

    func updateBackgroundColor() {
        var backgroundColor: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
        layer?.backgroundColor = backgroundColor
    }
}
