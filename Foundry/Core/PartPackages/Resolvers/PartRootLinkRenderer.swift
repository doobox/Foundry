import Foundation

/// Converts only the outer tag. Children and developer markup remain intact.
nonisolated enum PartRootLinkRenderer {
    static let blockTags: Set<String> = [
        "div", "section", "article", "header", "footer", "nav", "aside", "main",
        "figure", "figcaption", "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "address", "blockquote", "pre"
    ]
    static let allowedTags = blockTags.union([
        "span", "em", "strong", "small", "b", "i", "u", "s", "mark", "code",
        "kbd", "samp", "var", "sub", "sup", "abbr", "cite", "q", "time"
    ])

    static func root(in html: String) -> PartHTMLTag? {
        guard let start = html.indexAfterPartTemplateTrivia(from: html.startIndex) else { return nil }
        return html.partHTMLTag(at: start)
    }

    /// Tokenize actual tags, skipping comments and raw text. In particular,
    /// tag-like text inside scripts and quoted attributes is not markup.
    static func tags(in html: String, from start: String.Index) -> [PartHTMLTag] {
        var result: [PartHTMLTag] = []
        var cursor = start
        while cursor < html.endIndex, let next = html[cursor...].firstIndex(of: "<") {
            if html[next...].hasPrefix("<!--") {
                guard let end = html.range(of: "-->", range: next..<html.endIndex) else { break }
                cursor = end.upperBound
                continue
            }
            guard let tag = html.partHTMLTag(at: next) else {
                cursor = html.index(after: next)
                continue
            }
            result.append(tag)
            cursor = tag.range.upperBound
            if !tag.isClosing, ["script", "style", "textarea", "title"].contains(tag.name),
               let closing = html.range(of: "</\(tag.name)", options: .caseInsensitive, range: cursor..<html.endIndex) {
                cursor = closing.lowerBound
            }
        }
        return result
    }

    private static let attributePattern = #"([^\s=/>]+)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?"#

    private static func attributes(_ tag: PartHTMLTag, in html: String) -> [(name: String, text: String)] {
        let body = String(html[tag.range].dropFirst().dropLast())
        let regex = try! NSRegularExpression(pattern: attributePattern)
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).dropFirst().map {
            (String(body[Range($0.range(at: 1), in: body)!]).lowercased(),
             String(body[Range($0.range, in: body)!]))
        }
    }

    static func hasInteractiveChildren(_ html: String) -> Bool {
        guard let root = root(in: html) else { return false }
        return tags(in: html, from: root.range.upperBound).contains { tag in
            guard !tag.isClosing else { return false }
            let names = Set(attributes(tag, in: html).map(\.name))
            return ["a", "button", "input", "select", "textarea", "details", "summary", "iframe", "embed", "label"].contains(tag.name)
                || names.contains("tabindex") || names.contains("contenteditable")
                || (["audio", "video"].contains(tag.name) && names.contains("controls"))
                || (tag.name == "img" && names.contains("usemap"))
        }
    }

    static func convert(_ html: String, anchor: String) -> String {
        guard let root = root(in: html), allowedTags.contains(root.name),
              let link = self.root(in: anchor) else { return html }
        let children = tags(in: html, from: root.range.upperBound)
        guard let closing = children.last, closing.isClosing, closing.name == root.name else { return html }
        if hasInteractiveChildren(html) {
            var output = html
            let message = "Whole-part link disabled: remove nested links or interactive controls."
            let tooltip = attributes(root, in: html).contains { $0.name == "title" } ? "" : " title=\"\(message)\""
            output.insert(contentsOf: " data-foundry-link-error=\"\(message)\"\(tooltip)", at: html.index(before: root.range.upperBound))
            return output
        }
        let original = attributes(root, in: html)
        let generated = attributes(link, in: anchor)
        // Preserve identity and style. Link-owned attributes replace root
        // attributes once, rather than emitting ambiguous duplicate values.
        let owned: Set<String> = ["href", "target", "rel", "aria-label", "data-foundry-root-link", "data-foundry-link-display"]
        let originalNames = Set(original.map(\.name))
        let kept = original.filter { !owned.contains($0.name) }
        let additions = generated.filter { owned.contains($0.name) || !originalNames.contains($0.name) }
        let display = blockTags.contains(root.name) ? "block" : "inline"
        let attrs = (kept + additions).map(\.text).joined(separator: " ")
        let opening = "<a \(attrs) data-foundry-link-display=\"\(display)\">"
        var output = html
        output.replaceSubrange(closing.range, with: "</a>")
        output.replaceSubrange(root.range, with: opening)
        return output
    }
}
