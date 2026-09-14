import Foundation
import Testing
@testable import Foundry

@MainActor
struct DocumentCodingTests {
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
    func siteMetadataRoundTripsThroughProjectJSON() throws {
        var original = Site.starter()
        original.language = "en-GB"
        original.titleSuffix = " — Foundry"
        original.defaultDescription = "The default site description"
        original.favicon = "foundry-asset:site-icon"
        original.defaultSocialImage = "foundry-asset:social-image"
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
    func encodedProjectIsReadableJSON() throws {
        let data = try FoundryDocument.encoder.encode(Site.starter())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["schemaVersion"] as? Int == Site.currentSchemaVersion)
        #expect(object?["pages"] != nil)
        #expect(object?["theme"] != nil)
    }
}
