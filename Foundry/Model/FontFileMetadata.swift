import Foundation
import CoreText
import CryptoKit

/// Inspects font bytes without registering the font with the process or system.
nonisolated struct FontFileMetadata: Equatable, Sendable {
    let family: String
    let face: String
    let weight: Int
    let maximumWeight: Int
    let italic: Bool

    var cssWeight: String { weight == maximumWeight ? "\(weight)" : "\(weight) \(maximumWeight)" }
    var cssStyle: String { italic ? "italic" : "normal" }
    var summary: String { "\(face) · \(cssWeight)\(italic ? " · Italic" : "")" }

    func belongsToSameFamily(as other: Self) -> Bool {
        family.compare(other.family, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private final class Entry: NSObject {
        let value: FontFileMetadata?
        init(_ value: FontFileMetadata?) { self.value = value }
    }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 256
        return cache
    }()

    static func read(_ data: Data) -> Self? {
        read(data, digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    static func read(_ content: ProjectAssetContent) -> Self? {
        read(content.data, digest: content.digest ?? content.asset.contentDigest)
    }

    private static func read(_ data: Data, digest: String) -> Self? {
        let key = digest as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let value = inspect(data)
        cache.setObject(Entry(value), forKey: key)
        return value
    }

    private static func inspect(_ data: Data) -> Self? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let family = CTFontCopyFamilyName(font) as String
        guard !family.isEmpty else { return nil }
        // Variable fonts can report a descriptor for every named instance.
        // Descriptor count is not the number of independent font families.
        guard descriptors.allSatisfy({ descriptor in
            let candidate = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
            return family.compare(CTFontCopyFamilyName(candidate) as String, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] ?? []
        // Font collections need per-face source selection; don't mistake those
        // for the named instances of a single variable face.
        guard descriptors.count == 1 || !axes.isEmpty else { return nil }
        let face = axes.isEmpty ? ((CTFontCopyName(font, kCTFontSubFamilyNameKey) as String?) ?? "Regular") : "Variable"
        let italic = CTFontGetSymbolicTraits(font).contains(.traitItalic)
        var weight = 400
        if let table = CTFontCopyTable(font, CTFontTableTag(0x4F532F32), []) as Data?, table.count >= 6 {
            weight = min(1000, max(1, Int(table[4]) * 256 + Int(table[5])))
        }
        var maximumWeight = weight
        if let axis = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == 0x77676874 }),
           let minimum = axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber,
           let maximum = axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber {
            weight = max(1, min(1000, minimum.intValue))
            maximumWeight = max(weight, min(1000, maximum.intValue))
        }
        return Self(family: family, face: face, weight: weight, maximumWeight: maximumWeight, italic: italic)
    }
}
