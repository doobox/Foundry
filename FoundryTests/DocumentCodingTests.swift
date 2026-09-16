import Foundation
import Testing
@testable import Foundry

@MainActor
struct DocumentCodingTests {
    @Test
    func fileBackedAssetsSurviveSnapshotOwnerAndRoundTrip() throws {
        let bytes = Data(repeating: 123, count: 2 * 1_024 * 1_024)
        let asset = ProjectAsset(filename: "large.bin", mediaType: "application/octet-stream", byteCount: bytes.count)
        var site = Site.starter()
        site.assetLibrary = [.asset(asset)]
        var snapshot: FoundryDocumentSnapshot? = .init(site: site, assetData: [asset.id: bytes])
        let retained = try #require(snapshot?.assetData[asset.id])
        snapshot = nil
        #expect(retained == bytes)
        // Saving still uses the same Data API, including after its backing owner dies.
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "project.json": FileWrapper(regularFileWithContents: try JSONEncoder().encode(site)),
            "assets": FileWrapper(directoryWithFileWrappers: [asset.storageFilename: FileWrapper(regularFileWithContents: retained)])
        ])
        let loaded = try FoundryDocument.decodeSnapshot(from: wrapper)
        #expect(loaded.assetData[asset.id] == bytes)
    }
    @Test
    func responsiveOverridesRoundTripWithoutDuplicatingBaseProperties() throws {
        var site = TestSiteFixtures.populatedSite()
        let partID = try #require(site.pages.first?.parts.first?.id)
        let key = PartProperty.Key(rawValue: "themePadding")
        let base = ThemePaddingValue()
        var override = base
        var edge = override.value(for: .top)
        edge.token = "lg"
        override.set(edge, for: .top)
        site.updatePart(id: partID) {
            $0.setResponsiveProperty(key, value: .themePadding(base), at: .mobile)
            $0.setResponsiveProperty(key, value: .themePadding(override), at: .small)
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let part = try #require(decoded.part(withID: partID))

        #expect(part.propertyValue(key) == .themePadding(base))
        #expect(part.propertyValue(key, at: .mobile) == .themePadding(base))
        #expect(part.propertyValue(key, at: .small) == .themePadding(override))
        #expect(part.propertyValue(key, at: .medium) == .themePadding(override))
    }

    @Test
    func siteRoundTripsThroughProjectJSON() throws {
        let original = Site.starter()
        let data = try FoundryDocument.encoder.encode(original)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded == original)
        #expect(decoded.pages.first?.parts.first?.id ==
                original.pages.first?.parts.first?.id)
    }

    @Test
    func multiplePublishingDestinationsRoundTrip() throws {
        var original = Site.starter()
        let staging = PublishingDestination(
            name: "Staging",
            kind: .sftp,
            host: "staging.example.com",
            port: 22,
            username: "deploy",
            remotePath: "public_html"
        )
        original.publishingDestinations.append(staging)
        original.defaultPublishingDestinationID = staging.id
        original.synchronizeLegacyPublishingFields()

        let data = try FoundryDocument.encoder.encode(original)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded == original)
        #expect(decoded.defaultPublishingDestination?.name == "Staging")
        #expect(decoded.publishingDestination == .sftp)
    }

    @Test
    func legacyPublishingSettingsMigrateToDefaultDestination() throws {
        var original = Site.starter()
        original.publishingDestination = .sftp
        original.publishingHost = "legacy.example.com"
        original.publishingUsername = "legacy-user"
        let data = try FoundryDocument.encoder.encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "publishingDestinations")
        object.removeValue(forKey: "defaultPublishingDestinationID")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: legacyData)

        #expect(decoded.publishingDestinations.count == 1)
        #expect(decoded.defaultPublishingDestination?.kind == .sftp)
        #expect(decoded.defaultPublishingDestination?.host == "legacy.example.com")
        #expect(decoded.defaultPublishingDestination?.username == "legacy-user")
    }

    @Test
    func siteMetadataRoundTripsThroughProjectJSON() throws {
        var original = Site.starter()
        original.language = "en-GB"
        original.titleSuffix = " — Foundry"
        original.defaultDescription = "The default site description"
        original.favicon = "foundry-asset:site-icon"
        original.defaultSocialImage = "foundry-asset:social-image"
        original.logo = "foundry-asset:site-logo"
        original.logoAlt = "Foundry"
        original.generatesCanonicalURLs = false
        original.generatesSitemap = false
        original.generatesRobotsTXT = false
        original.allowsSearchIndexing = false
        original.customCodeEnabled = false
        original.headCode = "<meta name=\"custom\" content=\"head\">"
        original.bodyStartCode = "<div>body start</div>"
        original.bodyEndCode = "<div>body end</div>"
        original.analyticsCode = "<script>analytics()</script>"
        original.cleansObsoleteExportFiles = true
        original.publishingDestination = .amazonS3
        original.publishingUsername = "ACCESSKEY"
        original.publishingRemotePath = "production"
        original.publishingS3Bucket = "example-site"
        original.publishingS3Region = "eu-west-2"
        original.pages[0].metadata = PageMetadata(
            browserTitle: "Foundry",
            description: "Build a site",
            socialTitle: "Share Foundry",
            socialDescription: "A visual site builder",
            socialImage: "https://example.com/social.png"
        )

        let data = try FoundryDocument.encoder.encode(original)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded == original)
    }

    @Test
    func projectsSavedBeforeSiteLogoSettingsUseEmptyDefaults() throws {
        let data = try FoundryDocument.encoder.encode(Site.starter())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "logo")
        object.removeValue(forKey: "logoAlt")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: legacyData)

        #expect(decoded.logo.isEmpty)
        #expect(decoded.logoAlt.isEmpty)
    }

    @Test
    func projectsSavedBeforeGeneratedWebIconsUseAnEmptyCache() throws {
        let data = try FoundryDocument.encoder.encode(Site.starter())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "webIconAssets")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: legacyData)

        #expect(decoded.webIconAssets.isEmpty)
    }

    @Test
    func projectsSavedBeforePrivateSiteLogosUseAnEmptyManagedSet() throws {
        let data = try FoundryDocument.encoder.encode(Site.starter())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "siteLogoAssets")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: legacyData)

        #expect(decoded.siteLogoAssets.isEmpty)
    }

    @Test
    func generatedWebIconFilesLoadFromTheProjectPackage() throws {
        let bytes = Data("cached icon".utf8)
        let icon = ProjectAsset(
            filename: "favicon.ico",
            mediaType: "image/x-icon",
            byteCount: bytes.count
        )
        var site = Site.starter()
        site.webIconAssets = [icon]
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "project.json": FileWrapper(regularFileWithContents: try FoundryDocument.encoder.encode(site)),
            "assets": FileWrapper(directoryWithFileWrappers: [
                icon.storageFilename: FileWrapper(regularFileWithContents: bytes)
            ])
        ])

        let decoded = try FoundryDocument.decodeSnapshot(from: wrapper)

        #expect(decoded.site.webIconAssets == [icon])
        #expect(decoded.assetData[icon.id] == bytes)
    }

    @Test
    func encodedProjectIsReadableJSON() throws {
        let data = try FoundryDocument.encoder.encode(Site.starter())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["schemaVersion"] as? Int == Site.currentSchemaVersion)
        #expect(object?["pages"] != nil)
        #expect(object?["theme"] != nil)
    }
}
