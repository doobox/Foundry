import Foundation
import Markdown

/// Markdown parsing is shared by canvas, preview and export. Source is content,
/// not a second pass through Foundry's template language.
nonisolated enum FoundryMarkdown {
    static func html(from source: String) -> String {
        render(Document(parsing: source))
    }

    private static func children(_ node: any Markup) -> String {
        node.children.map { render($0) }.joined()
    }

    private static func render(_ node: any Markup) -> String {
        switch node {
        case let text as Markdown.Text: return escape(text.string)
        case let code as InlineCode: return "<code>\(escape(code.code))</code>"
        case let code as CodeBlock:
            let language = code.language?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            let attribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
            let label = language.isEmpty ? "Code" : language
            let languageAttribute = language.isEmpty ? "" : " data-language=\"\(escape(language))\""
            return """
            <div class="fd-markdown-code"\(languageAttribute)>
            <div class="fd-markdown-code-header"><span class="fd-markdown-code-language">\(escape(label))</span><button class="fd-markdown-code-copy" type="button" aria-label="Copy code" aria-live="polite">Copy</button></div>
            <pre><code\(attribute)>\(escape(code.code))</code></pre>
            </div>

            """
        case let heading as Heading:
            return "<h\(heading.level)>\(children(heading))</h\(heading.level)>\n"
        case is Paragraph: return "<p>\(children(node))</p>\n"
        case is Strong: return "<strong>\(children(node))</strong>"
        case is Emphasis: return "<em>\(children(node))</em>"
        case is Strikethrough: return "<del>\(children(node))</del>"
        case is BlockQuote: return "<blockquote>\n\(children(node))</blockquote>\n"
        case let list as OrderedList:
            let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
            return "<ol\(start)>\n\(children(list))</ol>\n"
        case is UnorderedList: return "<ul>\n\(children(node))</ul>\n"
        case let item as ListItem:
            let checkbox = item.checkbox.map {
                "<input type=\"checkbox\" disabled\($0 == .checked ? " checked" : "")> "
            } ?? ""
            return "<li>\(checkbox)\(children(item))</li>\n"
        case let link as Markdown.Link:
            guard let href = safeURL(link.destination) else { return children(link) }
            let title = link.title.map { " title=\"\(escape($0))\"" } ?? ""
            return "<a href=\"\(escape(href))\"\(title)>\(children(link))</a>"
        case let image as Markdown.Image:
            guard let src = safeURL(image.source) else { return escape(image.plainText) }
            let title = image.title.map { " title=\"\(escape($0))\"" } ?? ""
            return "<img src=\"\(escape(src))\" alt=\"\(escape(image.plainText))\"\(title)>"
        case is LineBreak: return "<br>\n"
        case is SoftBreak: return "\n"
        case is ThematicBreak: return "<hr>\n"
        case let table as Table: return "<table>\n\(children(table))</table>\n"
        case is Table.Head: return "<thead><tr>\(children(node))</tr></thead>\n"
        case is Table.Body: return "<tbody>\(children(node))</tbody>\n"
        case is Table.Row: return "<tr>\(children(node))</tr>\n"
        case let cell as Table.Cell:
            let tag = cell.parent is Table.Head ? "th" : "td"
            let table = cell.parent?.parent as? Table ?? cell.parent?.parent?.parent as? Table
            let alignment = table.flatMap { table in
                cell.indexInParent < table.columnAlignments.count ? table.columnAlignments[cell.indexInParent] : nil
            }.map { " style=\"text-align: \($0)\"" } ?? ""
            return "<\(tag)\(alignment)>\(children(cell))</\(tag)>"
        // Keep pasted HTML as text; use the HTML part for executable markup.
        case let html as HTMLBlock: return escape(html.rawHTML)
        case let html as InlineHTML: return escape(html.rawHTML)
        default: return children(node)
        }
    }

    private static func escape(_ source: String) -> String {
        source.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func safeURL(_ source: String?) -> String? {
        guard let source, !source.isEmpty else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if let scheme = URLComponents(string: trimmed)?.scheme,
           !["http", "https", "mailto", "tel"].contains(scheme.lowercased()) { return nil }
        return trimmed
    }
}
