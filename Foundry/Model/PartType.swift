import Foundation

nonisolated struct PartType: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }
    var definition: PartDefinition { PartRegistry.definition(for: self) }
    var displayName: String { definition.displayName }
    // Parts wear one shared symbol; packs differentiate with icon.svg images.
    var systemImage: String { "puzzlepiece.extension" }
    var libraryDescription: String {
        if let description = definition.package?.manifest.description {
            return description
        }
        return switch self {
        case .section:
            "Creates a full-width page section with constrained inner content."
        case .stack:
            "Stacks child parts vertically or horizontally."
        case .grid:
            "Arranges child parts with CSS Grid."
        case .box:
            "Groups content in a neutral styleable box."
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
        default:
            "Adds this part to the page."
        }
    }

    init(rawValue: String) {
        self.rawValue = Self.migratedIdentifier(rawValue)
    }

    static func migratedIdentifier(_ identifier: String) -> String {
        switch identifier {
        case "foundry.layout.flexbox": "foundry.layout.stack"
        case "foundry.layout.flexitem": "foundry.layout.stackitem"
        default: identifier
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let section = PartType(rawValue: "foundry.layout.section")
    static let stack = PartType(rawValue: "foundry.layout.stack")
    static let stackItem = PartType(rawValue: "foundry.layout.stackitem")
    static let grid = PartType(rawValue: "foundry.layout.grid")
    static let gridItem = PartType(rawValue: "foundry.layout.griditem")
    static let box = PartType(rawValue: "foundry.layout.box")
    static let paragraph = PartType(rawValue: "foundry.content.paragraph")
    static let heading = PartType(rawValue: "foundry.content.heading")
    static let button = PartType(rawValue: "foundry.content.button")
    static let image = PartType(rawValue: "foundry.media.image")
    static let svg = PartType(rawValue: "foundry.media.svg")
    static let video = PartType(rawValue: "foundry.media.video")
    static let divider = PartType(rawValue: "foundry.layout.divider")

    static var allCases: [PartType] { PartRegistry.availableTypes }

}
