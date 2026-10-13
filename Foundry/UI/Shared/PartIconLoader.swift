import AppKit
import Foundation
import Observation

struct LoadedPartIcon {
    let image: NSImage
}

extension PartType {
    /// The icon recipe for any part type: package parts resolve their
    /// manifest's `icon`; everything else uses its symbol and group palette.
    var iconSpecification: PartIconSpecification {
        definition.package?.iconSpecification
            ?? .init(glyph: .symbol(systemImage), group: definition.category.rawValue)
    }
}

extension PartIconSpecification {
    /// SVGs are cache-only here; a miss schedules background preparation.
    /// Observing views refresh when the prepared bitmap becomes available.
    func resolvedGlyphImage() -> NSImage? {
        switch glyph {
        case .svg(let url):
            return PartIconLoader.shared.requestIcon(at: url)?.image
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: PartDefinition.genericSystemImage, accessibilityDescription: nil)
        }
    }

    /// The glyph for a structure-tree row, which has no tile behind it.
    /// Always uses the base group colour.
    func rowImage() -> (image: NSImage?, tint: NSColor?) {
        let tint = groupColour
        guard let source = resolvedGlyphImage() else { return (nil, tint) }
        guard case .svg = glyph else { return (source, tint) }
        // Copy before changing the template flag; the cache is shared.
        guard let artwork = source.copy() as? NSImage else { return (nil, tint) }
        artwork.isTemplate = false
        // Match the row's 14-point symbol configuration without filling its
        // entire 18-point image slot. Preserve the SVG's aspect ratio.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard source.size.width > 0, source.size.height > 0 else { return true }
            let box = rect.insetBy(dx: rect.width / 9, dy: rect.height / 9)
            artwork.draw(in: Self.fitted(source.size, in: box), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return (image, tint)
    }

    /// The complete tile. Monochrome draws the foreground over the background
    /// rounded rectangle; every SVG is a monochrome stencil.
    /// SVG viewBoxes are tight artwork bounds; SF Symbols include optical
    /// padding. Give SVGs a smaller box to match their visible size.
    /// The drawing handler resolves colours for each appearance.
    func tileImage(size: NSSize) -> NSImage {
        let backgroundColor = tileBackgroundColour
        let foregroundColor = tileForegroundColour
        let insetFraction: CGFloat
        switch glyph {
        case .svg: insetFraction = 0.25
        case .symbol: insetFraction = 0.2
        }
        let glyphSource: NSImage? = {
            switch glyph {
            case .svg:
                return resolvedGlyphImage()
            case .symbol:
                // Rasterise generously, then fit down — crisp at any tile size.
                return resolvedGlyphImage()?.withSymbolConfiguration(
                    .init(pointSize: 256, weight: .medium)
                )
            }
        }()
        // Tint the glyph alone first: filling atop inside the tile would
        // recolour the backdrop as well as the stencil.
        let glyphImage: NSImage? = glyphSource.flatMap { source in
            guard source.size.width > 0, source.size.height > 0 else { return nil }
            return NSImage(size: source.size, flipped: false) { rect in
                source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                foregroundColor.setFill()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        return NSImage(size: size, flipped: false) { rect in
            let radius = rect.height * 0.16
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            backgroundColor.setFill()
            rect.fill()
            guard let glyphImage else { return true }
            let inset = rect.height * insetFraction
            let box = rect.insetBy(dx: inset, dy: inset)
            glyphImage.draw(in: Self.fitted(glyphImage.size, in: box), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// `size` scaled to fit `box`, centred.
    private static func fitted(_ size: NSSize, in box: NSRect) -> NSRect {
        let scale = min(box.width / size.width, box.height / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: box.midX - drawSize.width / 2,
            y: box.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}

@MainActor
@Observable
final class PartIconLoader {
    static let shared = PartIconLoader()

    private var cache: [URL: LoadedPartIcon] = [:]
    @ObservationIgnored private var pending: [URL: (id: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var failed: Set<URL> = []

    static func cachedIcon(at sourceURL: URL) -> LoadedPartIcon? {
        shared.cache[sourceURL.standardizedFileURL]
    }

    func requestIcon(at sourceURL: URL) -> LoadedPartIcon? {
        let url = sourceURL.standardizedFileURL
        if let cached = cache[url] { return cached }
        guard pending[url] == nil, !failed.contains(url) else { return nil }
        let id = UUID()
        let task = Task {
            let bitmap = await Self.prepareBitmap(at: url)
            // A development reload can invalidate this URL while decoding.
            guard !Task.isCancelled, pending[url]?.id == id else { return }
            pending[url] = nil
            if let bitmap, let image = NSImage(data: bitmap) {
                image.isTemplate = true
                cache[url] = LoadedPartIcon(image: image)
            } else {
                failed.insert(url)
            }
        }
        pending[url] = (id, task)
        return nil
    }

    func icon(at sourceURL: URL) async -> LoadedPartIcon? {
        let url = sourceURL.standardizedFileURL
        if let icon = requestIcon(at: url) { return icon }
        await pending[url]?.task.value
        return cache[url]
    }

    func removeIcon(at sourceURL: URL) {
        let url = sourceURL.standardizedFileURL
        pending.removeValue(forKey: url)?.task.cancel()
        failed.remove(url)
        cache.removeValue(forKey: url)
    }

    /// Drops every cached glyph inside a package root — used when a pack
    /// reloads and its icon file may have changed or moved.
    func removeIcons(underRoot rootURL: URL) {
        let prefix = rootURL.standardizedFileURL.path + "/"
        for url in Set(cache.keys).union(pending.keys).union(failed) where url.path.hasPrefix(prefix) {
            removeIcon(at: url)
        }
    }

    func removeAll() {
        for entry in pending.values { entry.task.cancel() }
        pending.removeAll()
        failed.removeAll()
        cache.removeAll()
    }

    /// Rasterize SVGs off the main actor so AppKit's SVG decoder is never
    /// entered by row drawing. Only immutable PNG bytes cross back to the UI.
    @concurrent
    private static func prepareBitmap(at url: URL) async -> Data? {
        guard !Task.isCancelled,
              let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount <= PartPackageValidator.maximumIconByteCount,
              let source = NSImage(contentsOf: url),
              source.size.width > 0, source.size.height > 0 else { return nil }
        let scale = 256 / max(source.size.width, source.size.height)
        let width = max(1, Int((source.size.width * scale).rounded()))
        let height = max(1, Int((source.size.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                    from: .zero, operation: .copy, fraction: 1)
        guard !Task.isCancelled else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
