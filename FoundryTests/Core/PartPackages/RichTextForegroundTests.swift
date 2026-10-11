import Foundation
import Testing
@testable import Foundry

struct RichTextForegroundTests {
    @Test(arguments: [SiteAppearanceMode.light, .dark, .both])
    func storesAndRendersForegroundTokens(mode: SiteAppearanceMode) throws {
        let reference = RichTextColourReference(foregroundToken: .init(id: "fg-body"))
        #expect(reference.marker == "token:fg-body")
        #expect(RichTextColourReference(marker: reference.marker) == reference)
        let decoded = try JSONDecoder().decode(RichTextColourReference.self, from: JSONEncoder().encode(reference))
        #expect(decoded == reference)
        let value = FoundryRichTextCodec.storageValue(forHTMLFragment: #"<span data-foundry-color="token:fg-body"><strong>Text</strong></span>"#)
        let context = PartTemplateContext(instanceID: UUID(), packageIdentifier: "test.foreground",
            properties: ["body": .string(value)], slots: [:],
            richTextColourContext: .init(palettes: Theme.standard.colourPalettes, mode: mode))
        let html = PartTemplateRenderer.render(#"<p>{{ text("body") }}</p>"#, context: context)
        #expect(html.contains(#"<span style="color:var(--bs-fg-body)"><strong>Text</strong></span>"#))
        #expect(html.contains("data-foundry-color") == false)
        #expect(html.contains("theme-") == false)
    }

    @Test func customForegroundsRetainIdentityAndMissingColoursInherit() throws {
        let base = BootstrapColourCatalogue.palette(role: .primary)
        var palette = try ColourPalette(id: "custom.readable", name: "Readable", origin: .custom,
            shades: base.shades, lightDefaultShade: base.lightDefaultShade)
        palette.customKind = .foreground
        let token = PartColourToken(id: palette.colourToken("fg-body"))
        let reference = RichTextColourReference(foregroundToken: token)
        #expect(RichTextColourReference(marker: reference.marker) == reference)
        palette.name = "Renamed"
        #expect(reference.resolveCSS(in: [palette], appearance: .light) == token.expression)
        #expect(reference.resolveCSS(in: [palette], appearance: .dark) == token.expression)
        let fragment = "<span data-foundry-color=\"\(reference.marker)\">Text</span>"
        #expect(FoundryRichTextCodec.resolvingColours(in: fragment, context: .init(palettes: [], mode: .both)) == "<span>Text</span>")
        #expect(PartColourToken.groups(for: ["foregrounds"], palettes: [palette]).flatMap { $0.1 }.contains(token.id))
    }

    @Test(arguments: ["token:bg-body", "token:border-body", "token:link-color", "token:shadow-color", "token:black", "token:bad\"onclick=x"])
    func rejectsNonForegroundMarkers(marker: String) {
        #expect(RichTextColourReference(marker: marker) == nil)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func browserResolvesForegroundInBothModes() async throws {
        let reference = RichTextColourReference(foregroundToken: .init(id: "fg-body"))
        let css = BootstrapColourCatalogue.sourceCSS + ":root{--bs-fg-body:light-dark(#123456,#abcdef)}"
        for (mode, expected) in [(SiteAppearance.light, "#123456"), (.dark, "#ABCDEF")] {
            let expression = try #require(reference.resolveCSS(in: Theme.standard.colourPalettes, appearance: mode))
            let colours = try await BootstrapScalePreviewResolver().resolve(expressions: [expression], css: css, mode: mode.rawValue)
            #expect(colours == [expected])
        }
    }
}
