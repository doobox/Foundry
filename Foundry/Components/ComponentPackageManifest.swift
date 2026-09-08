import Foundation

nonisolated struct ComponentPackageManifest: Codable, Equatable, Sendable {
    let minimumAPIVersion: Int
    let identifier: String
    let name: String
    let description: String
    let author: String?
    let version: String
    let category: String
    let tags: [String]
    let slots: [ComponentPackageSlot]
    let properties: [ComponentPackageProperty]
    let render: ComponentPackageRender
    let assets: [ComponentPackageAsset]
    let helpURL: URL?
    let missingComponent: ComponentPackageMissingComponent?
    let requiresPhp: Bool
    let libraries: [ComponentPackageLibraryRequirement]
    let updates: FoundryPackUpdateConfiguration?

    enum CodingKeys: String, CodingKey {
        case minimumAPIVersion
        case identifier = "id"
        case name = "title"
        case description
        case author
        case version
        case category = "group"
        case tags
        case slots
        case properties = "customItems"
        case render = "templates"
        case assets
        case helpURL
        case missingComponent
        case requiresPhp
        case libraries
        case updates
    }

    init(
        minimumAPIVersion: Int,
        identifier: String,
        name: String,
        description: String = "",
        author: String? = nil,
        version: String,
        category: String = "Other",
        tags: [String] = [],
        slots: [ComponentPackageSlot] = [],
        properties: [ComponentPackageProperty] = [],
        render: ComponentPackageRender,
        assets: [ComponentPackageAsset] = [],
        helpURL: URL? = nil,
        missingComponent: ComponentPackageMissingComponent? = nil,
        requiresPhp: Bool = false,
        libraries: [ComponentPackageLibraryRequirement] = [],
        updates: FoundryPackUpdateConfiguration? = nil
    ) {
        self.minimumAPIVersion = minimumAPIVersion
        self.identifier = identifier
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.category = category
        self.tags = tags
        self.slots = slots
        self.properties = properties
        self.render = render
        self.assets = assets
        self.helpURL = helpURL
        self.missingComponent = missingComponent
        self.requiresPhp = requiresPhp
        self.libraries = libraries
        self.updates = updates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumAPIVersion = try container.decode(Int.self, forKey: .minimumAPIVersion)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decode(String.self, forKey: .version)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Other"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        slots = try container.decodeIfPresent([ComponentPackageSlot].self, forKey: .slots) ?? []
        properties = try container.decodeIfPresent([ComponentPackageProperty].self, forKey: .properties) ?? []
        render = try container.decode(ComponentPackageRender.self, forKey: .render)
        assets = try container.decodeIfPresent([ComponentPackageAsset].self, forKey: .assets) ?? []
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
        missingComponent = try container.decodeIfPresent(ComponentPackageMissingComponent.self, forKey: .missingComponent)
        requiresPhp = try container.decodeIfPresent(Bool.self, forKey: .requiresPhp) ?? false
        libraries = try container.decodeIfPresent(
            [ComponentPackageLibraryRequirement].self,
            forKey: .libraries
        ) ?? []
        updates = try container.decodeIfPresent(FoundryPackUpdateConfiguration.self, forKey: .updates)
    }
}

nonisolated struct ComponentPackageAsset: Codable, Equatable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable {
        case page
        case site
    }

    let path: String
    let scope: Scope

    init(path: String, scope: Scope = .page) {
        self.path = path
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            scope: try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .page
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        if scope != .page {
            try container.encode(scope, forKey: .scope)
        }
    }
}

extension ComponentPackageManifest {
    nonisolated func assetDeclaration(containing path: String) -> ComponentPackageAsset? {
        assets.first { asset in
            path == asset.path || path.hasPrefix(asset.path + "/")
        }
    }
}

nonisolated struct ComponentPackageLibraryRequirement: Codable, Equatable, Hashable, Sendable {
    let identifier: String
    let majorVersion: Int

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case majorVersion
    }
}

nonisolated struct ComponentPackageSlot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let accepts: [String]
    let minimum: Int
    let maximum: Int?
}

nonisolated struct ComponentPackageImageRendition: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let maximumDimension: Int

    var effectiveMaximumDimension: Int {
        min(maximumDimension, ComponentImageProcessor.canonicalMaximumDimension)
    }
}

nonisolated struct ComponentPackageProperty: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let group: String
    let control: ComponentPackageControl
    let defaultValue: ComponentPackageValue
    let responsive: Bool
    let subtitles: [String]
    let buttonTexts: [String]
    let buttonIcons: [String]
    let activeButtonTexts: [String]
    let activeButtonIcons: [String]
    let units: [String]
    let toolTip: String?
    let enable: ComponentPackageEnable?
    let alt: String
    let focalPoint: Bool
    let renditions: [ComponentPackageImageRendition]

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case group
        case defaultValue = "default"
        case responsive
        case subtitle
        case buttonText
        case buttonIcon
        case activeButtonText
        case activeButtonIcon
        case units
        case toolTip
        case enable
        case alt
        case focalPoint
        case renditions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "Settings"
        control = try ComponentPackageControl(from: decoder)
        toolTip = try container.decodeIfPresent(String.self, forKey: .toolTip)
        enable = try container.decodeIfPresent(ComponentPackageEnable.self, forKey: .enable)
        alt = try container.decodeIfPresent(String.self, forKey: .alt) ?? ""
        focalPoint = try container.decodeIfPresent(Bool.self, forKey: .focalPoint) ?? false
        renditions = try container.decodeIfPresent([ComponentPackageImageRendition].self, forKey: .renditions) ?? []

        if control.count != nil {
            subtitles = try container.decodeIfPresent([String].self, forKey: .subtitle) ?? []
            buttonTexts = try container.decodeIfPresent([String].self, forKey: .buttonText) ?? []
            buttonIcons = try container.decodeIfPresent([String].self, forKey: .buttonIcon) ?? []
            activeButtonTexts = try container.decodeIfPresent([String].self, forKey: .activeButtonText) ?? []
            activeButtonIcons = try container.decodeIfPresent([String].self, forKey: .activeButtonIcon) ?? []
            units = try container.decodeIfPresent([String].self, forKey: .units) ?? []
        } else {
            subtitles = try container.decodeIfPresent(String.self, forKey: .subtitle).map { [$0] } ?? []
            buttonTexts = try container.decodeIfPresent(String.self, forKey: .buttonText).map { [$0] } ?? []
            buttonIcons = try container.decodeIfPresent(String.self, forKey: .buttonIcon).map { [$0] } ?? []
            activeButtonTexts = try container.decodeIfPresent(String.self, forKey: .activeButtonText).map { [$0] } ?? []
            activeButtonIcons = try container.decodeIfPresent(String.self, forKey: .activeButtonIcon).map { [$0] } ?? []
            units = [try container.decodeIfPresent(String.self, forKey: .units) ?? ""]
        }
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""

        if control.type == .divider || control.type == .info || control.type == .image || control.type == .math {
            defaultValue = try container.decodeIfPresent(ComponentPackageValue.self, forKey: .defaultValue) ?? .string("")
            responsive = control.type == .image && focalPoint
                ? true
                : try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        } else if control.type == .slider {
            let lowerBound = control.minimum ?? 0
            let upperBound = control.maximum ?? 100
            let implicitDefault = min(max(0, lowerBound), upperBound)
            defaultValue = try container.decodeIfPresent(ComponentPackageValue.self, forKey: .defaultValue)
                ?? .number(implicitDefault)
            responsive = try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        } else {
            defaultValue = try container.decode(ComponentPackageValue.self, forKey: .defaultValue)
            responsive = try container.decodeIfPresent(Bool.self, forKey: .responsive) ?? false
        }
    }

    func encode(to encoder: Encoder) throws {
        try control.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if control.count != nil {
            if !units.isEmpty {
                try container.encode(units, forKey: .units)
            }
        } else {
            if let unit = units.first, !unit.isEmpty {
                try container.encode(unit, forKey: .units)
            }
        }
        if !label.isEmpty {
            try container.encode(label, forKey: .label)
        }
        try container.encode(group, forKey: .group)
        try container.encode(defaultValue, forKey: .defaultValue)
        try container.encode(responsive, forKey: .responsive)
        if control.count != nil, !subtitles.isEmpty {
            try container.encode(subtitles, forKey: .subtitle)
        } else if let subtitle = subtitles.first, !subtitle.isEmpty {
            try container.encode(subtitle, forKey: .subtitle)
        }
        if control.count != nil, !buttonTexts.isEmpty {
            try container.encode(buttonTexts, forKey: .buttonText)
        } else if let buttonText = buttonTexts.first, !buttonText.isEmpty {
            try container.encode(buttonText, forKey: .buttonText)
        }
        if control.count != nil {
            if !buttonIcons.isEmpty { try container.encode(buttonIcons, forKey: .buttonIcon) }
            if !activeButtonTexts.isEmpty { try container.encode(activeButtonTexts, forKey: .activeButtonText) }
            if !activeButtonIcons.isEmpty { try container.encode(activeButtonIcons, forKey: .activeButtonIcon) }
        } else {
            if let value = buttonIcons.first, !value.isEmpty { try container.encode(value, forKey: .buttonIcon) }
            if let value = activeButtonTexts.first, !value.isEmpty { try container.encode(value, forKey: .activeButtonText) }
            if let value = activeButtonIcons.first, !value.isEmpty { try container.encode(value, forKey: .activeButtonIcon) }
        }
        try container.encodeIfPresent(toolTip, forKey: .toolTip)
        try container.encodeIfPresent(enable, forKey: .enable)
        if control.type == .image, !alt.isEmpty {
            try container.encode(alt, forKey: .alt)
        }
        if control.type == .image, focalPoint {
            try container.encode(true, forKey: .focalPoint)
        }
        if control.type == .image, !renditions.isEmpty {
            try container.encode(renditions, forKey: .renditions)
        }
    }
}

nonisolated struct ComponentPackageEnable: Codable, Equatable, Sendable {
    let id: String
    let operation: String
    let value: ComponentPackageValue?

    enum CodingKeys: String, CodingKey {
        case id
        case operation
        case value
    }

    init(id: String, operation: String = "==", value: ComponentPackageValue? = nil) {
        self.id = id
        self.operation = operation
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "=="
        value = try container.decodeIfPresent(ComponentPackageValue.self, forKey: .value)
    }
}

nonisolated struct ComponentPackageControl: Codable, Equatable, Sendable {
    enum ButtonSelectionMode: String, Codable, Sendable {
        case multiple
        case single
    }

    enum Kind: String, Codable, Sendable {
        case text
        case textArea
        case number
        case color
        case themeColor
        case icon
        case select
        case link
        case toggle
        case textAlignment
        case divider
        case slider
        case date
        case details
        case info
        case button
        case image
        case math
        case shadow
    }

    let type: Kind
    let minimum: Double?
    let maximum: Double?
    let step: Double?
    let options: [ComponentPackageOption]?
    let themeValues: ComponentPackageThemeValues?
    let allowsCustom: Bool?
    let colorMath: Bool?
    let opacity: Bool?
    let customColor: String?
    let count: Int?
    let ticks: Int?
    let showsValueField: Bool?
    let trueValue: ComponentPackageValue?
    let falseValue: ComponentPackageValue?
    let selectionMode: ButtonSelectionMode?
    let argument1: ComponentPackageValue?
    let argument2: ComponentPackageValue?
    let operation: String?
    let round: Bool?
    let absoluteURL: Bool?
}

nonisolated enum ComponentPackageThemeValueSource: String, Codable, CaseIterable, Sendable {
    case colors
    case fontFamilies
    case fontSizes
    case spacing
    case shadows
}

nonisolated enum ComponentPackageThemeValues: Codable, Equatable, Sendable {
    case source(ComponentPackageThemeValueSource)
    case defaultValue(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ComponentPackageThemeValueSource(rawValue: value).map(Self.source) ?? .defaultValue(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .source(let source): try container.encode(source)
        case .defaultValue(let value): try container.encode(value)
        }
    }
}

nonisolated extension ComponentPackageControl {
    var themeValueSource: ComponentPackageThemeValueSource? {
        if type == .shadow { return .shadows }
        if type == .themeColor { return .colors }
        return switch themeValues {
        case .source(let source): source
        case .defaultValue: nil
        case nil: nil
        }
    }

    var themeValueDefault: String? {
        guard case .defaultValue(let value) = themeValues else { return nil }
        return value
    }
}

nonisolated struct ComponentPackageOption: Codable, Equatable, Identifiable, Sendable {
    let value: String
    let title: String

    var id: String { value }
}

nonisolated enum ComponentPackageValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([ComponentPackageValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([ComponentPackageValue].self) {
            self = .array(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    var stringValue: String {
        if case .string(let value) = self { value } else { "" }
    }

    var numberValue: Double? {
        if case .number(let value) = self { value } else { nil }
    }
}

nonisolated struct ComponentPackageRender: Codable, Equatable, Sendable {
    let html: String
    let editorCSS: String?
    let files: [ComponentPackageTemplateFile]

    enum CodingKeys: String, CodingKey {
        case html
        case editorCSS
        case files
    }

    init(html: String, editorCSS: String? = nil, files: [ComponentPackageTemplateFile] = []) {
        self.html = html
        self.editorCSS = editorCSS
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        html = try container.decode(String.self, forKey: .html)
        editorCSS = try container.decodeIfPresent(String.self, forKey: .editorCSS)
        files = try container.decodeIfPresent([ComponentPackageTemplateFile].self, forKey: .files) ?? []
    }
}

nonisolated struct ComponentPackageTemplateFile: Codable, Equatable, Sendable {
    enum Scope: String, Codable, Sendable {
        case instance
        case page
        case site
    }

    enum Placement: String, Codable, Hashable, Sendable {
        case headStart
        case headEnd
        case bodyStart
        case bodyEnd
    }

    let path: String
    let scope: Scope
    let placement: Placement?
    let closure: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case scope
        case placement
        case closure
    }

    init(path: String, scope: Scope = .instance, placement: Placement? = nil, closure: Bool = true) {
        self.path = path
        self.scope = scope
        self.placement = placement
        self.closure = closure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .instance
        placement = try container.decodeIfPresent(Placement.self, forKey: .placement)
        closure = try container.decodeIfPresent(Bool.self, forKey: .closure) ?? true
    }
}

nonisolated struct ComponentPackageMissingComponent: Codable, Equatable, Sendable {
    let message: String?
    let preview: String?
}

nonisolated struct ComponentPackageLock: Codable, Equatable, Hashable, Sendable {
    let identifier: String
}

nonisolated struct MissingComponentSnapshot: Codable, Equatable, Sendable {
    let name: String
    let category: String
    let previewHTML: String?
    let helpURL: URL?
}
