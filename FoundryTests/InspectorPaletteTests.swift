import Foundation
import Testing
@testable import Foundry

@MainActor
struct InspectorPaletteTests {
    @Test func literalAppearancesAndResponsivePairsStayIndependent() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var value = PartPackageColorValue(source: PartThemeValueSelection.manualCustom,
            customColor: "#123456", opacity: 1, shade: .two, darkShade: .nine)
        value.darkCustomColor = "#ABCDEF"
        value.darkOpacity = 0.4
        #expect(PartPackageColorResolver.resolve(value, theme: .standard, opacity: true).contains("18 52 86 / 1"))
        #expect(PartPackageColorResolver.resolve(value, theme: .standard, opacity: true, appearance: .dark).contains("171 205 239 / 0.4"))
        var node = PartNode(type: .container)
        node.setProperty(.backgroundColor, value: .packageColor(value))
        node.setProperty(.init(rawValue: "backgroundMode"), value: .choice("static"))
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
        #expect(PartTemplateRenderer.transformColor("light-dark(#000000, #FFFFFF)", target: 255, amount: 1)
                == "light-dark(#FFFFFF, #FFFFFF)")
    }

    @Test func appearanceSelectionsAreIndependentAndExportTogether() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        site.appearanceMode = .both
        let index = try #require(site.theme.colourPalettes.firstIndex { $0.id == "theme.background" })
        var shades = site.theme.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try site.theme.colourPalettes[index].replaceShades(shades)
        let value = PartPackageColorValue(source: "background", customColor: "#000000", opacity: 1,
                                              shade: .two, darkShade: .nine)
        site.theme.colourPalettes[index].setLightDefault(.four)
        site.theme.colourPalettes[index].setDarkDefault(.seven)
        #expect(PartPackageColorResolver.resolve(value, theme: site.theme, opacity: false) == "#123456")
        #expect(PartPackageColorResolver.resolve(value, theme: site.theme, opacity: false, appearance: .dark) == "#ABCDEF")
        var node = PartNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(value))
        node.setProperty(.init(rawValue: "backgroundMode"), value: .choice("static"))
        let page = Page(title: "Appearance", slug: "index", parts: [node])
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

    @Test func newPartsCaptureActiveThemeDefaultOnce() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        let index = try #require(theme.colourPalettes.firstIndex { $0.id == "theme.background" })
        theme.colourPalettes[index].setLightDefault(.three)
        var node = PartNode.make(.container)
        // The built-in container starts with a literal colour. Supply a theme-role
        // declaration and exercise the same initialisation used by make(_:theme:).
        node.setProperty(.backgroundColor, value: .packageColor(.init(
            source: "background", customColor: "#000000", opacity: 1)))
        node.selectInitialColourShades(from: theme)
        guard case .packageColor(let value) = node.propertyValue(.backgroundColor) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(value.shade == .three)
        let before = PartPackageColorResolver.resolve(value, theme: theme, opacity: false)
        theme.colourPalettes[index].setLightDefault(.nine)
        #expect(PartPackageColorResolver.resolve(value, theme: theme, opacity: false) == before)
        #expect(value.shade != theme.colourPalettes[index].lightDefaultShade)
        var next = node
        next.selectInitialColourShades(from: theme)
        guard case .packageColor(let nextValue) = next.propertyValue(.backgroundColor) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(nextValue.shade == .nine)
    }

    @Test func canvasAndExportIgnoreMatchingCustomNamesForStableReferences() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        let original = try #require(site.theme.colourPalettes.first { $0.id == "theme.background" })
        var custom = try original.duplicated()
        custom.name = original.name
        try custom.replaceShades(Array(repeating: "#193A5C", count: 11))
        site.theme.colourPalettes.insert(custom, at: 0)
        var node = PartNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(.init(source: "background",
            customColor: "#000000", opacity: 1)))
        let page = Page(title: "Override", slug: "index", parts: [node])
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
        let following = PartPackageColorValue(source: "theme.accent", customColor: "#000000", opacity: 1, shade: theme.colourPalettes[index].lightDefaultShade)
        let fixed = PartPackageColorValue(source: "theme.accent", customColor: "#000000", opacity: 1, shade: .two)
        func resolve(_ value: PartPackageColorValue) -> String {
            PartPackageColorResolver.resolve(value, theme: theme, opacity: false)
        }
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        theme.colourPalettes[index].name = "New Name"
        theme.colourPalettes[index].setLightDefault(.nine)
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        let restored = try JSONDecoder().decode(PartPackageColorValue.self, from: JSONEncoder().encode(fixed))
        #expect(restored == fixed)
        #expect(resolve(restored) == "#123456")
    }

    @Test func canvasAndExportResolveCustomPaletteShade() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        var palette = try site.theme.colourPalettes[0].duplicated()
        var shades = palette.shades
        shades[7] = "#193A5C"
        try palette.replaceShades(shades)
        site.theme.colourPalettes.append(palette)
        var node = PartNode.make(.container)
        node.setProperty(.backgroundColor, value: .packageColor(.init(source: palette.id,
            customColor: "#000000", opacity: 1, shade: .eight)))
        node.setProperty(.init(rawValue: "backgroundMode"), value: .choice("static"))
        let page = Page(title: "Palette", slug: "index", parts: [node])
        site.pages = [page]
        let html = HTMLPageRenderer().render(page: page, theme: site.theme)
        #expect(html.contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(css.contains("background-color: #193A5C"))
    }

    @Test func missingPaletteUsesExistingFallbackAndCustomOpacityStillWorks() {
        let missing = PartPackageColorValue(source: "custom.deleted", customColor: "#123456", opacity: 0.5)
        #expect(PartPackageColorResolver.resolve(missing, theme: .standard, opacity: true) == "#123456")
        var manual = missing
        manual.source = PartThemeValueSelection.manualCustom
        #expect(PartPackageColorResolver.resolve(manual, theme: .standard, opacity: true)
            == PartTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))
    }
}
