import Foundation

nonisolated struct ComponentPackageManifest: Codable, Equatable, Sendable {
    let identifier: String
    let name: String
    let description: String
    let author: String?
    let category: String
    let tags: [String]
    let icon: String
    let slots: [ComponentPackageSlot]
    let properties: [ComponentPackageProperty]
    let themeControls: [ComponentPackageThemeControl]
    let render: ComponentPackageRender
    let runtime: ComponentPackageRuntime?
    let assets: [String]
    let helpURL: URL?
    let missingComponent: ComponentPackageMissingComponent?

    enum CodingKeys: String, CodingKey {
        case identifier = "CFBundleIdentifier"
        case name = "title"
        case description
        case author
        case category = "group"
        case tags
        case icon
        case slots
        case properties = "customItems"
        case themeControls
        case render = "templates"
        case runtime
        case assets
        case helpURL
        case missingComponent
    }

    init(
        identifier: String,
        name: String,
        description: String = "",
        author: String? = nil,
        category: String = "Components",
        tags: [String] = [],
        icon: String = "",
        slots: [ComponentPackageSlot] = [],
        properties: [ComponentPackageProperty] = [],
        themeControls: [ComponentPackageThemeControl] = [],
        render: ComponentPackageRender,
        runtime: ComponentPackageRuntime? = nil,
        assets: [String] = [],
        helpURL: URL? = nil,
        missingComponent: ComponentPackageMissingComponent? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.description = description
        self.author = author
        self.category = category
        self.tags = tags
        self.icon = icon
        self.slots = slots
        self.properties = properties
        self.themeControls = themeControls
        self.render = render
        self.runtime = runtime
        self.assets = assets
        self.helpURL = helpURL
        self.missingComponent = missingComponent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Components"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        slots = try container.decodeIfPresent([ComponentPackageSlot].self, forKey: .slots) ?? []
        properties = try container.decodeIfPresent([ComponentPackageProperty].self, forKey: .properties) ?? []
        themeControls = try container.decodeIfPresent([ComponentPackageThemeControl].self, forKey: .themeControls) ?? []
        render = try container.decode(ComponentPackageRender.self, forKey: .render)
        runtime = try container.decodeIfPresent(ComponentPackageRuntime.self, forKey: .runtime)
        assets = try container.decodeIfPresent([String].self, forKey: .assets) ?? []
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
        missingComponent = try container.decodeIfPresent(ComponentPackageMissingComponent.self, forKey: .missingComponent)
    }
}

nonisolated struct ComponentPackageThemeControl: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case fontFamily
    }

    let type: Kind
    let title: String?
    let group: String?
    let defaultValue: String?
    let responsive: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case group
        case defaultValue = "default"
        case responsive
    }
}

nonisolated struct ComponentPackageSlot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let accepts: [String]
    let minimum: Int
    let maximum: Int?
}

nonisolated struct ComponentPackageProperty: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let section: String
    let control: ComponentPackageControl
    let defaultValue: ComponentPackageValue
    let responsive: Bool
    let inlineEditable: Bool
    let css: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case section
        case control
        case defaultValue = "default"
        case responsive
        case inlineEditable
        case css
    }
}

nonisolated struct ComponentPackageControl: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case textArea
        case number
        case color
        case select
        case url
        case image
        case toggle
    }

    let type: Kind
    let minimum: Double?
    let maximum: Double?
    let step: Double?
    let unit: String?
    let options: [ComponentPackageOption]?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
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
        }
    }
}

nonisolated struct ComponentPackageRender: Codable, Equatable, Sendable {
    let html: String
    let css: String?
    let editorCSS: String?
}

nonisolated struct ComponentPackageRuntime: Codable, Equatable, Sendable {
    enum Capability: String, Codable, Hashable, Sendable {
        case dom
        case timers
        case network
        case localStorage
    }

    let entry: String
    let capabilities: [Capability]
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
