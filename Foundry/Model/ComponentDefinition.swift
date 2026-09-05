import Foundation

nonisolated struct ComponentDefinition: Sendable {
    let type: ComponentType
    let displayName: String
    let systemImage: String
    let category: ComponentCategory
    let allowsChildren: Bool
    let renderKind: ComponentRenderKind
    let properties: [ComponentPropertyDefinition]
    let package: LoadedComponentPackage?

    init(
        type: ComponentType,
        displayName: String,
        systemImage: String,
        category: ComponentCategory,
        allowsChildren: Bool,
        renderKind: ComponentRenderKind,
        properties: [ComponentPropertyDefinition],
        package: LoadedComponentPackage? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.systemImage = systemImage
        self.category = category
        self.allowsChildren = allowsChildren
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
    let enable: ComponentPackageEnable?
    let themeValueSource: ComponentPackageThemeValueSource?
    let allowsCustomThemeValue: Bool

    var id: ComponentProperty.Key { key }

    init(
        key: ComponentProperty.Key,
        label: String,
        section: ComponentPropertySection,
        control: ComponentPropertyControl,
        defaultValue: ComponentProperty.Value,
        isResponsive: Bool? = nil,
        isInspectorVisible: Bool = true,
        enable: ComponentPackageEnable? = nil,
        themeValueSource: ComponentPackageThemeValueSource? = nil,
        allowsCustomThemeValue: Bool = false
    ) {
        self.key = key
        self.label = label
        self.section = section
        self.control = control
        self.defaultValue = defaultValue
        self.isResponsive = isResponsive ?? Self.builtInResponsiveKeys.contains(key)
        self.isInspectorVisible = isInspectorVisible
        self.enable = enable
        self.themeValueSource = themeValueSource
        self.allowsCustomThemeValue = allowsCustomThemeValue
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
    indirect case array(element: ComponentPropertyControl, count: Int, labels: [String], subtitles: [String], units: [String], help: String?)
    case singleLineText
    case multilineText
    case link(absoluteURL: Bool)
    case number(range: ClosedRange<Double>, step: Double, unit: String)
    case slider(range: ClosedRange<Double>, step: Double, ticks: Int, unit: String, showsValueField: Bool)
    case date
    case info
    case button(systemImage: String?)
    case details(help: String?)
    case derived
    case color
    case icon
    case packageColor(
        themeValues: Bool,
        colorMath: Bool,
        opacity: Bool
    )
    case choice([ComponentPropertyChoice])
    case themeFontSize
    case packageFontSize(themeValues: Bool)
    case packageSpacing(
        kind: ComponentSpacingKind,
        range: ClosedRange<Double>,
        step: Double
    )
    case textAlignment
    case divider
    case toggle
    case asset

    var isThemeFontSize: Bool {
        if case .themeFontSize = self { true } else { false }
    }

}

nonisolated enum ComponentSpacingKind: String, Sendable {
    case margin
    case padding

    var permitsAuto: Bool { self == .margin }
}

nonisolated struct ComponentPropertyChoice: Identifiable, Sendable {
    let value: String
    let label: String
    var separatorBefore: Bool = false

    var id: String { value }
}
