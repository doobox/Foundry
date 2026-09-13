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
    var blocks: [BlockNode]
    var folderID: UUID?
    var parentPageID: UUID?
    var order: Int
    var includeInNavigation: Bool
    /// Nil intentionally follows the theme's Page defaults in both appearances.
    var backgroundOverride: BlockPackageColorValue?

    init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        metadata: PageMetadata = .init(),
        blocks: [BlockNode] = [],
        folderID: UUID? = nil,
        parentPageID: UUID? = nil,
        order: Int = 0,
        includeInNavigation: Bool = true,
        backgroundOverride: BlockPackageColorValue? = nil
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.metadata = metadata
        self.blocks = blocks
        self.folderID = folderID
        self.parentPageID = parentPageID
        self.order = order
        self.includeInNavigation = includeInNavigation
        self.backgroundOverride = backgroundOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, slug, metadata, blocks, folderID, parentPageID, order, includeInNavigation, backgroundOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decode(String.self, forKey: .slug)
        metadata = try container.decode(PageMetadata.self, forKey: .metadata)
        blocks = try container.decode([BlockNode].self, forKey: .blocks)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        parentPageID = try container.decodeIfPresent(UUID.self, forKey: .parentPageID)
        order = try container.decode(Int.self, forKey: .order)
        includeInNavigation = try container.decodeIfPresent(Bool.self, forKey: .includeInNavigation) ?? true
        backgroundOverride = try container.decodeIfPresent(BlockPackageColorValue.self, forKey: .backgroundOverride)
    }

    func backgroundColour(theme: Theme, appearance: SiteAppearance) -> String {
        guard let backgroundOverride else { return theme.color(for: .page, appearance: appearance) }
        return BlockPackageColorResolver.resolve(backgroundOverride, theme: theme, opacity: false, appearance: appearance)
    }

    func backgroundSelection(theme: Theme) -> BlockPackageColorValue {
        if let backgroundOverride { return backgroundOverride }
        let palette = theme.colourPalettes.resolvedPalette(id: "theme.page")
        var value = BlockPackageColorValue(source: "page", customColor: theme.color(for: .page), opacity: 1,
            shade: palette?.lightDefaultShade, darkShade: palette?.darkDefaultShade)
        value.darkCustomColor = theme.color(for: .page, appearance: .dark)
        return value
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
            blocks: blocks.map { $0.duplicated() },
            folderID: folderID,
            parentPageID: parentPageID,
            order: order,
            includeInNavigation: includeInNavigation,
            backgroundOverride: backgroundOverride
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

nonisolated extension BlockNode {
    func duplicated() -> BlockNode {
        return BlockNode(
            type: type,
            name: name,
            properties: properties.map {
                BlockProperty(key: $0.key, value: $0.value)
            },
            children: children.map { $0.duplicated() },
            reusableDefinitionID: reusableDefinitionID,
            overridesGlobalDefinition: overridesGlobalDefinition,
            responsiveOverrides: responsiveOverrides,
            packageLock: packageLock,
            missingPackageSnapshot: missingPackageSnapshot,
            slotID: slotID,
            customClasses: customClasses,
            rootAttributes: rootAttributes
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID) -> BlockNode {
        var copy = duplicated()
        copy.reusableDefinitionID = definitionID
        return copy
    }

    func duplicatedForReusableDefinition() -> BlockNode {
        var copy = duplicated()
        copy.reusableDefinitionID = nil
        return copy
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, rootID: UUID) -> BlockNode {
        BlockNode(
            id: rootID,
            type: type,
            name: name,
            properties: properties,
            children: children.map { $0.duplicated() },
            reusableDefinitionID: definitionID,
            responsiveOverrides: responsiveOverrides,
            packageLock: packageLock,
            missingPackageSnapshot: missingPackageSnapshot,
            slotID: slotID,
            customClasses: customClasses,
            rootAttributes: rootAttributes
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, preservingIDsFrom instance: BlockNode) -> BlockNode {
        if instance.overridesGlobalDefinition == true {
            return instance
        }
        return BlockNode(
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
            responsiveOverrides: responsiveOverrides,
            packageLock: packageLock,
            missingPackageSnapshot: missingPackageSnapshot,
            slotID: slotID,
            anchor: instance.anchor,
            customClasses: customClasses,
            rootAttributes: rootAttributes
        )
    }

    private func withoutReusableDefinitionLink() -> BlockNode {
        var copy = self
        copy.reusableDefinitionID = nil
        return copy
    }
}
