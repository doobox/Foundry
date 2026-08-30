import Foundation
import Testing
@testable import Foundry

@MainActor
struct DocumentCodingTests {
    @Test
    func responsiveOverridesRoundTripWithoutDuplicatingBaseProperties() throws {
        var site = Site.starter()
        let componentID = try #require(site.pages.first?.components.first?.id)
        site.updateComponent(id: componentID) {
            $0.setResponsiveProperty(.padding, value: .number(6), at: .mobile)
            $0.setResponsiveProperty(.padding, value: .number(12), at: .tabletPortrait)
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let component = try #require(decoded.component(withID: componentID))

        #expect(component.numberProperty(.padding) == 6)
        #expect(component.propertyValue(.padding, at: .mobile) == .number(6))
        #expect(component.propertyValue(.padding, at: .tabletPortrait) == .number(12))
        #expect(component.propertyValue(.padding, at: .tabletLandscape) == .number(12))
    }

    @Test
    func siteRoundTripsThroughProjectJSON() throws {
        let original = Site.starter()
        let data = try FoundryDocument.encoder.encode(original)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded == original)
        #expect(decoded.pages.first?.components.first?.id ==
                original.pages.first?.components.first?.id)
    }

    @Test
    func olderProjectsDecodeWithMetadataDefaults() throws {
        let encoded = try FoundryDocument.encoder.encode(Site.starter())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "language")
        object.removeValue(forKey: "titleSuffix")
        object.removeValue(forKey: "defaultDescription")
        object.removeValue(forKey: "favicon")
        object.removeValue(forKey: "defaultSocialImage")
        object.removeValue(forKey: "generatesCanonicalURLs")
        object.removeValue(forKey: "generatesSitemap")
        object.removeValue(forKey: "generatesRobotsTXT")
        object.removeValue(forKey: "allowsSearchIndexing")
        var pages = try #require(object["pages"] as? [[String: Any]])
        pages[0].removeValue(forKey: "metadata")
        object["pages"] = pages

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.language == "en")
        #expect(decoded.titleSuffix.isEmpty)
        #expect(decoded.defaultDescription.isEmpty)
        #expect(decoded.favicon.isEmpty)
        #expect(decoded.defaultSocialImage.isEmpty)
        #expect(decoded.generatesCanonicalURLs)
        #expect(decoded.generatesSitemap)
        #expect(decoded.generatesRobotsTXT)
        #expect(decoded.allowsSearchIndexing)
        #expect(decoded.pages.first?.metadata == PageMetadata())
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
