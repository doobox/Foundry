import Foundation

nonisolated enum PartFrameworkValueSelection {
    static let manualCustom = "foundry:manual-custom"
    static let manifestCustom = "custom"

    static func isManualCustom(_ source: String) -> Bool {
        source == manualCustom
    }

    static func storedSource(forManifestValue source: String) -> String {
        source == manifestCustom ? manualCustom : source
    }
}

nonisolated struct PartPackageColorValue: Codable, Equatable, Sendable {
    var source: String
    var customColor: String
    var opacity: Double
    var shade: ColourShade
    var darkShade: ColourShade
    var darkCustomColor: String
    var darkOpacity: Double

    init(source: String, customColor: String, opacity: Double,
         shade: ColourShade? = nil, darkShade: ColourShade? = nil) {
        self.source = source
        self.customColor = customColor
        self.opacity = opacity
        let id = FrameworkColorRole(rawValue: source) != nil ? "framework." + source : source
        self.shade = shade ?? Framework.standard.colourPalettes.resolvedPalette(id: id)?.lightDefaultShade ?? .six
        self.darkShade = darkShade ?? Framework.standard.colourPalettes.resolvedPalette(id: id)?.darkDefaultShade ?? .six
        self.darkCustomColor = customColor
        self.darkOpacity = opacity
    }

    var paletteID: String {
        FrameworkColorRole(rawValue: source) != nil ? "framework." + source : source
    }

    var selection: PaletteColourValue {
        PartFrameworkValueSelection.isManualCustom(source) ? .custom(hex: customColor)
            : .palette(id: paletteID, selection: .shade(shade))
    }

    private enum CodingKeys: String, CodingKey { case source, customColor, opacity, shade, darkShade, darkCustomColor, darkOpacity }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        customColor = try values.decode(String.self, forKey: .customColor)
        opacity = try values.decode(Double.self, forKey: .opacity)
        shade = try values.decode(ColourShade.self, forKey: .shade)
        darkShade = try values.decode(ColourShade.self, forKey: .darkShade)
        darkCustomColor = try values.decode(String.self, forKey: .darkCustomColor)
        darkOpacity = try values.decode(Double.self, forKey: .darkOpacity)
    }
}

nonisolated struct PartPackageFontSizeValue: Codable, Equatable, Sendable {
    var source: String
    var customValue: String
    var customLineHeight: String

    init(source: String, customValue: String, customLineHeight: String = "1.5") {
        self.source = source
        self.customValue = customValue
        self.customLineHeight = customLineHeight
    }

    private enum CodingKeys: String, CodingKey {
        case source, customValue, customLineHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        customValue = try container.decode(String.self, forKey: .customValue)
        if let stringValue = try? container.decode(String.self, forKey: .customLineHeight) {
            customLineHeight = stringValue
        } else if let numberValue = try? container.decode(Double.self, forKey: .customLineHeight) {
            customLineHeight = numberValue.formatted(
                .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))
            )
        } else {
            customLineHeight = "1.5"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(customValue, forKey: .customValue)
        try container.encode(customLineHeight, forKey: .customLineHeight)
    }
}

nonisolated struct PartPackageShadowValue: Codable, Equatable, Sendable {
    var source: String
    var customLayers: [FrameworkShadowLayer]

    static let defaultCustom = PartPackageShadowValue(
        source: PartFrameworkValueSelection.manualCustom,
        customLayers: [.init(x: 0, y: 4, blur: 8, opacity: 0.15)]
    )
}

nonisolated enum PartPackageShadowResolver {
    static func resolve(_ value: PartPackageShadowValue, framework: Framework) -> String {
        if PartFrameworkValueSelection.isManualCustom(value.source) {
            return value.customLayers.isEmpty ? "none" : value.customLayers.map(\.cssValue).joined(separator: ", ")
        }
        return framework.shadowCSSVariable(for: value.source) ?? "none"
    }
}

nonisolated struct PartProperty: Codable, Equatable, Identifiable, Sendable {
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
        static let backgroundColor = Key(rawValue: "backgroundColor")
        static let textColor = Key(rawValue: "textColor")
        static let fontSize = Key(rawValue: "fontSize")
        static let frameworkFontSize = Key(rawValue: "frameworkFontSize")
        static let frameworkColor = Key(rawValue: "frameworkColor")
        static let frameworkColorShade = Key(rawValue: "frameworkColorShade")
        static let frameworkTextAlignment = Key(rawValue: "frameworkTextAlignment")
        static let frameworkFontWeight = Key(rawValue: "frameworkFontWeight")
        static let frameworkLineHeight = Key(rawValue: "frameworkLineHeight")
        static let frameworkLetterSpacing = Key(rawValue: "frameworkLetterSpacing")
        static let frameworkItalic = Key(rawValue: "frameworkItalic")
        static let frameworkTextShadow = Key(rawValue: "frameworkTextShadow")
        static let frameworkTextCase = Key(rawValue: "frameworkTextCase")
        static let frameworkWhitespace = Key(rawValue: "frameworkWhitespace")
        static let frameworkUnderline = Key(rawValue: "frameworkUnderline")
        static let accessibilityLabel = Key(rawValue: "accessibilityLabel")
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
        case array([Value])
        case link(PartLink)
        case packageColor(PartPackageColorValue)
        // Retained only to decode saved values from the removed Select extension.
        case packageFontSize(PartPackageFontSizeValue)
        case packageShadow(PartPackageShadowValue)
        case frameworkSpacing(FrameworkSingleSpacingValue)
        case frameworkPadding(FrameworkPaddingValue)
        case frameworkMargin(FrameworkMarginValue)
        case frameworkBorderWidth(FrameworkBorderWidthValue)
        case frameworkRadius(FrameworkRadiusValue)

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
            case .array(let values):
                values.map(\.stringValue).joined(separator: ", ")
            case .link:
                ""
            case .packageColor(let value):
                value.source
            case .packageFontSize(let value):
                value.source
            case .packageShadow(let value):
                value.source
            case .frameworkSpacing, .frameworkPadding, .frameworkMargin, .frameworkBorderWidth, .frameworkRadius:
                ""
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

        var arrayValue: [Value]? {
            guard case .array(let value) = self else { return nil }
            return value
        }

        func replacingFrameworkReference(_ reference: String, with replacement: String) -> Value {
            switch self {
            case .frameworkSpacing(var value):
                if value.selection.token == reference { value.selection.token = replacement }
                return .frameworkSpacing(value)
            case .frameworkBorderWidth(var value):
                value.replaceReference(reference, with: replacement)
                return .frameworkBorderWidth(value)
            case .frameworkRadius(var value):
                value.replaceReference(reference, with: replacement)
                return .frameworkRadius(value)
            case .frameworkMargin(var value):
                value.replaceReference(reference, with: replacement)
                return .frameworkMargin(value)
            case .frameworkPadding(var value):
                value.replaceReference(reference, with: replacement)
                return .frameworkPadding(value)
            case .string(let value): return .string(value == reference ? replacement : value)
            case .choice(let value): return .choice(value == reference ? replacement : value)
            case .array(let values):
                return .array(values.map { $0.replacingFrameworkReference(reference, with: replacement) })
            case .packageFontSize(var value):
                if value.source == reference { value.source = replacement }
                return .packageFontSize(value)
            case .packageShadow(var value):
                if value.source == reference { value.source = replacement }
                return .packageShadow(value)
            case .packageColor(var value):
                if value.paletteID == reference { value.source = replacement }
                return .packageColor(value)
            case .url, .number, .color, .boolean, .token, .link:
                return self
            }
        }

        func value(at indexPath: [Int]) -> Value? {
            guard let index = indexPath.first else { return self }
            guard case .array(let values) = self, values.indices.contains(index) else { return nil }
            return values[index].value(at: Array(indexPath.dropFirst()))
        }

        func settingValue(
            _ value: Value,
            at indexPath: [Int],
            defaultLeafValue: Value
        ) -> Value {
            guard let index = indexPath.first else { return value }
            var values = arrayValue ?? []
            let remainingPath = Array(indexPath.dropFirst())
            let paddingValue: Value = remainingPath.isEmpty ? defaultLeafValue : .array([])
            while values.count <= index {
                values.append(paddingValue)
            }
            values[index] = values[index].settingValue(
                value,
                at: remainingPath,
                defaultLeafValue: defaultLeafValue
            )
            return .array(values)
        }
    }
}
