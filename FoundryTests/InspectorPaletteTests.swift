import Foundation
import Testing
@testable import Foundry

@MainActor
struct InspectorPaletteTests {
    @Test func referencesPersistAndFollowDefaultsIndependentlyOfNames() throws {
        var theme = Theme.standard
        let index = try #require(theme.colourPalettes.firstIndex { $0.id == "theme.accent" })
        var shades = theme.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try theme.colourPalettes[index].replaceShades(shades)
        theme.colourPalettes[index].setDefault(.two)
        let following = ComponentPackageColorValue(source: "theme.accent", customColor: "#000000", adjustment: 0, opacity: 1)
        let fixed = ComponentPackageColorValue(source: "theme.accent", customColor: "#000000", adjustment: 0, opacity: 1, shade: .shade(.two))
        func resolve(_ value: ComponentPackageColorValue) -> String {
            ComponentPackageColorResolver.resolve(value, theme: theme, colorMath: false, opacity: false)
        }
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        theme.colourPalettes[index].name = "New Name"
        theme.colourPalettes[index].setDefault(.nine)
        #expect(resolve(following) == "#ABCDEF")
        #expect(resolve(fixed) == "#123456")
        let restored = try JSONDecoder().decode(ComponentPackageColorValue.self, from: JSONEncoder().encode(fixed))
        #expect(restored == fixed)
        #expect(resolve(restored) == "#123456")
    }

    @Test func canvasAndExportResolveCustomPaletteShade() async throws {
        await ComponentPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        var palette = try site.theme.colourPalettes[0].duplicated()
        var shades = palette.shades
        shades[7] = "#193A5C"
        try palette.replaceShades(shades)
        site.theme.colourPalettes.append(palette)
        var node = ComponentNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(.init(source: palette.id,
            customColor: "#000000", adjustment: 0, opacity: 1, shade: .shade(.eight))))
        let page = Page(title: "Palette", slug: "index", components: [node])
        site.pages = [page]
        let html = HTMLPageRenderer().render(page: page, theme: site.theme)
        #expect(html.contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(css.contains("background-color: #193A5C"))
    }

    @Test func missingPaletteUsesExistingFallbackAndCustomOpacityStillWorks() {
        let missing = ComponentPackageColorValue(source: "custom.deleted", customColor: "#123456", adjustment: 0, opacity: 0.5)
        #expect(ComponentPackageColorResolver.resolve(missing, theme: .standard, colorMath: false, opacity: true) == "#123456")
        var manual = missing
        manual.source = ComponentThemeValueSelection.manualCustom
        #expect(ComponentPackageColorResolver.resolve(manual, theme: .standard, colorMath: false, opacity: true)
            == ComponentTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))
    }
}
