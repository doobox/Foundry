import Foundation

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

    static func URL(for link: BlockLink) -> URL? {
        guard let data = try? JSONEncoder().encode(link) else { return nil }
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Foundation.URL(string: linkPrefix + payload)
    }

    static func blockLink(from url: URL) -> BlockLink {
        let value = url.absoluteString
        guard value.hasPrefix(linkPrefix) else {
            return BlockLink(destination: .url(value))
        }
        var payload = String(value.dropFirst(linkPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let link = try? JSONDecoder().decode(BlockLink.self, from: data) else {
            return BlockLink(destination: .url(value))
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
            let link = blockLink(from: url)
            let resolved = BlockLinkResolver.resolve(
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
