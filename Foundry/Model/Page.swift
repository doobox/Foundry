import Foundation

nonisolated struct PageFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var parentID: UUID?
    var order: Int
    /// Menus mirror the Pages panel: a folder appears as a non-link group
    /// containing its pages. Opting out keeps the folder organizational —
    /// its pages surface in place, like pages excluded from navigation.
    var includeInNavigation: Bool
    init(id: UUID = UUID(), name: String, slug: String, parentID: UUID? = nil, order: Int = 0, includeInNavigation: Bool = true) {
        self.id = id
        self.name = name
        self.slug = Page.slugify(slug)
        self.parentID = parentID
        self.order = order
        self.includeInNavigation = includeInNavigation
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
    var parts: [PartNode]
    var folderID: UUID?
    var parentPageID: UUID?
    var order: Int
    var includeInNavigation: Bool
    /// The extension chosen when the page was created. PHP requirements from
    /// parts still promote the rendered page to PHP regardless of this value.
    var preferredExtension: PageExtensionPreference?
    /// Publishes the page into an explicit directory from the site root
    /// instead of the one derived from the page tree. Slash-separated
    /// segments; the empty string targets the site root. Nil follows the
    /// page tree. Never applies to the home page.
    var folderOverride: String?
    /// Replaces the exported `index` filename. Stored with an explicit
    /// `html`/`php` extension when the author typed one; without one the
    /// page's normal extension rules apply. Nil publishes `index`. Pages
    /// with a non-`index` filename link with the filename visible.
    var filenameOverride: String?
    /// BCP-47 language for this page's `<html lang>`; nil inherits the site.
    var language: String?
    /// Emits a per-page noindex when false; the sitemap also skips the page
    /// so crawlers aren't invited to a page they're told not to index.
    var includeInSearch: Bool
    var includeInSitemap: Bool
    /// Nil intentionally follows the framework's Page defaults in both appearances.
    var backgroundOverride: PartPackageColorValue?
    /// The developer's Controls page: a scratch page the Parts panel fills
    /// with a control showcase. It is never exported, listed or linked.
    var isDeveloperPlayground: Bool

    init(
        id: UUID = UUID(),
        title: String,
        slug: String,
        metadata: PageMetadata = .init(),
        parts: [PartNode] = [],
        folderID: UUID? = nil,
        parentPageID: UUID? = nil,
        order: Int = 0,
        includeInNavigation: Bool = true,
        preferredExtension: PageExtensionPreference? = nil,
        folderOverride: String? = nil,
        filenameOverride: String? = nil,
        language: String? = nil,
        includeInSearch: Bool = true,
        includeInSitemap: Bool = true,
        backgroundOverride: PartPackageColorValue? = nil,
        isDeveloperPlayground: Bool = false
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.metadata = metadata
        self.parts = parts
        self.folderID = folderID
        self.parentPageID = parentPageID
        self.order = order
        self.includeInNavigation = includeInNavigation
        self.preferredExtension = preferredExtension
        self.folderOverride = folderOverride
        self.filenameOverride = filenameOverride
        self.language = language
        self.includeInSearch = includeInSearch
        self.includeInSitemap = includeInSitemap
        self.backgroundOverride = backgroundOverride
        self.isDeveloperPlayground = isDeveloperPlayground
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, slug, metadata, parts, folderID, parentPageID, order, includeInNavigation, preferredExtension,
             folderOverride, filenameOverride, language, includeInSearch, includeInSitemap, backgroundOverride,
             isDeveloperPlayground
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decode(String.self, forKey: .slug)
        metadata = try container.decode(PageMetadata.self, forKey: .metadata)
        parts = try container.decode([PartNode].self, forKey: .parts)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        parentPageID = try container.decodeIfPresent(UUID.self, forKey: .parentPageID)
        order = try container.decode(Int.self, forKey: .order)
        includeInNavigation = try container.decodeIfPresent(Bool.self, forKey: .includeInNavigation) ?? true
        preferredExtension = try container.decodeIfPresent(PageExtensionPreference.self, forKey: .preferredExtension)
        folderOverride = try container.decodeIfPresent(String.self, forKey: .folderOverride)
        filenameOverride = try container.decodeIfPresent(String.self, forKey: .filenameOverride)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        includeInSearch = try container.decodeIfPresent(Bool.self, forKey: .includeInSearch) ?? true
        includeInSitemap = try container.decodeIfPresent(Bool.self, forKey: .includeInSitemap) ?? true
        backgroundOverride = try container.decodeIfPresent(PartPackageColorValue.self, forKey: .backgroundOverride)
        isDeveloperPlayground = try container.decodeIfPresent(Bool.self, forKey: .isDeveloperPlayground) ?? false
    }

    func backgroundColour(framework: Framework, appearance: SiteAppearance) -> String {
        guard let backgroundOverride else { return framework.color(for: .page, appearance: appearance) }
        return PartPackageColorResolver.resolve(backgroundOverride, framework: framework, opacity: false, appearance: appearance)
    }

    func backgroundSelection(framework: Framework) -> PartPackageColorValue {
        if let backgroundOverride { return backgroundOverride }
        let palette = framework.colourPalettes.resolvedPalette(id: "framework.page")
        var value = PartPackageColorValue(source: "page", customColor: framework.color(for: .page), opacity: 1,
            shade: palette?.lightDefaultShade, darkShade: palette?.darkDefaultShade)
        value.darkCustomColor = framework.color(for: .page, appearance: .dark)
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

    /// Folder and filename overrides intentionally do not copy: the copy
    /// would publish over the original.
    func duplicated(title: String, slug: String) -> Page {
        Page(
            title: title,
            slug: slug,
            metadata: metadata,
            parts: parts.map { $0.duplicated() },
            folderID: folderID,
            parentPageID: parentPageID,
            order: order,
            includeInNavigation: includeInNavigation,
            preferredExtension: preferredExtension,
            language: language,
            includeInSearch: includeInSearch,
            includeInSitemap: includeInSitemap,
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
        if let override = page.folderOverride {
            return override.split(separator: "/").map(String.init)
        }

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

nonisolated extension PartNode {
    func duplicated() -> PartNode {
        return PartNode(
            type: type,
            name: name,
            properties: properties.map {
                PartProperty(key: $0.key, value: $0.value)
            },
            children: children.map { $0.duplicated() },
            reusableDefinitionID: reusableDefinitionID,
            overridesGlobalDefinition: overridesGlobalDefinition,
            responsiveOverrides: responsiveOverrides,
            packageLock: packageLock,
            missingPackageSnapshot: missingPackageSnapshot,
            slotID: slotID,
            customClasses: customClasses,
            customCSS: customCSS,
            rootAttributes: rootAttributes
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID) -> PartNode {
        var copy = duplicated()
        copy.reusableDefinitionID = definitionID
        return copy
    }

    func duplicatedForReusableDefinition() -> PartNode {
        var copy = duplicated()
        copy.reusableDefinitionID = nil
        return copy
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, rootID: UUID) -> PartNode {
        PartNode(
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
            customCSS: customCSS,
            rootAttributes: rootAttributes
        )
    }

    func duplicatedAsReusableInstance(of definitionID: UUID, preservingIDsFrom instance: PartNode) -> PartNode {
        if instance.overridesGlobalDefinition == true {
            return instance
        }
        return PartNode(
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
            customCSS: customCSS,
            rootAttributes: rootAttributes
        )
    }

    private func withoutReusableDefinitionLink() -> PartNode {
        var copy = self
        copy.reusableDefinitionID = nil
        return copy
    }
}
