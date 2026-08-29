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
        static let themeFontSize = Key(rawValue: "themeFontSize")
        static let themeColor = Key(rawValue: "themeColor")
        static let themeColorShade = Key(rawValue: "themeColorShade")
        static let themeTextAlignment = Key(rawValue: "themeTextAlignment")
        static let themeFontWeight = Key(rawValue: "themeFontWeight")
        static let themeLineHeight = Key(rawValue: "themeLineHeight")
        static let themeLetterSpacing = Key(rawValue: "themeLetterSpacing")
        static let themeItalic = Key(rawValue: "themeItalic")
        static let themeTextShadow = Key(rawValue: "themeTextShadow")
        static let themeTextCase = Key(rawValue: "themeTextCase")
        static let themeWhitespace = Key(rawValue: "themeWhitespace")
        static let themeUnderline = Key(rawValue: "themeUnderline")
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

nonisolated enum ThemeTypographyControlCSS {
    static func declarations(for node: ComponentNode, theme: Theme) -> [String] {
        let keys = Set(node.type.definition.properties.map(\.key))
        guard keys.contains(.themeFontSize) else { return [] }

        let sizeReference = node.property(.themeFontSize)
        let lineHeight = node.property(.themeLineHeight)
        var declarations = [
            "font-size: \(theme.fontSizeCSSVariable(for: sizeReference))",
            "line-height: \(resolvedLineHeight(lineHeight, sizeReference: sizeReference, theme: theme))",
            "text-align: \(node.property(.themeTextAlignment))",
            "font-weight: \(node.property(.themeFontWeight))",
            "letter-spacing: \(letterSpacing(node.property(.themeLetterSpacing)))",
            "font-style: \(node.propertyValue(.themeItalic).booleanValue == true ? "italic" : "normal")",
            "text-shadow: \(textShadow(node.property(.themeTextShadow)))",
            "text-transform: \(node.property(.themeTextCase))",
            "white-space: \(node.property(.themeWhitespace))",
            "text-decoration-line: \(node.property(.themeUnderline))"
        ]
        declarations.removeAll { $0.hasSuffix(": none") && $0.hasPrefix("text-transform") }
        return declarations
    }

    private static func resolvedLineHeight(_ value: String, sizeReference: String, theme: Theme) -> String {
        guard value != "theme", let lineHeight = ThemeLineHeight(rawValue: value) else {
            return theme.lineHeightCSSVariable(for: sizeReference)
        }
        return lineHeight.value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private static func letterSpacing(_ value: String) -> String {
        switch value {
        case "tighter": "-0.05em"
        case "tight": "-0.025em"
        case "wide": "0.025em"
        case "wider": "0.05em"
        case "widest": "0.1em"
        default: "0em"
        }
    }

    private static func textShadow(_ value: String) -> String {
        switch value {
        case "small": "0 1px 2px rgb(0 0 0 / 0.18)"
        case "medium": "0 2px 4px rgb(0 0 0 / 0.22)"
        case "large": "0 4px 10px rgb(0 0 0 / 0.28)"
        default: "none"
        }
    }
}
