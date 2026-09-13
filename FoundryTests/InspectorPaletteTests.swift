import Foundation
import Testing
@testable import Foundry

@MainActor
struct InspectorPaletteTests {
    @Test func literalAppearancesAndResponsivePairsStayIndependent() async {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var value = BlockPackageColorValue(source: BlockThemeValueSelection.manualCustom,
            customColor: "#123456", opacity: 1, shade: .two, darkShade: .nine)
        value.darkCustomColor = "#ABCDEF"
        value.darkOpacity = 0.4
        #expect(BlockPackageColorResolver.resolve(value, theme: .standard, opacity: true).contains("18 52 86 / 1"))
        #expect(BlockPackageColorResolver.resolve(value, theme: .standard, opacity: true, appearance: .dark).contains("171 205 239 / 0.4"))
        var node = BlockNode(type: .container)
        node.setProperty(.backgroundColor, value: .packageColor(value))
        var wide = value
        wide.darkShade = .eleven
        node.setResponsiveProperty(.backgroundColor, value: .packageColor(wide), at: .large)
        #expect(node.resolved(at: .mobile).propertyValue(.backgroundColor) == .packageColor(value))
        #expect(node.resolved(at: .large).propertyValue(.backgroundColor) == .packageColor(wide))
        #expect(wide.shade == value.shade)
    }

    @Test func appearanceOutputAndFiltersUseBothColours() {
        #expect(SiteAppearanceMode.light.colour(light: "#123456", dark: "#ABCDEF") == "#123456")
        #expect(SiteAppearanceMode.dark.colour(light: "#123456", dark: "#ABCDEF") == "#ABCDEF")
        #expect(SiteAppearanceMode.light.bootstrap(siteID: UUID()).isEmpty)
        #expect(SiteAppearanceMode.both.bootstrap(siteID: UUID()).contains("window.foundryAppearance"))
        #expect(BlockTemplateRenderer.transformColor("light-dark(#000000, #FFFFFF)", target: 255, amount: 1)
                == "light-dark(#FFFFFF, #FFFFFF)")
    }

    @Test func appearanceSelectionsAreIndependentAndExportTogether() async throws {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        site.appearanceMode = .both
        let index = try #require(site.theme.colourPalettes.firstIndex { $0.id == "theme.background" })
        var shades = site.theme.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try site.theme.colourPalettes[index].replaceShades(shades)
        let value = BlockPackageColorValue(source: "background", customColor: "#000000", opacity: 1,
                                              shade: .two, darkShade: .nine)
        site.theme.colourPalettes[index].setLightDefault(.four)
        site.theme.colourPalettes[index].setDarkDefault(.seven)
        #expect(BlockPackageColorResolver.resolve(value, theme: site.theme, opacity: false) == "#123456")
        #expect(BlockPackageColorResolver.resolve(value, theme: site.theme, opacity: false, appearance: .dark) == "#ABCDEF")
        var node = BlockNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(value))
        let page = Page(title: "Appearance", slug: "index", blocks: [node])
        site.pages = [page]
        #expect(HTMLPageRenderer(appearance: .light).render(page: page, theme: site.theme).contains("background-color: #123456"))
        #expect(HTMLPageRenderer(appearance: .dark).render(page: page, theme: site.theme).contains("background-color: #ABCDEF"))
        let output = StaticSiteRenderer().render(site: site)
        #expect(output.file(at: "files/page.css")?.contents.contains("light-dark(#123456, #ABCDEF)") == true)
        #expect(output.file(at: "files/site.css")?.contents.contains("color-scheme:light dark") == true)
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(restored.appearanceMode == .both)
        #expect(restored.theme.colourPalettes[index].darkDefaultShade == .seven)
    }

    @Test func newBlocksCaptureActiveThemeDefaultOnce() async throws {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        let index = try #require(theme.colourPalettes.firstIndex { $0.id == "theme.background" })
        theme.colourPalettes[index].setLightDefault(.three)
        var node = BlockNode.make(.container)
        // The built-in container starts with a literal colour. Supply a theme-role
        // declaration and exercise the same initialisation used by make(_:theme:).
        node.setProperty(.backgroundColor, value: .packageColor(.init(
            source: "background", customColor: "#000000", opacity: 1)))
        node.selectInitialColourShades(from: theme)
        guard case .packageColor(let value) = node.propertyValue(.backgroundColor) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(value.shade == .three)
        let before = BlockPackageColorResolver.resolve(value, theme: theme, opacity: false)
        theme.colourPalettes[index].setLightDefault(.nine)
        #expect(BlockPackageColorResolver.resolve(value, theme: theme, opacity: false) == before)
        #expect(value.shade != theme.colourPalettes[index].lightDefaultShade)
        var next = node
        next.selectInitialColourShades(from: theme)
        guard case .packageColor(let nextValue) = next.propertyValue(.backgroundColor) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(nextValue.shade == .nine)
    }

    @Test func canvasAndExportIgnoreMatchingCustomNamesForStableReferences() async throws {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        let original = try #require(site.theme.colourPalettes.first { $0.id == "theme.background" })
        var custom = try original.duplicated()
        custom.name = original.name
        try custom.replaceShades(Array(repeating: "#193A5C", count: 11))
        site.theme.colourPalettes.insert(custom, at: 0)
        var node = BlockNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(.init(source: "background",
            customColor: "#000000", opacity: 1)))
        let page = Page(title: "Override", slug: "index", blocks: [node])
        site.pages = [page]
        #expect(!HTMLPageRenderer().render(page: page, theme: site.theme).contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(!css.contains("background-color: #193A5C"))
        #expect(site.theme.colourPalettes.resolvedPalette(id: original.id) == original)
        #expect(site.theme.colourPalettes.resolvedPalette(id: custom.id) == custom)
        #expect(site.theme.fixedThemeColourPalettes.contains(original))
    }

    @Test func referencesKeepTheirShadeWhenDefaultsAndNamesChange() throws {
        var theme = Theme.standard
        let index = try #require(theme.colourPalettes.firstIndex { $0.id == "theme.accent" })
        var shades = theme.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try theme.colourPalettes[index].replaceShades(shades)
        theme.colourPalettes[index].setLightDefault(.two)
        let following = BlockPackageColorValue(source: "theme.accent", customColor: "#000000", opacity: 1, shade: theme.colourPalettes[index].lightDefaultShade)
        let fixed = BlockPackageColorValue(source: "theme.accent", customColor: "#000000", opacity: 1, shade: .two)
        func resolve(_ value: BlockPackageColorValue) -> String {
            BlockPackageColorResolver.resolve(value, theme: theme, opacity: false)
        }
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        theme.colourPalettes[index].name = "New Name"
        theme.colourPalettes[index].setLightDefault(.nine)
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        let restored = try JSONDecoder().decode(BlockPackageColorValue.self, from: JSONEncoder().encode(fixed))
        #expect(restored == fixed)
        #expect(resolve(restored) == "#123456")
    }

    @Test func canvasAndExportResolveCustomPaletteShade() async throws {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        var palette = try site.theme.colourPalettes[0].duplicated()
        var shades = palette.shades
        shades[7] = "#193A5C"
        try palette.replaceShades(shades)
        site.theme.colourPalettes.append(palette)
        var node = BlockNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(.init(source: palette.id,
            customColor: "#000000", opacity: 1, shade: .eight)))
        let page = Page(title: "Palette", slug: "index", blocks: [node])
        site.pages = [page]
        let html = HTMLPageRenderer().render(page: page, theme: site.theme)
        #expect(html.contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(css.contains("background-color: #193A5C"))
    }

    @Test func missingPaletteUsesExistingFallbackAndCustomOpacityStillWorks() {
        let missing = BlockPackageColorValue(source: "custom.deleted", customColor: "#123456", opacity: 0.5)
        #expect(BlockPackageColorResolver.resolve(missing, theme: .standard, opacity: true) == "#123456")
        var manual = missing
        manual.source = BlockThemeValueSelection.manualCustom
        #expect(BlockPackageColorResolver.resolve(manual, theme: .standard, opacity: true)
            == BlockTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))
    }
}
