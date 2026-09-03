import Foundation

nonisolated struct ComponentType: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }
    var definition: ComponentDefinition { ComponentRegistry.definition(for: self) }
    var displayName: String { definition.displayName }
    var systemImage: String { definition.systemImage }
    var libraryDescription: String {
        if let description = definition.package?.manifest.description {
            return description
        }
        return switch self {
        case .container:
            "Groups components inside a constrained, styled wrapper."
        case .section:
            "Creates a full-width page region for organising related content."
        case .columns:
            "Arranges child components in a responsive multi-column layout."
        case .paragraph:
            "Adds editable paragraph or body text to the page."
        case .heading:
            "Adds an editable heading with a selectable semantic level."
        case .button:
            "Creates a styled link for calls to action and navigation."
        case .image:
            "Displays an imported asset or an image from a web address."
        case .divider:
            "Adds a visual rule to separate groups of content."
        case .spacer:
            "Adds adjustable vertical space between components."
        default:
            "Adds this component to the page."
        }
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let container = ComponentType(rawValue: "foundry.layout.container")
    static let section = ComponentType(rawValue: "foundry.layout.section")
    static let columns = ComponentType(rawValue: "foundry.layout.columns")
    static let paragraph = ComponentType(rawValue: "foundry.content.paragraph")
    static let heading = ComponentType(rawValue: "foundry.content.heading")
    static let button = ComponentType(rawValue: "foundry.content.button")
    static let image = ComponentType(rawValue: "foundry.media.image")
    static let divider = ComponentType(rawValue: "foundry.content.divider")
    static let spacer = ComponentType(rawValue: "foundry.layout.spacer")

    static var allCases: [ComponentType] { ComponentRegistry.availableTypes }

}
