import Foundation

nonisolated struct ProjectThemeValues: Codable, Equatable, Sendable {
    var spacing: [ThemeSpacing] = []
    var fonts: [ThemeCustomFont] = []
    var fontSizes: [ThemeFontSize] = []

    mutating func absorb(_ theme: Theme) {
        spacing = theme.spacing.custom
        fonts = theme.typography.customFonts
        fontSizes = theme.typography.customFontSizes
    }

    mutating func include(_ theme: Theme) {
        Self.mergeKeepingExisting(theme.spacing.custom, into: &spacing, id: \.id)
        Self.mergeKeepingExisting(theme.typography.customFonts, into: &fonts, id: \.id)
        Self.mergeKeepingExisting(theme.typography.customFontSizes, into: &fontSizes, id: \.id)
    }

    func applied(to theme: Theme) -> Theme {
        var result = theme
        Self.mergeReplacingExisting(spacing, into: &result.spacing.custom, id: \.id)
        Self.mergeReplacingExisting(fonts, into: &result.typography.customFonts, id: \.id)
        Self.mergeReplacingExisting(fontSizes, into: &result.typography.customFontSizes, id: \.id)
        return result
    }

    private static func mergeReplacingExisting<Element, ID: Hashable>(
        _ incoming: [Element],
        into values: inout [Element],
        id: KeyPath<Element, ID>
    ) {
        for value in incoming {
            if let index = values.firstIndex(where: { $0[keyPath: id] == value[keyPath: id] }) {
                values[index] = value
            } else {
                values.append(value)
            }
        }
    }

    private static func mergeKeepingExisting<Element, ID: Hashable>(
        _ incoming: [Element],
        into values: inout [Element],
        id: KeyPath<Element, ID>
    ) {
        let existing = Set(values.map { $0[keyPath: id] })
        values.append(contentsOf: incoming.filter { !existing.contains($0[keyPath: id]) })
    }
}

nonisolated struct ProjectThemeState: Codable, Equatable, Identifiable, Sendable {
    let sourceID: UUID
    var theme: Theme

    var id: UUID { sourceID }
}

nonisolated enum PublishingDestinationKind: String, Codable, CaseIterable, Sendable {
    case local
    case sftp
    case ftp
    case amazonS3
    case ftps

    var title: String {
        switch self {
        case .local: "Local Folder"
        case .sftp: "SFTP"
        case .ftp: "FTP (Legacy)"
        case .ftps: "FTPS (Legacy)"
        case .amazonS3: "Amazon S3"
        }
    }

    var defaultPort: Int {
        switch self {
        case .local: 0
        case .sftp: 22
        case .ftp, .ftps: 21
        case .amazonS3: 443
        }
    }

    var usesTLS: Bool {
        self == .ftps || self == .amazonS3
    }
}

nonisolated struct Site: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 11

    let id: UUID
    var schemaVersion: Int
    var name: String
    var language: String
    var publicURL: String
    var titleSuffix: String
    var defaultDescription: String
    var favicon: String
    var defaultSocialImage: String
    var generatesCanonicalURLs: Bool
    var generatesSitemap: Bool
    var generatesRobotsTXT: Bool
    var allowsSearchIndexing: Bool
    var customCodeEnabled: Bool
    var headCode: String
    var bodyStartCode: String
    var bodyEndCode: String
    var analyticsCode: String
    var cleansObsoleteExportFiles: Bool
    var publishingDestination: PublishingDestinationKind
    var publishingHost: String
    var publishingPort: Int
    var publishingUsername: String
    var publishingRemotePath: String
    var publishingS3Bucket: String
    var publishingS3Region: String
    var pages: [Page]
    var pageFolders: [PageFolder]
    var theme: Theme
    var themeSourceID: UUID
    var projectThemeValues: ProjectThemeValues
    var themeStates: [ProjectThemeState]
    var reusableComponents: [ReusableComponentDefinition]
    var globalComponents: [ReusableComponentDefinition]
    var assetLibrary: [ProjectAssetNode]
    var componentPackages: [ComponentPackageLock]

    var assets: [ProjectAsset] { assetLibrary.flatMap(\.allAssets) }

    mutating func saveActiveThemeState() {
        let state = ProjectThemeState(sourceID: themeSourceID, theme: theme)
        if let index = themeStates.firstIndex(where: { $0.sourceID == themeSourceID }) {
            themeStates[index] = state
        } else {
            themeStates.append(state)
        }
    }

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
        generatesCanonicalURLs: Bool = true,
        generatesSitemap: Bool = true,
        generatesRobotsTXT: Bool = true,
        allowsSearchIndexing: Bool = true,
        customCodeEnabled: Bool = true,
        headCode: String = "",
        bodyStartCode: String = "",
        bodyEndCode: String = "",
        analyticsCode: String = "",
        cleansObsoleteExportFiles: Bool = true,
        publishingDestination: PublishingDestinationKind = .local,
        publishingHost: String = "",
        publishingPort: Int = 0,
        publishingUsername: String = "",
        publishingRemotePath: String = "/",
        publishingS3Bucket: String = "",
        publishingS3Region: String = "us-east-1",
        pages: [Page],
        pageFolders: [PageFolder] = [],
        theme: Theme = ThemeBundleStore.systemTheme,
        themeSourceID: UUID = ThemeBundleStore.systemThemeID,
        projectThemeValues: ProjectThemeValues = .init(),
        themeStates: [ProjectThemeState] = [],
        reusableComponents: [ReusableComponentDefinition] = [],
        globalComponents: [ReusableComponentDefinition] = [],
        assetLibrary: [ProjectAssetNode],
        componentPackages: [ComponentPackageLock] = [],
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
        self.generatesCanonicalURLs = generatesCanonicalURLs
        self.generatesSitemap = generatesSitemap
        self.generatesRobotsTXT = generatesRobotsTXT
        self.allowsSearchIndexing = allowsSearchIndexing
        self.customCodeEnabled = customCodeEnabled
        self.headCode = headCode
        self.bodyStartCode = bodyStartCode
        self.bodyEndCode = bodyEndCode
        self.analyticsCode = analyticsCode
        self.cleansObsoleteExportFiles = cleansObsoleteExportFiles
        self.publishingDestination = publishingDestination
        self.publishingHost = publishingHost
        self.publishingPort = publishingPort
        self.publishingUsername = publishingUsername
        self.publishingRemotePath = publishingRemotePath
        self.publishingS3Bucket = publishingS3Bucket
        self.publishingS3Region = publishingS3Region
        self.pages = pages
        self.pageFolders = pageFolders
        self.theme = theme
        self.themeSourceID = themeSourceID
        self.projectThemeValues = projectThemeValues
        self.themeStates = themeStates
        self.reusableComponents = reusableComponents
        self.globalComponents = globalComponents
        self.assetLibrary = assetLibrary
        self.componentPackages = componentPackages
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        theme: Theme = ThemeBundleStore.systemTheme,
        reusableComponents: [ReusableComponentDefinition] = []
    ) {
        self.init(id: id, schemaVersion: schemaVersion, name: name, pages: pages, theme: theme, reusableComponents: reusableComponents, globalComponents: [], assetLibrary: [])
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        theme: Theme = ThemeBundleStore.systemTheme,
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
        case id, schemaVersion, name, language, publicURL, titleSuffix, defaultDescription, favicon, defaultSocialImage, generatesCanonicalURLs, generatesSitemap, generatesRobotsTXT, allowsSearchIndexing, customCodeEnabled, headCode, bodyStartCode, bodyEndCode, analyticsCode, cleansObsoleteExportFiles, publishingDestination, publishingHost, publishingPort, publishingUsername, publishingRemotePath, publishingS3Bucket, publishingS3Region, pages, pageFolders, theme, themeSourceID, projectThemeValues, themeStates, reusableComponents, globalComponents, assetLibrary, componentPackages
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
        generatesCanonicalURLs = try container.decodeIfPresent(Bool.self, forKey: .generatesCanonicalURLs) ?? true
        generatesSitemap = try container.decodeIfPresent(Bool.self, forKey: .generatesSitemap) ?? true
        generatesRobotsTXT = try container.decodeIfPresent(Bool.self, forKey: .generatesRobotsTXT) ?? true
        allowsSearchIndexing = try container.decodeIfPresent(Bool.self, forKey: .allowsSearchIndexing) ?? true
        customCodeEnabled = try container.decodeIfPresent(Bool.self, forKey: .customCodeEnabled) ?? true
        headCode = try container.decodeIfPresent(String.self, forKey: .headCode) ?? ""
        bodyStartCode = try container.decodeIfPresent(String.self, forKey: .bodyStartCode) ?? ""
        bodyEndCode = try container.decodeIfPresent(String.self, forKey: .bodyEndCode) ?? ""
        analyticsCode = try container.decodeIfPresent(String.self, forKey: .analyticsCode) ?? ""
        cleansObsoleteExportFiles = try container.decodeIfPresent(Bool.self, forKey: .cleansObsoleteExportFiles) ?? true
        publishingDestination = try container.decodeIfPresent(PublishingDestinationKind.self, forKey: .publishingDestination) ?? .local
        publishingHost = try container.decodeIfPresent(String.self, forKey: .publishingHost) ?? ""
        publishingPort = try container.decodeIfPresent(Int.self, forKey: .publishingPort) ?? 0
        publishingUsername = try container.decodeIfPresent(String.self, forKey: .publishingUsername) ?? ""
        publishingRemotePath = try container.decodeIfPresent(String.self, forKey: .publishingRemotePath) ?? "/"
        publishingS3Bucket = try container.decodeIfPresent(String.self, forKey: .publishingS3Bucket) ?? ""
        publishingS3Region = try container.decodeIfPresent(String.self, forKey: .publishingS3Region) ?? "us-east-1"
        pages = try container.decode([Page].self, forKey: .pages)
        pageFolders = try container.decodeIfPresent([PageFolder].self, forKey: .pageFolders) ?? []
        theme = try container.decode(Theme.self, forKey: .theme)
        themeSourceID = try container.decode(UUID.self, forKey: .themeSourceID)
        projectThemeValues = try container.decode(ProjectThemeValues.self, forKey: .projectThemeValues)
        themeStates = try container.decode([ProjectThemeState].self, forKey: .themeStates)
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
    }

    static func starter() -> Site {
        return Site(
            name: "Untitled Site",
            pages: [Page(title: "Home", slug: "index")]
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

nonisolated extension Site {
    func publishedPath(for asset: ProjectAsset) -> String {
        let filename = (asset.filename as NSString).lastPathComponent
        let safeFilename = filename.isEmpty ? asset.storageFilename : filename
        switch asset.exportDirectory {
        case .root:
            return safeFilename
        case .folder(let folderID):
            let folderPath = publishedFolderPath(for: folderID)
            return folderPath.isEmpty ? safeFilename : folderPath + "/" + safeFilename
        case nil:
            return assetLibrary.managedExportPath(for: asset)
        }
    }

    private func publishedFolderPath(for folderID: UUID) -> String {
        var currentID: UUID? = folderID
        var slugs: [String] = []
        var visited = Set<UUID>()
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = pageFolders.first(where: { $0.id == id }) {
            slugs.insert(folder.slug, at: 0)
            currentID = folder.parentID
        }
        return slugs.joined(separator: "/")
    }
}
