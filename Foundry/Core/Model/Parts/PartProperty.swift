import Foundation

nonisolated enum PartThemeValueSelection {
    static let manualCustom = "foundry:manual-custom"
    static let manifestCustom = "custom"

    static func isManualCustom(_ source: String) -> Bool {
        source == manualCustom
    }

    static func storedSource(forManifestValue source: String) -> String {
        source == manifestCustom ? manualCustom : source
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

nonisolated struct PartPackageStackingOrderValue: Codable, Equatable, Sendable {
    var source: String
    var customValue: Double

    init(source: String, customValue: Double = 100) {
        self.source = source
        self.customValue = customValue
    }

    var isCustom: Bool {
        PartThemeValueSelection.isManualCustom(source)
    }
}

nonisolated struct PartPackageShadowValue: Codable, Equatable, Sendable {
    var source: String
    var customLayers: [ThemeShadowLayer]

    static let defaultCustom = PartPackageShadowValue(
        source: PartThemeValueSelection.manualCustom,
        customLayers: [.init(x: 0, y: 4, blur: 8, opacity: 0.15)]
    )
}

nonisolated enum PartPackageShadowResolver {
    static func filter(_ value: PartPackageShadowValue, theme: Theme) -> String {
        let layers = PartThemeValueSelection.isManualCustom(value.source)
            ? value.customLayers
            : theme.shadows.shadows.first(where: { $0.id == value.source })?.layers ?? []
        let shadows = layers.compactMap(\.dropShadowCSS)
        return shadows.isEmpty ? "none" : shadows.joined(separator: " ")
    }

    static func resolve(_ value: PartPackageShadowValue, theme: Theme) -> String {
        if PartThemeValueSelection.isManualCustom(value.source) {
            return value.customLayers.isEmpty ? "none" : value.customLayers.map(\.cssValue).joined(separator: ", ")
        }
        return theme.shadowCSSVariable(for: value.source) ?? "none"
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
        static let themeFontSize = Key(rawValue: "frameworkFontSize")
        static let themeTextAlignment = Key(rawValue: "frameworkTextAlignment")
        static let themeFontWeight = Key(rawValue: "frameworkFontWeight")
        static let themeLineHeight = Key(rawValue: "frameworkLineHeight")
        static let themeLetterSpacing = Key(rawValue: "frameworkLetterSpacing")
        static let themeItalic = Key(rawValue: "frameworkItalic")
        static let themeTextShadow = Key(rawValue: "frameworkTextShadow")
        static let themeTextCase = Key(rawValue: "frameworkTextCase")
        static let themeWhitespace = Key(rawValue: "frameworkWhitespace")
        static let themeUnderline = Key(rawValue: "frameworkUnderline")
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
        case object([String: Value])
        case link(PartLink)
        // Retained only to decode saved values from the removed Select extension.
        case packageFontSize(PartPackageFontSizeValue)
        case packageShadow(PartPackageShadowValue)
        case packageStackingOrder(PartPackageStackingOrderValue)
        case themeSpacing(ThemeSingleSpacingValue)
        case themePadding(ThemePaddingValue)
        case themeMargin(ThemeMarginValue)
        case themeBorderWidth(ThemeBorderWidthValue)
        case themeRadius(ThemeRadiusValue)

        // Existing project files retain these stable payload keys.
        private enum CodingKeys: String, CodingKey {
            case string, url, number, color, choice, boolean, token, array, object, link
            case packageFontSize, packageShadow, packageStackingOrder
            case themeSpacing = "frameworkSpacing"
            case themePadding = "frameworkPadding"
            case themeMargin = "frameworkMargin"
            case themeBorderWidth = "frameworkBorderWidth"
            case themeRadius = "frameworkRadius"
        }

        var stringValue: String {
            switch self {
            case .string(let value), .url(let value), .color(let value), .choice(let value):
                value
            case .number(let value):
                // Output text, not UI: fixed locale, no grouping.
                value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            case .boolean(let value):
                value ? "true" : "false"
            case .token(let token):
                token.rawValue
            case .array(let values):
                values.map(\.stringValue).joined(separator: ", ")
            case .object:
                ""
            case .link:
                ""
            case .packageFontSize(let value):
                value.source
            case .packageShadow(let value):
                value.source
            case .packageStackingOrder(let value):
                value.source
            case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius:
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

        var objectValue: [String: Value]? {
            guard case .object(let value) = self else { return nil }
            return value
        }

        func replacingSpacingReference(_ reference: String, with replacement: String) -> Value {
            switch self {
            case .themeSpacing(var value):
                if value.selection.token == reference { value.selection.token = replacement }
                return .themeSpacing(value)
            case .themeMargin(var value):
                value.replaceReference(reference, with: replacement)
                return .themeMargin(value)
            case .themePadding(var value):
                value.replaceReference(reference, with: replacement)
                return .themePadding(value)
            case .array(let values): return .array(values.map { $0.replacingSpacingReference(reference, with: replacement) })
            case .object(let values): return .object(values.mapValues { $0.replacingSpacingReference(reference, with: replacement) })
            default: return self
            }
        }

        func replacingThemeReference(_ reference: String, with replacement: String) -> Value {
            switch self {
            case .themeSpacing(var value):
                if value.selection.token == reference { value.selection.token = replacement }
                return .themeSpacing(value)
            case .themeBorderWidth(var value):
                value.replaceReference(reference, with: replacement)
                return .themeBorderWidth(value)
            case .themeRadius(var value):
                value.replaceReference(reference, with: replacement)
                return .themeRadius(value)
            case .themeMargin(var value):
                value.replaceReference(reference, with: replacement)
                return .themeMargin(value)
            case .themePadding(var value):
                value.replaceReference(reference, with: replacement)
                return .themePadding(value)
            case .string(let value): return .string(value == reference ? replacement : value)
            case .choice(let value): return .choice(value == reference ? replacement : value)
            case .array(let values):
                return .array(values.map { $0.replacingThemeReference(reference, with: replacement) })
            case .object(let values):
                return .object(values.mapValues { $0.replacingThemeReference(reference, with: replacement) })
            case .packageFontSize(var value):
                if value.source == reference { value.source = replacement }
                return .packageFontSize(value)
            case .packageShadow(var value):
                if value.source == reference { value.source = replacement }
                return .packageShadow(value)
            case .packageStackingOrder(var value):
                if value.source == reference { value.source = replacement }
                return .packageStackingOrder(value)
            case .url, .number, .color, .boolean, .token, .link:
                return self
            }
        }

        /// Deleting a shared spacing bakes its current size into any part
        /// still using it: length-capable controls keep the exact amount as
        /// a custom value; token-only selections snap to `fallbackToken`.
        func bakingThemeSpacingReference(
            _ reference: String,
            amountRem: Double,
            fallbackToken: String
        ) -> Value {
            switch self {
            case .themeSpacing(var value):
                if value.selection.token == reference {
                    value.selection.token = fallbackToken
                    value.selection.isCustom = true
                    value.selection.amount = amountRem
                    value.selection.unit = "rem"
                }
                return .themeSpacing(value)
            case .themeMargin(var value):
                value.bakeReference(reference, amount: amountRem, unit: "rem", fallbackToken: fallbackToken)
                return .themeMargin(value)
            case .themePadding(var value):
                value.bakeReference(reference, amount: amountRem, unit: "rem", fallbackToken: fallbackToken)
                return .themePadding(value)
            case .string(let value): return .string(value == reference ? fallbackToken : value)
            case .choice(let value): return .choice(value == reference ? fallbackToken : value)
            case .array(let values):
                return .array(values.map {
                    $0.bakingThemeSpacingReference(reference, amountRem: amountRem, fallbackToken: fallbackToken)
                })
            case .object(let values):
                return .object(values.mapValues {
                    $0.bakingThemeSpacingReference(reference, amountRem: amountRem, fallbackToken: fallbackToken)
                })
            case .themeBorderWidth, .themeRadius, .packageFontSize, .packageShadow,
                 .packageStackingOrder, .url, .number, .color, .boolean, .token, .link:
                return self
            }
        }

        /// Deleting a custom border width or corner radius bakes its pixel
        /// size into any part still using it; `isRadius` picks which value
        /// kind the reference can appear in.
        func bakingThemeDimensionReference(
            _ reference: String,
            amountPx: Double,
            fallbackToken: String,
            isRadius: Bool
        ) -> Value {
            switch self {
            case .themeBorderWidth(var value) where !isRadius:
                value.bakeReference(reference, amount: amountPx, unit: "px", fallbackToken: fallbackToken)
                return .themeBorderWidth(value)
            case .themeRadius(var value) where isRadius:
                value.bakeReference(reference, amount: amountPx, unit: "px", fallbackToken: fallbackToken)
                return .themeRadius(value)
            case .array(let values):
                return .array(values.map {
                    $0.bakingThemeDimensionReference(reference, amountPx: amountPx, fallbackToken: fallbackToken, isRadius: isRadius)
                })
            case .object(let values):
                return .object(values.mapValues {
                    $0.bakingThemeDimensionReference(reference, amountPx: amountPx, fallbackToken: fallbackToken, isRadius: isRadius)
                })
            default:
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
