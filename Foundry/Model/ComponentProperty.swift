import Foundation

nonisolated struct ComponentProperty: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var key: Key
    var value: Value

    init(id: UUID = UUID(), key: Key, value: Value) {
        self.id = id
        self.key = key
        self.value = value
    }

    nonisolated struct Key: RawRepresentable, Codable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        static let text = Key(rawValue: "text")
        static let destination = Key(rawValue: "destination")
        static let alignment = Key(rawValue: "alignment")
        static let padding = Key(rawValue: "padding")
        static let backgroundColor = Key(rawValue: "backgroundColor")
        static let textColor = Key(rawValue: "textColor")
        static let fontSize = Key(rawValue: "fontSize")
        static let themeFontFamily = Key(rawValue: "themeFontFamily")
        static let accessibilityLabel = Key(rawValue: "accessibilityLabel")
        static let marginTop = Key(rawValue: "marginTop")
        static let marginBottom = Key(rawValue: "marginBottom")
        static let borderColor = Key(rawValue: "borderColor")
        static let borderWidth = Key(rawValue: "borderWidth")
        static let cornerRadius = Key(rawValue: "cornerRadius")
        static let maxWidth = Key(rawValue: "maxWidth")
        static let horizontalAlignment = Key(rawValue: "horizontalAlignment")
        static let source = Key(rawValue: "source")
        static let altText = Key(rawValue: "altText")
        static let headingLevel = Key(rawValue: "headingLevel")
        static let height = Key(rawValue: "height")
        static let columnCount = Key(rawValue: "columnCount")
        static let gap = Key(rawValue: "gap")
    }

    nonisolated enum Value: Codable, Equatable, Sendable {
        case string(String)
        case url(String)
        case number(Double)
        case color(String)
        case choice(String)
        case boolean(Bool)
        case token(DesignToken)

        var stringValue: String {
            switch self {
            case .string(let value), .url(let value), .color(let value), .choice(let value):
                value
            case .number(let value):
                value.formatted()
            case .boolean(let value):
                value ? "true" : "false"
            case .token(let token):
                token.rawValue
            }
        }

        var numberValue: Double? {
            guard case .number(let value) = self else { return nil }
            return value
        }

        var tokenValue: DesignToken? {
            guard case .token(let token) = self else { return nil }
            return token
        }

        var booleanValue: Bool? {
            guard case .boolean(let value) = self else { return nil }
            return value
        }
    }
}
