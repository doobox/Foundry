import Foundation

nonisolated struct Site: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 6

    let id: UUID
    var schemaVersion: Int
    var name: String
    var language: String
    var publicURL: String
    var titleSuffix: String
    var defaultDescription: String
    var favicon: String
    var defaultSocialImage: String
    var pages: [Page]
    var pageFolders: [PageFolder]
    var theme: Theme
    var reusableComponents: [ReusableComponentDefinition]
    var globalComponents: [ReusableComponentDefinition]
    var assetLibrary: [ProjectAssetNode]
    var componentPackages: [ComponentPackageLock]
    var themePackage: ThemePackageLock?

    var assets: [ProjectAsset] { assetLibrary.flatMap(\.allAssets) }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        language: String = "en",
        publicURL: String = "",
        titleSuffix: String = "",
        defaultDescription: String = "",
        favicon: String = "",
        defaultSocialImage: String = "",
        pages: [Page],
        pageFolders: [PageFolder] = [],
        theme: Theme = .standard,
        reusableComponents: [ReusableComponentDefinition] = [],
        globalComponents: [ReusableComponentDefinition] = [],
        assetLibrary: [ProjectAssetNode],
        componentPackages: [ComponentPackageLock] = [],
        themePackage: ThemePackageLock? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.language = language
        self.publicURL = publicURL
        self.titleSuffix = titleSuffix
        self.defaultDescription = defaultDescription
        self.favicon = favicon
        self.defaultSocialImage = defaultSocialImage
        self.pages = pages
        self.pageFolders = pageFolders
        self.theme = theme
        self.reusableComponents = reusableComponents
        self.globalComponents = globalComponents
        self.assetLibrary = assetLibrary
        self.componentPackages = componentPackages
        self.themePackage = themePackage
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        theme: Theme = .standard,
        reusableComponents: [ReusableComponentDefinition] = []
    ) {
        self.init(id: id, schemaVersion: schemaVersion, name: name, pages: pages, theme: theme, reusableComponents: reusableComponents, globalComponents: [], assetLibrary: [])
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        theme: Theme = .standard,
        reusableComponents: [ReusableComponentDefinition] = [],
        assets: [ProjectAsset]
    ) {
        self.init(
            id: id,
            schemaVersion: schemaVersion,
            name: name,
            pages: pages,
            theme: theme,
            reusableComponents: reusableComponents,
            globalComponents: [],
            assetLibrary: assets.map(ProjectAssetNode.asset)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, name, language, publicURL, titleSuffix, defaultDescription, favicon, defaultSocialImage, pages, pageFolders, theme, reusableComponents, globalComponents, assetLibrary, componentPackages, themePackage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        publicURL = try container.decodeIfPresent(String.self, forKey: .publicURL) ?? ""
        titleSuffix = try container.decodeIfPresent(String.self, forKey: .titleSuffix) ?? ""
        defaultDescription = try container.decodeIfPresent(String.self, forKey: .defaultDescription) ?? ""
        favicon = try container.decodeIfPresent(String.self, forKey: .favicon) ?? ""
        defaultSocialImage = try container.decodeIfPresent(String.self, forKey: .defaultSocialImage) ?? ""
        pages = try container.decode([Page].self, forKey: .pages)
        pageFolders = try container.decodeIfPresent([PageFolder].self, forKey: .pageFolders) ?? []
        theme = try container.decode(Theme.self, forKey: .theme)
        reusableComponents = try container.decodeIfPresent(
            [ReusableComponentDefinition].self,
            forKey: .reusableComponents
        ) ?? []
        globalComponents = try container.decodeIfPresent(
            [ReusableComponentDefinition].self,
            forKey: .globalComponents
        ) ?? []
        assetLibrary = try container.decodeIfPresent([ProjectAssetNode].self, forKey: .assetLibrary) ?? []
        componentPackages = try container.decodeIfPresent([ComponentPackageLock].self, forKey: .componentPackages) ?? []
        themePackage = try container.decodeIfPresent(ThemePackageLock.self, forKey: .themePackage)
    }

    static func starter() -> Site {
        let container = ComponentNode(
            type: .container,
            name: "Hero",
            children: [
                ComponentNode(
                    type: .paragraph,
                    name: "Paragraph",
                    properties: [
                        .init(key: .text, value: .string("Build something remarkable."))
                    ]
                ),
                ComponentNode(
                    type: .button,
                    name: "Call to action",
                    properties: [
                        .init(key: .text, value: .string("Get started")),
                        .init(key: .destination, value: .link(.init(destination: .url("#get-started"))))
                    ]
                )
            ]
        )
        return Site(
            name: "Untitled Site",
            pages: [Page(title: "Home", slug: "index", components: [container])]
        )
    }
}

nonisolated private extension ProjectAssetNode {
    var allAssets: [ProjectAsset] {
        switch self {
        case .asset(let asset): [asset]
        case .folder(let folder): folder.children.flatMap(\.allAssets)
        }
    }
}
