import Foundation

nonisolated struct PartInspectorControlGroup: Identifiable, Sendable {
    let id: PartProperty.Key
    var properties: [PartPropertyDefinition]

    static func groups(for properties: [PartPropertyDefinition]) -> [Self] {
        var groups: [Self] = []
        for property in properties {
            if let controlID = property.inspectorControlID,
               let last = groups.last,
               last.properties.last?.inspectorControlID == controlID {
                groups[groups.count - 1].properties.append(property)
            } else {
                groups.append(Self(id: property.key, properties: [property]))
            }
        }
        return groups
    }
}

nonisolated struct PartDefinition: Sendable {
    static let genericSystemImage = "puzzlepiece.extension"

    let type: PartType
    let displayName: String
    let systemImage: String
    let category: PartCategory
    let allowsChildren: Bool
    let renderKind: PartRenderKind
    let properties: [PartPropertyDefinition]
    let package: LoadedPartPackage?
    /// Unified manifest order, including controls represented by child slots.
    let inspectorRows: [PartInspectorRow]
    // Per-key index: rendering resolves every property of every part
    // instance by key, and scanning `properties` each time dominates
    // page-render profiles on layout-heavy trees.
    private let propertyIndicesByKey: [PartProperty.Key: Int]

    init(
        type: PartType,
        displayName: String,
        systemImage: String,
        category: PartCategory,
        allowsChildren: Bool,
        renderKind: PartRenderKind,
        properties: [PartPropertyDefinition],
        package: LoadedPartPackage? = nil,
        inspectorRows: [PartInspectorRow]? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.systemImage = systemImage
        self.category = category
        self.allowsChildren = allowsChildren
        self.renderKind = renderKind
        self.properties = properties
        self.package = package
        self.inspectorRows = inspectorRows ?? PartInspectorControlGroup.groups(for: properties).map(PartInspectorRow.controls)
        propertyIndicesByKey = Dictionary(
            properties.enumerated().map { ($1.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func property(for key: PartProperty.Key) -> PartPropertyDefinition? {
        propertyIndicesByKey[key].map { properties[$0] }
    }

    /// The SF Symbol for an Inspector section's disclosure header: named
    /// sections supply icons through their `systemImage`, the native Advanced
    /// section wears its fixed gear, and everything else takes the generic
    /// fallback.
    func systemImage(for section: PartPropertySection) -> String {
        if let icon = package?.manifest.resolvedGroupIcons[section.rawValue] {
            return icon
        }
        if section.rawValue == "Advanced",
           package?.manifest.controlGroups.contains(where: { $0.type == .advanced }) == true {
            return "gearshape"
        }
        return PartPropertySection.genericSystemImage
    }

    func visibilityCondition(for section: PartPropertySection) -> PartPackageVisibilityCondition? {
        package?.manifest.controlSections.first { $0.name == section.rawValue }?.visibleWhen
    }
}

nonisolated struct PartCategory: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let accessibility = PartCategory(rawValue: "Accessibility")
    static let animation = PartCategory(rawValue: "Animation")
    static let cms = PartCategory(rawValue: "CMS")
    static let content = PartCategory(rawValue: "Content")
    static let dynamic = PartCategory(rawValue: "Dynamic")
    static let ecommerce = PartCategory(rawValue: "Ecommerce")
    static let forms = PartCategory(rawValue: "Forms")
    static let interactive = PartCategory(rawValue: "Interactive")
    static let layout = PartCategory(rawValue: "Layout")
    static let media = PartCategory(rawValue: "Media")
    static let navigation = PartCategory(rawValue: "Navigation")
    static let security = PartCategory(rawValue: "Security")
    static let seo = PartCategory(rawValue: "SEO")
    static let utility = PartCategory(rawValue: "Utility")
    static let other = PartCategory(rawValue: "Other")
    static let unavailable = other
}

/// The Parts-panel headings a manifest's `group` may name, in the order the
/// panel lists them. Anything else falls into Other.
nonisolated enum PartPackageGroup: String, CaseIterable, Sendable {
    case accessibility = "Accessibility"
    case animation = "Animation"
    case cms = "CMS"
    case content = "Content"
    case dynamic = "Dynamic"
    case ecommerce = "Ecommerce"
    case forms = "Forms"
    case interactive = "Interactive"
    case layout = "Layout"
    case media = "Media"
    case navigation = "Navigation"
    case security = "Security"
    case seo = "SEO"
    case utility = "Utility"
    case other = "Other"

    /// What belongs under each heading, for developers choosing a group.
    var summary: String {
        switch self {
        case .accessibility: "Skip links, screen-reader text, contrast and focus aids"
        case .animation: "Motion and transitions on scroll, hover or load"
        case .cms: "Content pulled from an external content management system"
        case .content: "Headings, body text, quotes and lists"
        case .dynamic: "Content fetched live from a spreadsheet, feed or API"
        case .ecommerce: "Product listings, baskets, checkout links and pricing"
        case .forms: "Inputs, choices, uploads and submit buttons"
        case .interactive: "Dialogs, disclosure panels, slideshows and tooltips"
        case .layout: "Sections, grids, columns and wrappers that arrange other parts"
        case .media: "Pictures, film, sound and embedded players"
        case .navigation: "Menus, bars, crumbs, tab strips and page links"
        case .security: "Password gates, sign-in prompts and protected areas"
        case .seo: "Structured data, meta helpers and rich results"
        case .utility: "Consent banners, anchors, spacers and separators"
        case .other: "Anything that fits nowhere else"
        }
    }

    var category: PartCategory { PartCategory(rawValue: rawValue) }

    static func resolve(_ value: String) -> PartPackageGroup {
        allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame } ?? .other
    }
}

nonisolated enum PartRenderKind: Sendable {
    case package
    case unavailable
}

nonisolated struct PartPropertyDefinition: Identifiable, Sendable {
    // Rows generated by one public control share an Inspector grid.
    var inspectorControlID: String? = nil
    let key: PartProperty.Key
    let label: String
    let subtitle: String?
    let section: PartPropertySection
    let control: PartPropertyControl
    var breakpointDefaults: [ResponsiveBreakpoint: PartProperty.Value] = [:]
    let defaultValue: PartProperty.Value
    let isResponsive: Bool
    let isInspectorVisible: Bool
    let visibleWhen: PartPackageVisibilityCondition?
    var outputWhenHidden: Bool
    let themeValueSource: PartPackageThemeValueSource?
    let allowsCustomThemeValue: Bool
    let supportsImageFocalPoint: Bool
    let dateMinimum: Date?
    let dateMaximum: Date?
    let presentation: PartPackageControl.ControlPresentation?
    let colourSections: [String]
    let colourPurpose: PartColourPurpose?

    var id: PartProperty.Key { key }

    init(
        key: PartProperty.Key,
        label: String,
        subtitle: String? = nil,
        section: PartPropertySection,
        control: PartPropertyControl,
        defaultValue: PartProperty.Value,
        isResponsive: Bool? = nil,
        isInspectorVisible: Bool = true,
        visibleWhen: PartPackageVisibilityCondition? = nil,
        outputWhenHidden: Bool = true,
        themeValueSource: PartPackageThemeValueSource? = nil,
        allowsCustomThemeValue: Bool = false,
        supportsImageFocalPoint: Bool = false,
        dateMinimum: Date? = nil,
        dateMaximum: Date? = nil,
        presentation: PartPackageControl.ControlPresentation? = nil,
        colourSections: [String] = ["themes"],
        colourPurpose: PartColourPurpose? = nil
    ) {
        self.key = key
        self.label = label
        self.subtitle = subtitle
        self.section = section
        self.control = control
        self.defaultValue = defaultValue
        self.isResponsive = isResponsive ?? Self.builtInResponsiveKeys.contains(key)
        self.isInspectorVisible = isInspectorVisible
        self.visibleWhen = visibleWhen
        self.outputWhenHidden = outputWhenHidden
        self.themeValueSource = themeValueSource
        self.allowsCustomThemeValue = allowsCustomThemeValue
        self.supportsImageFocalPoint = supportsImageFocalPoint
        self.dateMinimum = dateMinimum
        self.dateMaximum = dateMaximum
        self.presentation = presentation
        self.colourSections = colourSections
        self.colourPurpose = colourPurpose
    }

    private static let builtInResponsiveKeys: Set<PartProperty.Key> = [
        .alignment, .backgroundColor, .textColor, .fontSize,
        .borderColor, .borderWidth, .cornerRadius,
        .maxWidth, .horizontalAlignment, .height, .columnCount, .gap
    ]
}

nonisolated struct PartPropertySection: RawRepresentable, Hashable, Sendable {
    /// The Inspector header icon for groups that declare none of their own.
    static let genericSystemImage = "slider.horizontal.3"

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let content = PartPropertySection(rawValue: "Content")
    static let typography = PartPropertySection(rawValue: "Typography")
    static let appearance = PartPropertySection(rawValue: "Appearance")
    static let layout = PartPropertySection(rawValue: "Layout")
    static let link = PartPropertySection(rawValue: "Link")
    static let accessibility = PartPropertySection(rawValue: "Accessibility")
}

nonisolated enum PartPropertyControl: Sendable {
    indirect case array(element: PartPropertyControl, count: Int, subtitles: [String], buttonTexts: [String], buttonIcons: [String], activeButtonTexts: [String], activeButtonIcons: [String], buttonSelectionMode: PartPackageControl.ButtonSelectionMode, units: [String], help: String?)
    case singleLineText
    case multilineText
    case link(absoluteURL: Bool)
    case number(range: ClosedRange<Double>, step: Double, unit: String)
    case slider(SliderOptions)
    case date
    case note(systemImage: String?)
    case button(icon: String?, text: String, activeIcon: String?, activeText: String?)
    case derived
    case color
    case colorWithOpacity
    case literalColor(allowsOpacity: Bool)
    case icon
    case choice([PartPropertyChoice])
    case space(axis: String)
    case themeColors
    case themeFontSize
    case themeStackingOrder
    case pageFolder
    case themeFont
    case themeBorderWidth
    case themeRadius
    case themeMargin
    case themeSpacing
    case themePadding
    case edges(units: [String])
    case corners(units: [String])
    case fontWeight(font: String?)
    case fontStyle(font: String?)
    case packageShadow
    case textAlignment
    case divider
    case spacer(height: Double)
    case toggle
    case image
    case svg
    case video
    case collection(itemLabel: String, fields: [PartPropertyDefinition])

    var isThemeFontSize: Bool {
        if case .themeFontSize = self { true } else { false }
    }

    var isArray: Bool {
        if case .array = self { true } else { false }
    }

    var isMedia: Bool {
        switch self {
        case .image, .svg, .video: true
        default: false
        }
    }

    var isCollection: Bool {
        if case .collection = self { true } else { false }
    }

}

nonisolated struct PartPropertyChoice: Identifiable, Sendable {
    let value: String
    let label: String
    var systemImage: String? = nil
    var separatorBefore: Bool = false

    var id: String { value }
}

extension PartPropertyControl {
    nonisolated var isThemeSpacing: Bool {
        switch self {
        case .themeSpacing, .themePadding, .themeMargin, .themeBorderWidth, .themeRadius, .edges, .corners: true
        default: false
        }
    }
}

/// Everything a slider control needs to draw itself in the Inspector.
nonisolated struct SliderOptions: Equatable, Sendable {
    struct ValueLabel: Equatable, Sendable {
        let value: Double
        let text: String
    }

    struct EndLabel: Equatable, Sendable {
        let title: String?
        let systemImage: String?
    }

    var range: ClosedRange<Double>
    var step: Double = 0
    var ticks: Int = 0
    var unit: String = ""
    var editableValue: Bool = false
    var tickLabels: [ValueLabel] = []
    var valueLabels: [ValueLabel] = []
    var minimumLabel: EndLabel?
    var maximumLabel: EndLabel?
    var neutralValue: Double?

    /// Where marks are drawn: the evenly spaced `ticks` plus every labelled
    /// value, in order, without duplicates.
    var tickValues: [Double] {
        var values = tickLabels.map(\.value)
        if ticks >= 2 {
            let interval = (range.upperBound - range.lowerBound) / Double(ticks - 1)
            values += (0..<ticks).map { range.lowerBound + Double($0) * interval }
        }
        return values.sorted().reduce(into: []) { unique, value in
            if let last = unique.last, abs(last - value) < Self.tolerance { return }
            unique.append(value)
        }
    }

    func tickLabel(at value: Double) -> String? {
        tickLabels.first { abs($0.value - value) < Self.tolerance }?.text
    }

    /// The text that replaces the read-only value when the slider rests on
    /// one of the developer's labelled values.
    func valueLabel(for value: Double) -> String? {
        valueLabels.first { abs($0.value - value) < Self.tolerance }?.text
    }

    private static let tolerance = 0.000_001
}
