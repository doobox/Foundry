import Foundation

nonisolated struct BlockHTMLAttribute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

nonisolated enum BlockAnchorDiscovery {
    static func identifiers(in html: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"<[^>]*\bdata-foundry-id\s*=\s*([\"']).*?\1[^>]*\sid\s*=\s*([\"'])(.*?)\2[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }
        var seen = Set<String>()
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range(at: 3), in: html) else { return nil }
            let identifier = String(html[range])
            return identifier.isEmpty || !seen.insert(identifier).inserted ? nil : identifier
        }
    }
}

nonisolated struct BlockLink: Codable, Equatable, Sendable {
    enum Destination: Codable, Equatable, Sendable {
        case none
        case url(String)
        case plainText(String)
        case page(UUID)
        case resource(UUID)
    }

    var destination: Destination = .none
    var anchor = ""
    var opensInNewWindow = false
    var attributes: [Attribute] = []

    typealias Attribute = BlockHTMLAttribute
}
