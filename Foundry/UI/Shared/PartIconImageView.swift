import AppKit
import Observation

/// An AppKit part-icon tile: a tint-filled backing behind a white stencil
/// glyph, re-resolved whenever the view's effective appearance changes.
final class PartIconImageView: NSImageView {
    private var specification: PartIconSpecification?
    private var tileSize: NSSize?
    private var observationID = UUID()

    func configure(_ specification: PartIconSpecification?, tileSize: NSSize? = nil) {
        observationID = UUID()
        if self.specification?.cacheKey != specification?.cacheKey { image = nil }
        self.specification = specification
        self.tileSize = tileSize
        refreshIcon()
    }

    private func refreshIcon() {
        guard let specification else { return }
        let observationID = UUID()
        self.observationID = observationID
        withObservationTracking {
            if let tileSize {
                image = specification.tileImage(size: tileSize)
                contentTintColor = nil
            } else {
                let icon = specification.rowImage()
                if let preparedImage = icon.image { image = preparedImage }
                contentTintColor = icon.tint
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationID == observationID else { return }
                self.refreshIcon()
            }
        }
    }

    var tileBackground: NSColor? {
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
            backgroundColor = tileBackground?.cgColor
        }
        layer?.backgroundColor = backgroundColor
    }
}
