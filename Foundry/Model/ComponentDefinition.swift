import Foundation

nonisolated struct ComponentDefinition: Sendable {
    let type: ComponentType
    let displayName: String
    let systemImage: String
    let category: ComponentCategory
    let allowsChildren: Bool
    let inlineEditableProperty: ComponentProperty.Key?
    let renderKind: ComponentRenderKind
    let properties: [ComponentPropertyDefinition]
    let package: LoadedComponentPackage?

    init(
        type: ComponentType,
        displayName: String,
        systemImage: String,
        category: ComponentCategory,
        allowsChildren: Bool,
        inlineEditableProperty: ComponentProperty.Key?,
        renderKind: ComponentRenderKind,
        properties: [ComponentPropertyDefinition],
        package: LoadedComponentPackage? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.systemImage = systemImage
        self.category = category
        self.allowsChildren = allowsChildren
        self.inlineEditableProperty = inlineEditableProperty
        self.renderKind = renderKind
        self.properties = properties
        self.package = package
    }
}

nonisolated struct ComponentCategory: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let layout = ComponentCategory(rawValue: "Layout")
    static let content = ComponentCategory(rawValue: "Content")
    static let media = ComponentCategory(rawValue: "Media")
    static let navigation = ComponentCategory(rawValue: "Navigation")
    static let forms = ComponentCategory(rawValue: "Forms")
    static let interactive = ComponentCategory(rawValue: "Interactive")
    static let other = ComponentCategory(rawValue: "Other")
    static let unavailable = other
}

nonisolated enum ComponentPackageGroup: String, CaseIterable, Sendable {
    case layout = "Layout"
    case content = "Content"
    case media = "Media"
    case navigation = "Navigation"
    case forms = "Forms"
    case interactive = "Interactive"
    case other = "Other"

    static func resolve(_ value: String) -> ComponentPackageGroup {
        allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame } ?? .other
    }
}

nonisolated enum ComponentRenderKind: Sendable {
    case section
    case columns
    case text
    case heading
    case button
    case image
    case divider
    case spacer
    case package
    case unavailable
}

nonisolated struct ComponentPropertyDefinition: Identifiable, Sendable {
    let key: ComponentProperty.Key
    let label: String
    let section: ComponentPropertySection
    let control: ComponentPropertyControl
    let defaultValue: ComponentProperty.Value
    let isResponsive: Bool
    let isInspectorVisible: Bool

    var id: ComponentProperty.Key { key }

    init(
        key: ComponentProperty.Key,
        label: String,
        section: ComponentPropertySection,
        control: ComponentPropertyControl,
        defaultValue: ComponentProperty.Value,
        isResponsive: Bool? = nil,
        isInspectorVisible: Bool = true
    ) {
        self.key = key
        self.label = label
        self.section = section
        self.control = control
        self.defaultValue = defaultValue
        self.isResponsive = isResponsive ?? Self.builtInResponsiveKeys.contains(key)
        self.isInspectorVisible = isInspectorVisible
    }

    private static let builtInResponsiveKeys: Set<ComponentProperty.Key> = [
        .alignment, .padding, .backgroundColor, .textColor, .fontSize,
        .marginTop, .marginBottom, .borderColor, .borderWidth, .cornerRadius,
        .maxWidth, .horizontalAlignment, .height, .columnCount, .gap
    ]
}

nonisolated struct ComponentPropertySection: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let content = ComponentPropertySection(rawValue: "Content")
    static let typography = ComponentPropertySection(rawValue: "Typography")
    static let appearance = ComponentPropertySection(rawValue: "Appearance")
    static let layout = ComponentPropertySection(rawValue: "Layout")
    static let link = ComponentPropertySection(rawValue: "Link")
    static let accessibility = ComponentPropertySection(rawValue: "Accessibility")
}

nonisolated enum ComponentPropertyControl: Sendable {
    indirect case array(element: ComponentPropertyControl, count: Int, subtitles: [String], help: String?)
    case singleLineText
    case multilineText
    case url
    case number(range: ClosedRange<Double>, step: Double, unit: String)
    case slider(range: ClosedRange<Double>, step: Double, tickMarks: Int, restrictsToTickMarks: Bool)
    case date
    case info
    case button
    case color
    case packageColor(
        themeValues: Bool,
        customColorKey: ComponentProperty.Key,
        colorMathKey: ComponentProperty.Key?,
        opacityKey: ComponentProperty.Key?
    )
    case choice([ComponentPropertyChoice])
    case themeFontFamily
    case themeFontSize
    case packageFontFamily(themeValues: Bool, customValueKey: ComponentProperty.Key)
    case packageFontSize(themeValues: Bool, customValueKey: ComponentProperty.Key)
    case textAlignment
    case divider
    case toggle
    case asset

    var isThemeFontFamily: Bool {
        if case .themeFontFamily = self { true } else { false }
    }

    var isThemeFontSize: Bool {
        if case .themeFontSize = self { true } else { false }
    }

}

nonisolated struct ComponentPropertyChoice: Identifiable, Sendable {
    let value: String
    let label: String

    var id: String { value }
}
