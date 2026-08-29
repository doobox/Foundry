import Foundation

nonisolated struct ComponentPackageManifest: Codable, Equatable, Sendable {
    let type: FoundryPackType
    let identifier: String
    let name: String
    let description: String
    let author: String?
    let version: String?
    let category: String
    let tags: [String]
    let slots: [ComponentPackageSlot]
    let properties: [ComponentPackageProperty]
    let render: ComponentPackageRender
    let runtime: ComponentPackageRuntime?
    let assets: [String]
    let helpURL: URL?
    let missingComponent: ComponentPackageMissingComponent?

    enum CodingKeys: String, CodingKey {
        case type
        case identifier = "CFBundleIdentifier"
        case name = "title"
        case description
        case author
        case version
        case category = "group"
        case tags
        case slots
        case properties = "customItems"
        case render = "templates"
        case runtime
        case assets
        case helpURL
        case missingComponent
    }

    init(
        type: FoundryPackType = .component,
        identifier: String,
        name: String,
        description: String = "",
        author: String? = nil,
        version: String? = nil,
        category: String = "Other",
        tags: [String] = [],
        slots: [ComponentPackageSlot] = [],
        properties: [ComponentPackageProperty] = [],
        render: ComponentPackageRender,
        runtime: ComponentPackageRuntime? = nil,
        assets: [String] = [],
        helpURL: URL? = nil,
        missingComponent: ComponentPackageMissingComponent? = nil
    ) {
        self.type = type
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
        self.runtime = runtime
        self.assets = assets
        self.helpURL = helpURL
        self.missingComponent = missingComponent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(FoundryPackType.self, forKey: .type)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Other"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        slots = try container.decodeIfPresent([ComponentPackageSlot].self, forKey: .slots) ?? []
        properties = try container.decodeIfPresent([ComponentPackageProperty].self, forKey: .properties) ?? []
        render = try container.decode(ComponentPackageRender.self, forKey: .render)
        runtime = try container.decodeIfPresent(ComponentPackageRuntime.self, forKey: .runtime)
        assets = try container.decodeIfPresent([String].self, forKey: .assets) ?? []
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
        missingComponent = try container.decodeIfPresent(ComponentPackageMissingComponent.self, forKey: .missingComponent)
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
        case fontFamily
        case fontSize
    }

    let type: Kind
    let minimum: Double?
    let maximum: Double?
    let step: Double?
    let unit: String?
    let options: [ComponentPackageOption]?
    let themeValues: Bool?
    let colorMath: Bool?
    let opacity: Bool?
    let customColor: String?
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

    enum Placement: String, Codable, Sendable {
        case headStart
        case headEnd
        case bodyStart
        case bodyEnd
    }

    let path: String
    let scope: Scope
    let placement: Placement?

    enum CodingKeys: String, CodingKey {
        case path
        case scope
        case placement
    }

    init(path: String, scope: Scope = .instance, placement: Placement? = nil) {
        self.path = path
        self.scope = scope
        self.placement = placement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .instance
        placement = try container.decodeIfPresent(Placement.self, forKey: .placement)
    }
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
