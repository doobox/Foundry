import Foundation

nonisolated enum PartDragPayload: Equatable, Sendable {
    case library(PartType)
    case reusable(UUID)
    case global(UUID)
    case node(UUID)
    case nodes([UUID])

    init?(_ value: String) {
        if value.hasPrefix(Self.libraryPrefix) {
            let identifier = String(value.dropFirst(Self.libraryPrefix.count))
            guard !identifier.isEmpty else { return nil }
            self = .library(PartType(rawValue: identifier))
        } else if value.hasPrefix(Self.reusablePrefix),
                  let id = UUID(uuidString: String(value.dropFirst(Self.reusablePrefix.count))) {
            self = .reusable(id)
        } else if value.hasPrefix(Self.globalPrefix),
                  let id = UUID(uuidString: String(value.dropFirst(Self.globalPrefix.count))) {
            self = .global(id)
        } else if value.hasPrefix(Self.nodesPrefix) {
            let ids = value.dropFirst(Self.nodesPrefix.count)
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
            guard !ids.isEmpty else { return nil }
            self = .nodes(ids)
        } else if value.hasPrefix(Self.nodePrefix),
                  let id = UUID(uuidString: String(value.dropFirst(Self.nodePrefix.count))) {
            self = .node(id)
        } else {
            return nil
        }
    }

    var stringValue: String {
        switch self {
        case .library(let type): Self.libraryPrefix + type.rawValue
        case .reusable(let id): Self.reusablePrefix + id.uuidString
        case .global(let id): Self.globalPrefix + id.uuidString
        case .node(let id): Self.nodePrefix + id.uuidString
        case .nodes(let ids): Self.nodesPrefix + ids.map(\.uuidString).joined(separator: ",")
        }
    }

    private static let libraryPrefix = "foundry-part-type:"
    private static let reusablePrefix = "foundry-reusable-part:"
    private static let globalPrefix = "foundry-global-part:"
    private static let nodePrefix = "foundry-node:"
    private static let nodesPrefix = "foundry-nodes:"
}
