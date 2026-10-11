import Foundation

nonisolated extension ProjectMutationImpact {
    /// nil means shared or uncertain impact: invalidate every page.
    func affectedPageIDs(in site: Site) -> Set<UUID>? {
        let partIDs: [UUID]
        switch self {
        case .partProperty(let id, _): partIDs = [id]
        case .partProperties(let ids, _): partIDs = ids
        case .partStructure(let ownerID):
            guard let ownerID else { return nil }
            partIDs = [ownerID]
        case .publishingOnly: return []
        case .page, .theme, .assets, .package: return nil
        }
        guard !partIDs.isEmpty else { return nil }
        var pages = Set<UUID>()
        for id in partIDs {
            // Globals or unresolved owners can affect more than one page.
            guard let page = site.pages.first(where: { $0.parts.node(withID: id) != nil }) else { return nil }
            pages.insert(page.id)
        }
        return pages
    }
}
