import Foundation

nonisolated struct PageFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var parentID: UUID?
    var order: Int

    init(id: UUID = UUID(), name: String, slug: String, parentID: UUID? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.slug = Page.slugify(slug)
        self.parentID = parentID
        self.order = order
    }
}

nonisolated struct PageMetadata: Codable, Equatable, Sendable {
    var browserTitle: String
    var description: String
    var socialTitle: String
    var socialDescription: String
    var socialImage: String

    init(
        browserTitle: String = "",
        description: String = "",
        socialTitle: String = "",
        socialDescription: String = "",
        socialImage: String = ""
    ) {
        self.browserTitle = browserTitle
        self.description = description
        self.socialTitle = socialTitle
        self.socialDescription = socialDescription
        self.socialImage = socialImage
    }
}

nonisolated struct Page: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var slug: String
    var metadata: PageMetadata
    var components: [ComponentNode]
    var folderID: UUID?
    var parentPageID: UUID?
    var order: Int

    init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        metadata: PageMetadata = .init(),
        components: [ComponentNode] = [],
        folderID: UUID? = nil,
        parentPageID: UUID? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.metadata = metadata
        self.components = components
        self.folderID = folderID
        self.parentPageID = parentPageID
        self.order = order
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, slug, metadata, components, folderID, parentPageID, order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decode(String.self, forKey: .slug)
        metadata = try container.decodeIfPresent(PageMetadata.self, forKey: .metadata) ?? .init()
        components = try container.decode([ComponentNode].self, forKey: .components)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        parentPageID = try container.decodeIfPresent(UUID.self, forKey: .parentPageID)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    static func slugify(_ value: String) -> String {
        let lowered = value.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: .current
        ).lowercased()
        let parts = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = parts.filter { !$0.isEmpty }.joined(separator: "-")
        return slug.isEmpty ? "page" : slug
    }

    func duplicated(title: String, slug: String) -> Page {
        Page(
            title: title,
            slug: slug,
            metadata: metadata,
            components: components.map { $0.duplicated() },
            folderID: folderID,
            parentPageID: parentPageID,
            order: order
        )
    }
}

nonisolated enum PageRouteResolver {
    static func pathSegments(
        for page: Page,
        pages: [Page],
        folders: [PageFolder]
    ) -> [String] {
        guard page.slug != "index" else { return [] }

        var segments = [page.slug]
        var currentPage = page
        var visitedPages: Set<UUID> = [page.id]
        while let parentID = currentPage.parentPageID,
              visitedPages.insert(parentID).inserted,
              let parent = pages.first(where: { $0.id == parentID }) {
            if parent.slug != "index" {
                segments.insert(parent.slug, at: 0)
            }
            currentPage = parent
        }

        var folderID = currentPage.folderID
        var folderSegments: [String] = []
        var visitedFolders = Set<UUID>()
        while let id = folderID,
              visitedFolders.insert(id).inserted,
              let folder = folders.first(where: { $0.id == id }) {
            folderSegments.insert(folder.slug, at: 0)
            folderID = folder.parentID
        }
        return folderSegments + segments
    }

    static func path(for page: Page, pages: [Page], folders: [PageFolder]) -> String {
        let segments = pathSegments(for: page, pages: pages, folders: folders)
        return segments.isEmpty ? "/" : "/" + segments.joined(separator: "/") + "/"
    }
}

nonisolated extension ComponentNode {
    func duplicated() -> ComponentNode {
        return ComponentNode(
            type: type,
            name: name,
            properties: properties.map {
                ComponentProperty(key: $0.key, value: $0.value)
            },
            children: children.map { $0.duplicated() },
            reusableDefinitionID: reusableDefinitionID,
            overridesGlobalDefinition: overridesGlobalDefinition,
            responsiveOverrides: responsiveOverrides
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID) -> ComponentNode {
        var copy = duplicated()
        copy.reusableDefinitionID = definitionID
        return copy
    }

    func duplicatedForReusableDefinition() -> ComponentNode {
        var copy = duplicated()
        copy.reusableDefinitionID = nil
        return copy
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, rootID: UUID) -> ComponentNode {
        ComponentNode(
            id: rootID,
            type: type,
            name: name,
            properties: properties,
            children: children.map { $0.duplicated() },
            reusableDefinitionID: definitionID
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, preservingIDsFrom instance: ComponentNode) -> ComponentNode {
        if instance.overridesGlobalDefinition == true {
            return instance
        }
        return ComponentNode(
            id: instance.id,
            type: type,
            name: name,
            properties: properties,
            children: children.enumerated().map { index, child in
                guard instance.children.indices.contains(index) else { return child.duplicated() }
                return child.duplicatedAsReusableInstance(
                    of: definitionID,
                    preservingIDsFrom: instance.children[index]
                ).withoutReusableDefinitionLink()
            },
            reusableDefinitionID: definitionID,
            overridesGlobalDefinition: false,
            responsiveOverrides: responsiveOverrides
        )
    }

    private func withoutReusableDefinitionLink() -> ComponentNode {
        var copy = self
        copy.reusableDefinitionID = nil
        return copy
    }
}
