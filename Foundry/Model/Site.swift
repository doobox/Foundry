import Foundation

/// The curated language choices Site Settings and Page Info offer up front.
/// Any other BCP-47 tag stays available through each surface's Custom option.
nonisolated struct SiteLanguageOption: Identifiable, Sendable {
    let code: String
    let name: String

    var id: String { code }

    static let common: [SiteLanguageOption] = [
        .init(code: "en", name: "English"),
        .init(code: "en-GB", name: "English (United Kingdom)"),
        .init(code: "en-US", name: "English (United States)"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "es", name: "Spanish"),
        .init(code: "it", name: "Italian"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "zh-Hans", name: "Chinese (Simplified)"),
        .init(code: "zh-Hant", name: "Chinese (Traditional)")
    ]

    /// A structurally valid BCP-47 tag: a 2–8 letter language code followed
    /// by optional alphanumeric subtags, such as en, en-GB, or zh-Hant-TW.
    static func isValidTag(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let languageCode = parts.first,
              (2...8).contains(languageCode.count),
              languageCode.allSatisfy(\.isLetter) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (1...8).contains(part.count) && part.allSatisfy { character in
                character.isLetter || character.isNumber
            }
        }
    }
}

nonisolated enum PageExtensionPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case html
    case php

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .html: "HTML"
        case .php: "PHP"
        }
    }
}

nonisolated struct ProjectFrameworkValues: Codable, Equatable, Sendable {
    var fonts: [FrameworkCustomFont] = []
    var fontSizes: [FrameworkFontSize] = []
    var shadows: [FrameworkShadow] = []
    var colours: [ColourPalette] = []
    var borderWidths: [FrameworkCustomDimension] = []
    var borderRadii: [FrameworkCustomDimension] = []
    var zIndexes: [FrameworkCustomDimension] = []
    var spacing: [CustomSpacingToken] = []

    private enum CodingKeys: String, CodingKey {
        case fonts, fontSizes, shadows, colours, borderWidths, borderRadii, zIndexes, spacing
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fonts = try container.decodeIfPresent([FrameworkCustomFont].self, forKey: .fonts) ?? []
        fontSizes = try container.decodeIfPresent([FrameworkFontSize].self, forKey: .fontSizes) ?? []
        shadows = try container.decodeIfPresent([FrameworkShadow].self, forKey: .shadows) ?? []
        colours = try container.decodeIfPresent([ColourPalette].self, forKey: .colours) ?? []
        borderWidths = try container.decodeIfPresent([FrameworkCustomDimension].self, forKey: .borderWidths) ?? []
        borderRadii = try container.decodeIfPresent([FrameworkCustomDimension].self, forKey: .borderRadii) ?? []
        zIndexes = try container.decodeIfPresent([FrameworkCustomDimension].self, forKey: .zIndexes) ?? []
        spacing = try container.decodeIfPresent([CustomSpacingToken].self, forKey: .spacing) ?? []
    }

    mutating func absorb(_ framework: Framework) {
        fonts = framework.typography.customFonts
        fontSizes = framework.typography.customFontSizes
        shadows = framework.shadows.custom
        colours = framework.colourPalettes.filter { $0.origin == .custom }
        borderWidths = framework.borderWidths.custom
        borderRadii = framework.borderRadii.custom
        zIndexes = framework.zIndexes.custom
        spacing = framework.spacing.custom
    }

    mutating func include(_ framework: Framework) {
        let names = Set(spacing.map(\.name))
        Self.mergeKeepingExisting(framework.spacing.custom.filter { !names.contains($0.name) }, into: &spacing, id: \.id)
        Self.mergeKeepingExisting(framework.typography.customFonts, into: &fonts, id: \.id)
        Self.mergeKeepingExisting(framework.typography.customFontSizes, into: &fontSizes, id: \.id)
        Self.mergeKeepingExisting(framework.shadows.custom, into: &shadows, id: \.id)
        Self.mergeKeepingExisting(framework.borderWidths.custom, into: &borderWidths, id: \.id)
        Self.mergeKeepingExisting(framework.borderRadii.custom, into: &borderRadii, id: \.id)
        Self.mergeKeepingExisting(framework.zIndexes.custom, into: &zIndexes, id: \.id)
    }

    func applied(to framework: Framework) -> Framework {
        var result = framework
        result.spacing.custom = spacing
        Self.mergeReplacingExisting(fonts, into: &result.typography.customFonts, id: \.id)
        Self.mergeReplacingExisting(fontSizes, into: &result.typography.customFontSizes, id: \.id)
        Self.mergeReplacingExisting(shadows, into: &result.shadows.custom, id: \.id)
        Self.mergeReplacingExisting(borderWidths, into: &result.borderWidths.custom, id: \.id)
        Self.mergeReplacingExisting(borderRadii, into: &result.borderRadii.custom, id: \.id)
        Self.mergeReplacingExisting(zIndexes, into: &result.zIndexes.custom, id: \.id)
        result.colourPalettes.removeAll { $0.origin == .custom }
        result.colourPalettes.append(contentsOf: colours)
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

nonisolated struct ProjectFrameworkState: Codable, Equatable, Identifiable, Sendable {
    let sourceID: UUID
    var framework: Framework

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

nonisolated struct PublishingDestination: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var kind: PublishingDestinationKind
    var host: String
    var port: Int
    var username: String
    var remotePath: String
    var s3Bucket: String
    var s3Region: String
    var cleansObsoleteFiles: Bool

    init(
        id: UUID = UUID(),
        name: String = "Publishing Destination",
        kind: PublishingDestinationKind = .local,
        host: String = "",
        port: Int = 0,
        username: String = "",
        remotePath: String = "/",
        s3Bucket: String = "",
        s3Region: String = "us-east-1",
        cleansObsoleteFiles: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.s3Bucket = s3Bucket
        self.s3Region = s3Region
        self.cleansObsoleteFiles = cleansObsoleteFiles
    }
}

nonisolated struct Site: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 14

    var id: UUID
    var schemaVersion: Int
    var name: String
    var language: String
    var publicURL: String
    var titleSuffix: String
    var defaultDescription: String
    var favicon: String
    var webIconAssets: [ProjectAsset]
    var defaultSocialImage: String
    /// Describes the default social image for shares (og:image:alt); only
    /// emitted on pages that use the site-wide image.
    var socialImageAlt: String
    /// The site's social handle, such as @doobox, emitted as twitter:site.
    var socialAccount: String
    var logo: String
    var siteLogoAssets: [ProjectAsset]
    var logoAlt: String
    var generatesCanonicalURLs: Bool
    var generatesSitemap: Bool
    var generatesRobotsTXT: Bool
    var allowsSearchIndexing: Bool
    var customCodeEnabled: Bool
    var headCode: String
    var bodyStartCode: String
    var bodyEndCode: String
    var analyticsCode: String
    var generatesCacheBustingLinks: Bool
    var defaultPageExtension: PageExtensionPreference
    var previewServerPort: Int?
    var minifiesGeneratedOutput: Bool
    var cleansObsoleteExportFiles: Bool
    var publishingDestination: PublishingDestinationKind
    var publishingHost: String
    var publishingPort: Int
    var publishingUsername: String
    var publishingRemotePath: String
    var publishingS3Bucket: String
    var publishingS3Region: String
    var publishingDestinations: [PublishingDestination]
    var defaultPublishingDestinationID: UUID?
    var pages: [Page]
    var pageFolders: [PageFolder]
    var framework: Framework
    var frameworkSourceID: UUID
    var appearanceMode: SiteAppearanceMode = .light
    var projectFrameworkValues: ProjectFrameworkValues
    var frameworkStates: [ProjectFrameworkState]
    /// The Global Parts panel's ordered tree: folders and live-linked
    /// definitions, organized exactly like the templates library.
    var globalPartLibrary: [ReusablePartNode]
    /// Templates saved to this project only — the Templates panel's Project
    /// section. Their definitions reference the document's own assets
    /// directly; embedding happens only when one moves into a pack.
    var projectTemplateLibrary: [ReusablePartNode] = []
    var assetLibrary: [ProjectAssetNode]
    var partPackages: [PartPackageLock]

    var globalParts: [ReusablePartDefinition] { globalPartLibrary.allDefinitions }

    var assets: [ProjectAsset] { assetLibrary.flatMap(\.allAssets) }

    var defaultPublishingDestination: PublishingDestination? {
        publishingDestinations.first { $0.id == defaultPublishingDestinationID } ?? publishingDestinations.first
    }

    mutating func synchronizeLegacyPublishingFields() {
        guard let destination = defaultPublishingDestination else { return }
        defaultPublishingDestinationID = destination.id
        publishingDestination = destination.kind
        publishingHost = destination.host
        publishingPort = destination.port
        publishingUsername = destination.username
        publishingRemotePath = destination.remotePath
        publishingS3Bucket = destination.s3Bucket
        publishingS3Region = destination.s3Region
        cleansObsoleteExportFiles = destination.cleansObsoleteFiles
    }

    mutating func saveActiveFrameworkState() {
        let state = ProjectFrameworkState(sourceID: frameworkSourceID, framework: framework)
        if let index = frameworkStates.firstIndex(where: { $0.sourceID == frameworkSourceID }) {
            frameworkStates[index] = state
        } else {
            frameworkStates.append(state)
        }
    }

    mutating func replacePartSpacingReference(_ reference: String, with replacement: String) {
        for pageIndex in pages.indices {
            for partIndex in pages[pageIndex].parts.indices {
                pages[pageIndex].parts[partIndex].replaceSpacingReference(reference, with: replacement)
            }
        }
        globalPartLibrary.updateAllDefinitions { $0.root.replaceSpacingReference(reference, with: replacement) }
        projectTemplateLibrary.updateAllDefinitions { $0.root.replaceSpacingReference(reference, with: replacement) }
    }

    mutating func replacePartFrameworkReference(_ reference: String, with replacement: String) {
        for pageIndex in pages.indices {
            if let background = pages[pageIndex].backgroundOverride,
               case .packageColor(let updated) = PartProperty.Value.packageColor(background)
                .replacingFrameworkReference(reference, with: replacement) {
                pages[pageIndex].backgroundOverride = updated
            }
            for partIndex in pages[pageIndex].parts.indices {
                pages[pageIndex].parts[partIndex].replaceFrameworkReference(reference, with: replacement)
            }
        }
        globalPartLibrary.updateAllDefinitions {
            $0.root.replaceFrameworkReference(reference, with: replacement)
        }
    }

    mutating func bakePartFrameworkSpacingReference(_ reference: String, amountRem: Double, fallbackToken: String) {
        for pageIndex in pages.indices {
            for partIndex in pages[pageIndex].parts.indices {
                pages[pageIndex].parts[partIndex]
                    .bakeFrameworkSpacingReference(reference, amountRem: amountRem, fallbackToken: fallbackToken)
            }
        }
        globalPartLibrary.updateAllDefinitions {
            $0.root.bakeFrameworkSpacingReference(reference, amountRem: amountRem, fallbackToken: fallbackToken)
        }
    }

    mutating func bakePartFrameworkDimensionReference(_ reference: String, amountPx: Double, fallbackToken: String, isRadius: Bool) {
        for pageIndex in pages.indices {
            for partIndex in pages[pageIndex].parts.indices {
                pages[pageIndex].parts[partIndex]
                    .bakeFrameworkDimensionReference(reference, amountPx: amountPx, fallbackToken: fallbackToken, isRadius: isRadius)
            }
        }
        globalPartLibrary.updateAllDefinitions {
            $0.root.bakeFrameworkDimensionReference(reference, amountPx: amountPx, fallbackToken: fallbackToken, isRadius: isRadius)
        }
    }

    /// Prepares this site to become a new project stamped from a kit: a
    /// fresh identity — publishing destinations and keychain entries key off
    /// the site id — and factory publishing settings, so nothing collides
    /// with a sibling project or leaks the kit author's host details.
    mutating func prepareAsKitCopy(named title: String) {
        id = UUID()
        name = title
        let factory = Site(name: title, pages: [], assetLibrary: [])
        publicURL = factory.publicURL
        publishingDestination = factory.publishingDestination
        publishingHost = factory.publishingHost
        publishingPort = factory.publishingPort
        publishingUsername = factory.publishingUsername
        publishingRemotePath = factory.publishingRemotePath
        publishingS3Bucket = factory.publishingS3Bucket
        publishingS3Region = factory.publishingS3Region
        publishingDestinations = factory.publishingDestinations
        defaultPublishingDestinationID = factory.defaultPublishingDestinationID
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
        webIconAssets: [ProjectAsset] = [],
        defaultSocialImage: String = "",
        socialImageAlt: String = "",
        socialAccount: String = "",
        logo: String = "",
        siteLogoAssets: [ProjectAsset] = [],
        logoAlt: String = "",
        generatesCanonicalURLs: Bool = true,
        generatesSitemap: Bool = true,
        generatesRobotsTXT: Bool = true,
        allowsSearchIndexing: Bool = true,
        customCodeEnabled: Bool = true,
        headCode: String = "",
        bodyStartCode: String = "",
        bodyEndCode: String = "",
        analyticsCode: String = "",
        generatesCacheBustingLinks: Bool = true,
        defaultPageExtension: PageExtensionPreference = .html,
        previewServerPort: Int? = nil,
        minifiesGeneratedOutput: Bool = false,
        cleansObsoleteExportFiles: Bool = true,
        publishingDestination: PublishingDestinationKind = .local,
        publishingHost: String = "",
        publishingPort: Int = 0,
        publishingUsername: String = "",
        publishingRemotePath: String = "/",
        publishingS3Bucket: String = "",
        publishingS3Region: String = "us-east-1",
        publishingDestinations: [PublishingDestination] = [],
        defaultPublishingDestinationID: UUID? = nil,
        pages: [Page],
        pageFolders: [PageFolder] = [],
        framework: Framework = FrameworkBundleStore.systemFramework,
        frameworkSourceID: UUID = FrameworkBundleStore.systemFrameworkID,
        projectFrameworkValues: ProjectFrameworkValues = .init(),
        frameworkStates: [ProjectFrameworkState] = [],
        reusableParts: [ReusablePartDefinition] = [],
        globalParts: [ReusablePartDefinition] = [],
        assetLibrary: [ProjectAssetNode],
        partPackages: [PartPackageLock] = [],
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.language = language
        self.publicURL = publicURL
        self.titleSuffix = titleSuffix
        self.defaultDescription = defaultDescription
        self.favicon = favicon
        self.webIconAssets = webIconAssets
        self.defaultSocialImage = defaultSocialImage
        self.socialImageAlt = socialImageAlt
        self.socialAccount = socialAccount
        self.logo = logo
        self.siteLogoAssets = siteLogoAssets
        self.logoAlt = logoAlt
        self.generatesCanonicalURLs = generatesCanonicalURLs
        self.generatesSitemap = generatesSitemap
        self.generatesRobotsTXT = generatesRobotsTXT
        self.allowsSearchIndexing = allowsSearchIndexing
        self.customCodeEnabled = customCodeEnabled
        self.headCode = headCode
        self.bodyStartCode = bodyStartCode
        self.bodyEndCode = bodyEndCode
        self.analyticsCode = analyticsCode
        self.generatesCacheBustingLinks = generatesCacheBustingLinks
        self.defaultPageExtension = defaultPageExtension
        self.previewServerPort = previewServerPort
        self.minifiesGeneratedOutput = minifiesGeneratedOutput
        self.cleansObsoleteExportFiles = cleansObsoleteExportFiles
        self.publishingDestination = publishingDestination
        self.publishingHost = publishingHost
        self.publishingPort = publishingPort
        self.publishingUsername = publishingUsername
        self.publishingRemotePath = publishingRemotePath
        self.publishingS3Bucket = publishingS3Bucket
        self.publishingS3Region = publishingS3Region
        if publishingDestinations.isEmpty {
            let destination = PublishingDestination(
                name: publishingDestination.title,
                kind: publishingDestination,
                host: publishingHost,
                port: publishingPort,
                username: publishingUsername,
                remotePath: publishingRemotePath,
                s3Bucket: publishingS3Bucket,
                s3Region: publishingS3Region,
                cleansObsoleteFiles: cleansObsoleteExportFiles
            )
            self.publishingDestinations = [destination]
            self.defaultPublishingDestinationID = destination.id
        } else {
            self.publishingDestinations = publishingDestinations
            self.defaultPublishingDestinationID = defaultPublishingDestinationID ?? publishingDestinations.first?.id
        }
        self.pages = pages
        self.pageFolders = pageFolders
        self.framework = framework
        self.frameworkSourceID = frameworkSourceID
        self.projectFrameworkValues = projectFrameworkValues
        self.frameworkStates = frameworkStates
        self.globalPartLibrary = globalParts.map(ReusablePartNode.part)
        self.assetLibrary = assetLibrary
        self.partPackages = partPackages
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        framework: Framework = FrameworkBundleStore.systemFramework,
        reusableParts: [ReusablePartDefinition] = []
    ) {
        self.init(id: id, schemaVersion: schemaVersion, name: name, pages: pages, framework: framework, reusableParts: reusableParts, globalParts: [], assetLibrary: [])
    }

    init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        name: String,
        pages: [Page],
        framework: Framework = FrameworkBundleStore.systemFramework,
        reusableParts: [ReusablePartDefinition] = [],
        assets: [ProjectAsset]
    ) {
        self.init(
            id: id,
            schemaVersion: schemaVersion,
            name: name,
            pages: pages,
            framework: framework,
            reusableParts: reusableParts,
            globalParts: [],
            assetLibrary: assets.map(ProjectAssetNode.asset)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case appearanceMode
        case id, schemaVersion, name, language, publicURL, titleSuffix, defaultDescription, favicon, webIconAssets, defaultSocialImage, socialImageAlt, socialAccount, logo, siteLogoAssets, logoAlt, generatesCanonicalURLs, generatesSitemap, generatesRobotsTXT, allowsSearchIndexing, customCodeEnabled, headCode, bodyStartCode, bodyEndCode, analyticsCode, generatesCacheBustingLinks, defaultPageExtension, previewServerPort, minifiesGeneratedOutput, cleansObsoleteExportFiles, publishingDestination, publishingHost, publishingPort, publishingUsername, publishingRemotePath, publishingS3Bucket, publishingS3Region, publishingDestinations, defaultPublishingDestinationID, pages, pageFolders, framework, frameworkSourceID, projectFrameworkValues, frameworkStates, globalPartLibrary, projectTemplateLibrary, assetLibrary, partPackages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appearanceMode = try container.decode(SiteAppearanceMode.self, forKey: .appearanceMode)
        name = try container.decode(String.self, forKey: .name)
        language = try container.decode(String.self, forKey: .language)
        publicURL = try container.decode(String.self, forKey: .publicURL)
        titleSuffix = try container.decode(String.self, forKey: .titleSuffix)
        defaultDescription = try container.decode(String.self, forKey: .defaultDescription)
        favicon = try container.decode(String.self, forKey: .favicon)
        webIconAssets = try container.decodeIfPresent([ProjectAsset].self, forKey: .webIconAssets) ?? []
        defaultSocialImage = try container.decode(String.self, forKey: .defaultSocialImage)
        socialImageAlt = try container.decodeIfPresent(String.self, forKey: .socialImageAlt) ?? ""
        socialAccount = try container.decodeIfPresent(String.self, forKey: .socialAccount) ?? ""
        logo = try container.decodeIfPresent(String.self, forKey: .logo) ?? ""
        siteLogoAssets = try container.decodeIfPresent([ProjectAsset].self, forKey: .siteLogoAssets) ?? []
        logoAlt = try container.decodeIfPresent(String.self, forKey: .logoAlt) ?? ""
        generatesCanonicalURLs = try container.decode(Bool.self, forKey: .generatesCanonicalURLs)
        generatesSitemap = try container.decode(Bool.self, forKey: .generatesSitemap)
        generatesRobotsTXT = try container.decode(Bool.self, forKey: .generatesRobotsTXT)
        allowsSearchIndexing = try container.decode(Bool.self, forKey: .allowsSearchIndexing)
        customCodeEnabled = try container.decode(Bool.self, forKey: .customCodeEnabled)
        headCode = try container.decode(String.self, forKey: .headCode)
        bodyStartCode = try container.decode(String.self, forKey: .bodyStartCode)
        bodyEndCode = try container.decode(String.self, forKey: .bodyEndCode)
        analyticsCode = try container.decode(String.self, forKey: .analyticsCode)
        generatesCacheBustingLinks = try container.decodeIfPresent(Bool.self, forKey: .generatesCacheBustingLinks) ?? true
        defaultPageExtension = try container.decodeIfPresent(PageExtensionPreference.self, forKey: .defaultPageExtension) ?? .html
        if defaultPageExtension == .automatic { defaultPageExtension = .html }
        previewServerPort = try container.decodeIfPresent(Int.self, forKey: .previewServerPort)
        minifiesGeneratedOutput = try container.decodeIfPresent(Bool.self, forKey: .minifiesGeneratedOutput) ?? false
        cleansObsoleteExportFiles = try container.decode(Bool.self, forKey: .cleansObsoleteExportFiles)
        publishingDestination = try container.decode(PublishingDestinationKind.self, forKey: .publishingDestination)
        publishingHost = try container.decode(String.self, forKey: .publishingHost)
        publishingPort = try container.decode(Int.self, forKey: .publishingPort)
        publishingUsername = try container.decode(String.self, forKey: .publishingUsername)
        publishingRemotePath = try container.decode(String.self, forKey: .publishingRemotePath)
        publishingS3Bucket = try container.decode(String.self, forKey: .publishingS3Bucket)
        publishingS3Region = try container.decode(String.self, forKey: .publishingS3Region)
        if let decodedDestinations = try container.decodeIfPresent([PublishingDestination].self, forKey: .publishingDestinations),
           !decodedDestinations.isEmpty {
            publishingDestinations = decodedDestinations
            let decodedDefault = try container.decodeIfPresent(UUID.self, forKey: .defaultPublishingDestinationID)
            defaultPublishingDestinationID = decodedDestinations.contains(where: { $0.id == decodedDefault })
                ? decodedDefault
                : decodedDestinations.first?.id
        } else {
            let destination = PublishingDestination(
                name: publishingDestination.title,
                kind: publishingDestination,
                host: publishingHost,
                port: publishingPort,
                username: publishingUsername,
                remotePath: publishingRemotePath,
                s3Bucket: publishingS3Bucket,
                s3Region: publishingS3Region,
                cleansObsoleteFiles: cleansObsoleteExportFiles
            )
            publishingDestinations = [destination]
            defaultPublishingDestinationID = destination.id
        }
        pages = try container.decode([Page].self, forKey: .pages)
        pageFolders = try container.decode([PageFolder].self, forKey: .pageFolders)
        framework = try container.decode(Framework.self, forKey: .framework)
        frameworkSourceID = try container.decode(UUID.self, forKey: .frameworkSourceID)
        projectFrameworkValues = try container.decode(ProjectFrameworkValues.self, forKey: .projectFrameworkValues)
        frameworkStates = try container.decode([ProjectFrameworkState].self, forKey: .frameworkStates)
        globalPartLibrary = try container.decodeIfPresent([ReusablePartNode].self, forKey: .globalPartLibrary) ?? []
        projectTemplateLibrary = try container.decodeIfPresent([ReusablePartNode].self, forKey: .projectTemplateLibrary) ?? []
        assetLibrary = try container.decode([ProjectAssetNode].self, forKey: .assetLibrary)
        partPackages = try container.decode([PartPackageLock].self, forKey: .partPackages)
        for pageIndex in pages.indices {
            for partIndex in pages[pageIndex].parts.indices {
                pages[pageIndex].parts[partIndex].migrateLegacyLayoutPartIdentity()
            }
        }
        globalPartLibrary.updateAllDefinitions { definition in
            definition.root.migrateLegacyLayoutPartIdentity()
            if definition.name == "Flexbox", definition.root.type == .stack {
                definition.name = "Stack"
            } else if definition.name == "Flex Item", definition.root.type == .stackItem {
                definition.name = "Stack Item"
            }
        }
        projectTemplateLibrary.updateAllDefinitions { definition in
            definition.root.migrateLegacyLayoutPartIdentity()
            if definition.name == "Flexbox", definition.root.type == .stack {
                definition.name = "Stack"
            } else if definition.name == "Flex Item", definition.root.type == .stackItem {
                definition.name = "Stack Item"
            }
        }
        foldNamedThemeOverrides()
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
        publishedPath(for: asset, managedAssetPaths: assetLibrary.managedExportPaths())
    }

    func publishedPath(for asset: ProjectAsset, managedAssetPaths: [UUID: String]) -> String {
        if siteLogoAssets.contains(where: { $0.id == asset.id }) {
            return SiteLogoStorage.exportPath(for: asset)
        }
        let filename = (asset.filename as NSString).lastPathComponent
        let safeFilename = filename.isEmpty ? asset.storageFilename : filename
        switch asset.exportDirectory {
        case .root:
            return safeFilename
        case .folder(let folderID):
            let folderPath = publishedFolderPath(for: folderID)
            return folderPath.isEmpty ? safeFilename : folderPath + "/" + safeFilename
        case nil:
            return managedAssetPaths[asset.id] ?? asset.exportPath
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

nonisolated extension Site {
    /// The pages the author made: everything except the developer's
    /// in-memory Controls scratch page.
    var authoredPages: [Page] {
        pages.filter { !$0.isDeveloperPlayground }
    }

    /// The site as it is saved, undone and exported, with the Controls
    /// scratch page left out.
    func withoutDeveloperPlayground() -> Site {
        guard pages.contains(where: \.isDeveloperPlayground) else { return self }
        var copy = self
        copy.pages = authoredPages
        return copy
    }
}
