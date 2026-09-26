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

    /// The complete tile: a tint-filled rounded rectangle behind the glyph
    /// in white. Both glyph kinds — SVG stencils and SF Symbols — aspect-fit
    /// the same padded box (20% of the tile height per side), so neither
    /// type ever renders larger than the other. The drawing handler runs per
    /// draw, so the system tint follows appearance changes.
    func tileImage(size: NSSize) -> NSImage {
        let tintColor = tint.nsColor
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
        let whiteGlyph: NSImage? = glyphSource.flatMap { source in
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
            guard let whiteGlyph else { return true }
            let inset = rect.height * 0.2
            let box = rect.insetBy(dx: inset, dy: inset)
            let scale = min(box.width / whiteGlyph.size.width, box.height / whiteGlyph.size.height)
            let drawSize = NSSize(
                width: whiteGlyph.size.width * scale,
                height: whiteGlyph.size.height * scale
            )
            let glyphRect = NSRect(
                x: box.midX - drawSize.width / 2,
                y: box.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            whiteGlyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
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
