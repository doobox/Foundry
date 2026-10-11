import Foundation
import Testing
@testable import Foundry

struct PaletteShadePickerTests {
    @Test func exposesOnlyRequestedPaletteScales() {
        #expect(PartColourToken.pickerSectionIDs.contains("palettes"))
        let groups = PartColourToken.groups(for: ["foregrounds", "palettes", "themes", "palettes"])
        #expect(groups.map(\.0) == ["Foregrounds", "Palettes"])
        #expect(groups.last?.1.count == BootstrapColourCatalogue.hues.count * 13)
        #expect(PartColourToken.groups(for: ["themes"]).isEmpty)
        for hue in BootstrapColourCatalogue.hues {
            for shade in ColourShade.allCases {
                let token = hue + "-" + shade.bootstrapLabel
                #expect(PartColourToken.parse("token:" + token)?.expression == "var(--bs-\(token))")
                #expect(BootstrapColourCatalogue.declarations["--bs-" + token] != nil)
            }
        }
        #expect(PartColourToken.parse("token:blue-999") == nil)
        #expect(PartColourToken.parse("token:unknown-500") == nil)
        #expect(PartColourToken.label("blue-500", palettes: []) == "Blue 500")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func paletteSelectionsRenderThroughControls(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let controls = #"[{"type":"backgroundColor","id":"paint","colourSections":["palettes"],"defaults":{"base":"token:blue-500"}},{"type":"foreground","id":"ink","colourSections":["palettes"]}]"#
        let html = #"<p class="{{ part.class }} {{ control.ink.classes }}" {{ part.attributes }} data-selection="{{ control.paint }}">Palette</p>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        part.setProperty(.init(rawValue: "ink.theme"), value: .string("token:blue-500"))
        part = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(part))
        let page = Page(title: "Palette", slug: "index", parts: [part])
        let site = Site(name: "Palette", pages: [page])
        let output: String
        if environment == .canvas {
            output = HTMLPageRenderer(site: site).render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: site)
            #expect(bundle.errors.isEmpty)
            output = bundle.files.map(\.contents).joined(separator: "\n")
        }
        #expect(output.contains(#"data-selection="fd-bg--blue-500""#))
        #expect(output.contains("fg-token--blue-500"))
        #expect(output.contains("--bs-fg:var(--bs-blue-500)"))
        #expect(BootstrapBackgroundColour.paint("token:blue-500") == "var(--bs-blue-500)")
    }
}
