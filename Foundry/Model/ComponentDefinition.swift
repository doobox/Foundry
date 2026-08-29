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

    static let layout = ComponentCategory(rawValue: "Layout component")
    static let content = ComponentCategory(rawValue: "Content component")
    static let media = ComponentCategory(rawValue: "Media component")
    static let unavailable = ComponentCategory(rawValue: "Unavailable component")
}

nonisolated enum ComponentRenderKind: Sendable {
    case container
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

    var id: ComponentProperty.Key { key }

    init(
        key: ComponentProperty.Key,
        label: String,
        section: ComponentPropertySection,
        control: ComponentPropertyControl,
        defaultValue: ComponentProperty.Value,
        isResponsive: Bool? = nil
    ) {
        self.key = key
        self.label = label
        self.section = section
        self.control = control
        self.defaultValue = defaultValue
        self.isResponsive = isResponsive ?? Self.builtInResponsiveKeys.contains(key)
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
    case singleLineText
    case multilineText
    case url
    case number(range: ClosedRange<Double>, step: Double, unit: String)
    case color
    case choice([ComponentPropertyChoice])
    case themeFontFamily
    case toggle
    case asset

    var isThemeFontFamily: Bool {
        if case .themeFontFamily = self { true } else { false }
    }
}

nonisolated struct ComponentPropertyChoice: Identifiable, Sendable {
    let value: String
    let label: String

    var id: String { value }
}
