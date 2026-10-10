import AppKit

/// An AppKit part-icon tile: a tint-filled backing behind a white stencil
/// glyph, re-resolved whenever the view's effective appearance changes.
final class PartIconImageView: NSImageView {
    var tileTint: NSColor? {
        didSet { updateBackgroundColor() }
    }

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
            backgroundColor = tileTint?.cgColor
        }
        layer?.backgroundColor = backgroundColor
    }
}
