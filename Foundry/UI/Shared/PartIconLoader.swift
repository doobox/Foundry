import AppKit
import Foundation
import Synchronization

nonisolated struct LoadedPartIcon: @unchecked Sendable {
    let image: NSImage
}

extension PartIconColour {
    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            let rgba = hex.count == 9 ? value : (value << 8) | 255
            return NSColor(srgbRed: CGFloat((rgba >> 24) & 255) / 255,
                           green: CGFloat((rgba >> 16) & 255) / 255,
                           blue: CGFloat((rgba >> 8) & 255) / 255,
                           alpha: CGFloat(rgba & 255) / 255)
        }
    }
}

extension PartType {
    /// The icon recipe for any part type: package parts resolve their
    /// manifest's `icon`; everything else stencils its system symbol in the
    /// neutral tint.
    var iconSpecification: PartIconSpecification {
        definition.package?.iconSpecification
            ?? .init(glyph: .symbol(systemImage))
    }
}

extension PartIconSpecification {
    /// The glyph as a template image, synchronously: SVG stencils come from
    /// the icon cache — loaded and seeded on first use — and symbols come
    /// from the system, with unknown names falling back to the generic mark.
    func resolvedGlyphImage() -> NSImage? {
        switch glyph {
        case .svg(let url):
            return PartIconLoader.loadNow(at: url)?.image
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: PartDefinition.genericSystemImage, accessibilityDescription: nil)
        }
    }

    /// The glyph for a structure-tree row, which has no tile behind it.
    /// Original SVG colours survive unless an explicit Structure colour
    /// requests a tinted silhouette. Both use the same padded geometry.
    func rowImage() -> (image: NSImage?, tint: NSColor?) {
        let tint = (structure ?? background).nsColor
        guard let source = resolvedGlyphImage() else { return (nil, tint) }
        guard case .svg = glyph else { return (source, tint) }
        let usesOriginal = rendering == .original && structure == nil
        // Copy before changing the template flag; the cache is shared.
        guard let artwork = source.copy() as? NSImage else { return (nil, tint) }
        if usesOriginal { artwork.isTemplate = false }
        // Match the row's 14-point symbol configuration without filling its
        // entire 18-point image slot. Preserve the SVG's aspect ratio.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard source.size.width > 0, source.size.height > 0 else { return true }
            let box = rect.insetBy(dx: rect.width / 9, dy: rect.height / 9)
            artwork.draw(in: Self.fitted(source.size, in: box), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = !usesOriginal
        return (image, usesOriginal ? nil : tint)
    }

    /// The complete tile. Monochrome draws the foreground over the background
    /// rounded rectangle; original SVG artwork keeps its authored colours.
    /// SVG viewBoxes are tight artwork bounds; SF Symbols include optical
    /// padding. Give SVGs a smaller box to match their visible size.
    /// The drawing handler resolves colours for each appearance.
    func tileImage(size: NSSize) -> NSImage {
        let backgroundColor = background.nsColor
        let foregroundColor = foreground.nsColor
        let rendering = rendering
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
            if rendering == .original {
                let original = source.copy() as? NSImage
                original?.isTemplate = false
                return original
            }
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

actor PartIconLoader {
    static let shared = PartIconLoader()

    private nonisolated static let cache = Mutex<[URL: LoadedPartIcon]>([:])

    nonisolated static func cachedIcon(at sourceURL: URL) -> LoadedPartIcon? {
        let url = sourceURL.standardizedFileURL
        return cache.withLock { $0[url] }
    }

    /// Loads a glyph synchronously, seeding the shared cache. Glyph files
    /// are capped at 64 KiB so the one-time read is negligible.
    nonisolated static func loadNow(at sourceURL: URL) -> LoadedPartIcon? {
        let url = sourceURL.standardizedFileURL
        if let cached = cachedIcon(at: url) { return cached }
        guard let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              byteCount <= PartPackageValidator.maximumIconByteCount,
              let image = NSImage(contentsOf: url) else { return nil }
        // Glyphs are stencils: only the artwork's alpha matters, and the
        // template flag lets every surface tint the shape as it draws.
        image.isTemplate = true
        let loaded = LoadedPartIcon(image: image)
        return cache.withLock { cache in
            if let cached = cache[url] { return cached }
            cache[url] = loaded
            return loaded
        }
    }

    func icon(at sourceURL: URL) -> LoadedPartIcon? {
        Self.loadNow(at: sourceURL)
    }

    func removeIcon(at sourceURL: URL) {
        _ = Self.cache.withLock { cache in
            cache.removeValue(forKey: sourceURL.standardizedFileURL)
        }
    }

    /// Drops every cached glyph inside a package root — used when a pack
    /// reloads and its icon file may have changed or moved.
    func removeIcons(underRoot rootURL: URL) {
        let prefix = rootURL.standardizedFileURL.path + "/"
        Self.cache.withLock { cache in
            cache = cache.filter { !$0.key.path.hasPrefix(prefix) }
        }
    }

    func removeAll() {
        Self.cache.withLock { $0.removeAll() }
    }
}
