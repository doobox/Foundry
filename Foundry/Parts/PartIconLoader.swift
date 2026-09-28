import AppKit
import Foundation
import Synchronization

nonisolated struct LoadedPartIcon: @unchecked Sendable {
    let image: NSImage
}

extension PartIconTint {
    /// The macOS system colour behind each token — appearance-adaptive, so
    /// no icon needs a dark variant.
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }
}

extension PartType {
    /// The icon recipe for any part type: package parts resolve their
    /// manifest's `icon`; everything else stencils its system symbol in the
    /// neutral tint.
    var iconSpecification: PartIconSpecification {
        definition.package?.iconSpecification
            ?? .init(glyph: .symbol(systemImage), tint: .gray)
    }
}

extension PartIconSpecification {
    /// The tint with its shade applied. Shades blend the system colour with
    /// white or black as it resolves for each appearance, so they adapt to
    /// light and dark just as the system colours do.
    var color: NSColor {
        let base = tint.nsColor
        guard shade != .regular else { return base }
        let shade = shade
        return NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance {
                resolved = base.usingColorSpace(.sRGB) ?? base
            }
            return shade == .light
                ? resolved.blended(withFraction: 0.4, of: .white) ?? resolved
                : resolved.blended(withFraction: 0.35, of: .black) ?? resolved
        }
    }

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
    /// Monochrome glyphs come back as templates for the row to paint in
    /// `tint` — always the base colour, never a shade, so the tree stays
    /// consistent. Original artwork shows as authored, so `tint` is nil.
    func rowImage() -> (image: NSImage?, tint: NSColor?) {
        let glyph = resolvedGlyphImage()
        switch rendering {
        case .monochrome:
            return (glyph, tint.nsColor)
        case .original:
            let original = glyph?.copy() as? NSImage
            original?.isTemplate = false
            return (original, nil)
        }
    }

    /// The complete tile. Monochrome draws a white glyph on a tint-filled
    /// rounded rectangle; original SVG artwork fills the tile as drawn, with
    /// no backdrop. Monochrome glyphs aspect-fit the same padded box (20% of
    /// the tile height per side), so SVGs and symbols render at the same
    /// size. The drawing handler runs per draw, so the tint follows
    /// appearance changes.
    func tileImage(size: NSSize) -> NSImage {
        let tintColor = color
        let rendering = rendering
        if rendering == .original {
            let artwork = resolvedGlyphImage()
            return NSImage(size: size, flipped: false) { rect in
                guard let artwork, artwork.size.width > 0, artwork.size.height > 0 else { return true }
                artwork.draw(in: Self.fitted(artwork.size, in: rect), from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
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
                NSColor.white.setFill()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        return NSImage(size: size, flipped: false) { rect in
            let radius = rect.height * 0.16
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            tintColor.setFill()
            rect.fill()
            guard let glyphImage else { return true }
            let inset = rect.height * 0.2
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
