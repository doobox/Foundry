import Foundation

/// A palette-backed text colour inside rich text. Only the reference is
/// stored — resolution happens wherever the fragment renders, so palette
/// edits recolour existing text the same way they recolour parts.
nonisolated struct RichTextColourReference: Codable, Hashable, Sendable {
    var source: String
    var lightShade: ColourShade
    var darkShade: ColourShade

    var paletteID: String {
        ThemePaletteColorRole(rawValue: source) != nil ? "framework." + source : source
    }

    /// The stored `data-foundry-color` attribute value.
    var marker: String {
        "\(source):\(lightShade.rawValue):\(darkShade.rawValue)"
    }

    init(source: String, lightShade: ColourShade, darkShade: ColourShade) {
        self.source = source
        self.lightShade = lightShade
        self.darkShade = darkShade
    }

    init?(marker: String) {
        let parts = marker.split(separator: ":")
        guard parts.count == 3,
              let light = Int(parts[1]).flatMap(ColourShade.init(rawValue:)),
              let dark = Int(parts[2]).flatMap(ColourShade.init(rawValue:)),
              !parts[0].isEmpty else { return nil }
        self.init(source: String(parts[0]), lightShade: light, darkShade: dark)
    }

    /// Missing palettes stay unresolved; the text then inherits its part colour.
    func resolve(in palettes: [ColourPalette], appearance: SiteAppearance) -> String? {
        PaletteColourValue.palette(
            id: paletteID,
            selection: .shade(appearance == .light ? lightShade : darkShade)
        ).resolve(in: palettes)
    }

    func resolveCSS(in palettes: [ColourPalette], appearance: SiteAppearance) -> String? {
        palettes.resolvedPalette(id: paletteID)?.cssColour(at: appearance == .light ? lightShade : darkShade)
    }
}

/// Carries a `RichTextColourReference` through the modal editor's AttributedString.
nonisolated enum FoundryRichTextColourAttribute: CodableAttributedStringKey {
    typealias Value = RichTextColourReference
    static let name = "foundry.richTextColour"
}

nonisolated enum FoundryRichTextCodec {
    private static let prefix = "foundry-rich-text-v1:"
    private static let linkPrefix = "foundry-rich-link-v1:"

    static func storageValue(forHTMLFragment fragment: String) -> String {
        prefix + Data(fragment.utf8).base64EncodedString()
    }

    static func htmlFragment(from value: String) -> String? {
        guard value.hasPrefix(prefix),
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let fragment = String(data: data, encoding: .utf8) else { return nil }
        return fragment
    }

    static func isRichText(_ value: String) -> Bool {
        htmlFragment(from: value) != nil
    }

    static func URL(for link: PartLink) -> URL? {
        guard let data = try? JSONEncoder().encode(link) else { return nil }
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Foundation.URL(string: linkPrefix + payload)
    }

    static func partLink(from url: URL) -> PartLink {
        let value = url.absoluteString
        guard value.hasPrefix(linkPrefix) else {
            return PartLink(destination: .url(value))
        }
        var payload = String(value.dropFirst(linkPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let link = try? JSONDecoder().decode(PartLink.self, from: data) else {
            return PartLink(destination: .url(value))
        }
        return link
    }

    static func resolvingLinks(in fragment: String, context: LinkContext) -> String {
        let expression = try! NSRegularExpression(pattern: #"<a\s+href=\"([^\"]+)\">"#, options: [.caseInsensitive])
        var result = fragment
        let matches = expression.matches(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result),
                  let url = Foundation.URL(string: String(result[valueRange])),
                  url.absoluteString.hasPrefix(linkPrefix) else { continue }
            let link = partLink(from: url)
            let resolved = PartLinkResolver.resolve(
                link,
                pages: context.pages,
                folders: context.folders,
                assets: context.assets,
                assetLibrary: context.assetLibrary,
                publicURL: context.publicURL,
                absoluteURL: context.absoluteURL
            )
            var attributes = [#"href="\#(escapeAttribute(resolved.href))""#]
            if !resolved.target.isEmpty {
                attributes.append(#"target="\#(escapeAttribute(resolved.target))""#)
            }
            if !resolved.attributes.isEmpty {
                attributes.append(resolved.attributes)
            }
            result.replaceSubrange(wholeRange, with: "<a \(attributes.joined(separator: " "))>")
        }
        return result
    }

    /// Replaces stored palette references with concrete CSS colours. The
    /// canvas passes its single appearance; export passes the site's mode so
    /// dual-appearance sites get `light-dark()` colours, matching parts.
    static func resolvingColours(in fragment: String, context: ColourContext) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"<span\s+data-foundry-color=\"([^\"]*)\"\s*>"#,
            options: [.caseInsensitive]
        )
        var result = fragment
        let matches = expression.matches(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let reference = RichTextColourReference(marker: String(result[valueRange]))
            guard let reference,
                  let light = reference.resolveCSS(in: context.palettes, appearance: .light),
                  let dark = reference.resolveCSS(in: context.palettes, appearance: .dark) else {
                // A deleted palette inherits the surrounding colour rather than
                // guessing; the reference survives in the project for re-editing.
                result.replaceSubrange(wholeRange, with: "<span>")
                continue
            }
            result.replaceSubrange(
                wholeRange,
                with: "<span style=\"color:\(context.mode.colour(light: light, dark: dark))\">"
            )
        }
        return result
    }

    struct ColourContext: Sendable {
        let palettes: [ColourPalette]
        let mode: SiteAppearanceMode
    }

    struct LinkContext: Sendable {
        let pages: [Page]
        let folders: [PageFolder]
        let assets: [ProjectAsset]
        let assetLibrary: [ProjectAssetNode]?
        let publicURL: String
        let absoluteURL: Bool
    }

    private static func escapeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
