import Foundation
import Testing
@testable import Foundry

struct BackgroundFocalPointTests {
    @Test @MainActor
    func backgroundImageFocalPointBecomesTheBackgroundPosition() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let definition = PartType.section.definition
        // The group's image offers the Focal Point button; the presets are gone.
        let image = try #require(definition.properties.first { $0.key.rawValue == "background.backgroundImage" })
        #expect(image.supportsImageFocalPoint)
        #expect(!definition.properties.contains { $0.key.rawValue == "background.backgroundPosition" })

        var part = PartNode.make(.section)
        part.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        part.setProperty(.init(rawValue: "background.backgroundStyle"), value: .choice("image"))
        part.setProperty(.init(rawValue: "background.backgroundImage"), value: .url("https://example.com/hero.jpg"))
        part.setProperty(PartPackageAdapter.imageFocalPointKey(for: "background.backgroundImage"),
                         value: .array([.number(20), .number(35)]))
        let site = Site(name: "Background", pages: [Page(title: "Home", slug: "index", parts: [part])])

        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("background-position: 20% 35%"))
        let exported = StaticSiteRenderer().render(site: site).files.map(\.contents).joined()
        #expect(exported.contains("background-position: 20% 35%"))
    }
}
