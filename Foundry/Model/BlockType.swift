import Foundation

nonisolated struct BlockType: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }
    var definition: BlockDefinition { BlockRegistry.definition(for: self) }
    var displayName: String { definition.displayName }
    var systemImage: String { definition.systemImage }
    var libraryDescription: String {
        if let description = definition.package?.manifest.description {
            return description
        }
        return switch self {
        case .container:
            "Groups blocks inside a constrained, styled wrapper."
        case .section:
            "Creates a full-width page region for organising related content."
        case .columns:
            "Arranges child blocks in a responsive multi-column layout."
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
            "Adds adjustable vertical space between blocks."
        default:
            "Adds this block to the page."
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

    static let container = BlockType(rawValue: "foundry.layout.container")
    static let section = BlockType(rawValue: "foundry.layout.section")
    static let columns = BlockType(rawValue: "foundry.layout.columns")
    static let paragraph = BlockType(rawValue: "foundry.content.paragraph")
    static let heading = BlockType(rawValue: "foundry.content.heading")
    static let button = BlockType(rawValue: "foundry.content.button")
    static let image = BlockType(rawValue: "foundry.media.image")
    static let divider = BlockType(rawValue: "foundry.content.divider")
    static let spacer = BlockType(rawValue: "foundry.layout.spacer")

    static var allCases: [BlockType] { BlockRegistry.availableTypes }

}
