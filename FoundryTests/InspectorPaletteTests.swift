import Foundation
import Testing
@testable import Foundry

@MainActor
struct InspectorPaletteTests {
    @Test func literalAppearancesAndResponsivePairsStayIndependent() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var value = PartPackageColorValue(source: PartFrameworkValueSelection.manualCustom,
            customColor: "#123456", opacity: 1, shade: .two, darkShade: .nine)
        value.darkCustomColor = "#ABCDEF"
        value.darkOpacity = 0.4
        #expect(PartPackageColorResolver.resolve(value, framework: .standard, opacity: true).contains("18 52 86 / 1"))
        #expect(PartPackageColorResolver.resolve(value, framework: .standard, opacity: true, appearance: .dark).contains("171 205 239 / 0.4"))
        var node = PartNode(type: .section)
        node.setProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(value))
        node.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        var wide = value
        wide.darkShade = .eleven
        node.setResponsiveProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(wide), at: .large)
        #expect(node.resolved(at: .mobile).propertyValue(.init(rawValue: "background.backgroundColor")) == .packageColor(value))
        #expect(node.resolved(at: .large).propertyValue(.init(rawValue: "background.backgroundColor")) == .packageColor(wide))
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
        let index = try #require(site.framework.colourPalettes.firstIndex { $0.id == "framework.surface" })
        var shades = site.framework.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try site.framework.colourPalettes[index].replaceShades(shades)
        let value = PartPackageColorValue(source: "surface", customColor: "#000000", opacity: 1,
                                              shade: .two, darkShade: .nine)
        site.framework.colourPalettes[index].setLightDefault(.four)
        site.framework.colourPalettes[index].setDarkDefault(.seven)
        #expect(PartPackageColorResolver.resolve(value, framework: site.framework, opacity: false) == "#123456")
        #expect(PartPackageColorResolver.resolve(value, framework: site.framework, opacity: false, appearance: .dark) == "#ABCDEF")
        var node = PartNode.make(.section)
        node.setProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(value))
        node.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        let page = Page(title: "Appearance", slug: "index", parts: [node])
        site.pages = [page]
        #expect(HTMLPageRenderer(appearance: .light).render(page: page, framework: site.framework).contains("background-color: #123456"))
        #expect(HTMLPageRenderer(appearance: .dark).render(page: page, framework: site.framework).contains("background-color: #ABCDEF"))
        let output = StaticSiteRenderer().render(site: site)
        #expect(output.file(at: "files/page.css")?.contents.contains("light-dark(#123456, #ABCDEF)") == true)
        #expect(output.file(at: "files/site.css")?.contents.contains("color-scheme:light dark") == true)
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(restored.appearanceMode == .both)
        #expect(restored.framework.colourPalettes[index].darkDefaultShade == .seven)
    }

    @Test func newPartsCaptureActiveFrameworkDefaultOnce() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var framework = Framework.standard
        let index = try #require(framework.colourPalettes.firstIndex { $0.id == "framework.surface" })
        framework.colourPalettes[index].setLightDefault(.three)
        var node = PartNode.make(.section)
        // The built-in container starts with a literal colour. Supply a framework-role
        // declaration and exercise the same initialisation used by make(_:framework:).
        node.setProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(.init(
            source: "surface", customColor: "#000000", opacity: 1)))
        node.selectInitialColourShades(from: framework)
        guard case .packageColor(let value) = node.propertyValue(.init(rawValue: "background.backgroundColor")) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(value.shade == .three)
        let before = PartPackageColorResolver.resolve(value, framework: framework, opacity: false)
        framework.colourPalettes[index].setLightDefault(.nine)
        #expect(PartPackageColorResolver.resolve(value, framework: framework, opacity: false) == before)
        #expect(value.shade != framework.colourPalettes[index].lightDefaultShade)
        var next = node
        next.selectInitialColourShades(from: framework)
        guard case .packageColor(let nextValue) = next.propertyValue(.init(rawValue: "background.backgroundColor")) else {
            Issue.record("Expected a palette colour"); return
        }
        #expect(nextValue.shade == .nine)
    }

    @Test func canvasAndExportIgnoreMatchingCustomNamesForStableReferences() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        let original = try #require(site.framework.colourPalettes.first { $0.id == "framework.surface" })
        var custom = try original.duplicated()
        custom.name = original.name
        try custom.replaceShades(Array(repeating: "#193A5C", count: 11))
        site.framework.colourPalettes.insert(custom, at: 0)
        var node = PartNode.make(.section)
        node.setProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(.init(source: "surface",
            customColor: "#000000", opacity: 1)))
        let page = Page(title: "Override", slug: "index", parts: [node])
        site.pages = [page]
        #expect(!HTMLPageRenderer().render(page: page, framework: site.framework).contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(!css.contains("background-color: #193A5C"))
        #expect(site.framework.colourPalettes.resolvedPalette(id: original.id) == original)
        #expect(site.framework.colourPalettes.resolvedPalette(id: custom.id) == custom)
        #expect(site.framework.fixedFrameworkColourPalettes.contains(original))
    }

    @Test func referencesKeepTheirShadeWhenDefaultsAndNamesChange() throws {
        var framework = Framework.standard
        let index = try #require(framework.colourPalettes.firstIndex { $0.id == "framework.accent" })
        var shades = framework.colourPalettes[index].shades
        shades[1] = "#123456"
        shades[8] = "#ABCDEF"
        try framework.colourPalettes[index].replaceShades(shades)
        framework.colourPalettes[index].setLightDefault(.two)
        let following = PartPackageColorValue(source: "framework.accent", customColor: "#000000", opacity: 1, shade: framework.colourPalettes[index].lightDefaultShade)
        let fixed = PartPackageColorValue(source: "framework.accent", customColor: "#000000", opacity: 1, shade: .two)
        func resolve(_ value: PartPackageColorValue) -> String {
            PartPackageColorResolver.resolve(value, framework: framework, opacity: false)
        }
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        framework.colourPalettes[index].name = "New Name"
        framework.colourPalettes[index].setLightDefault(.nine)
        #expect(resolve(following) == "#123456")
        #expect(resolve(fixed) == "#123456")
        let restored = try JSONDecoder().decode(PartPackageColorValue.self, from: JSONEncoder().encode(fixed))
        #expect(restored == fixed)
        #expect(resolve(restored) == "#123456")
    }

    @Test func canvasAndExportResolveCustomPaletteShade() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var site = Site.starter()
        var palette = try site.framework.colourPalettes[0].duplicated()
        var shades = palette.shades
        shades[7] = "#193A5C"
        try palette.replaceShades(shades)
        site.framework.colourPalettes.append(palette)
        var node = PartNode.make(.section)
        node.setProperty(.init(rawValue: "background.backgroundColor"), value: .packageColor(.init(source: palette.id,
            customColor: "#000000", opacity: 1, shade: .eight)))
        node.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        let page = Page(title: "Palette", slug: "index", parts: [node])
        site.pages = [page]
        let html = HTMLPageRenderer().render(page: page, framework: site.framework)
        #expect(html.contains("background-color: #193A5C"))
        let css = try #require(StaticSiteRenderer().render(site: site).file(at: "files/page.css")?.contents)
        #expect(css.contains("background-color: #193A5C"))
    }

    @Test func missingPaletteAndCustomColorsApplyOptedInOpacity() {
        let missing = PartPackageColorValue(source: "custom.deleted", customColor: "#123456", opacity: 0.5)
        #expect(PartPackageColorResolver.resolve(missing, framework: .standard, opacity: true)
            == PartTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))
        var manual = missing
        manual.source = PartFrameworkValueSelection.manualCustom
        #expect(PartPackageColorResolver.resolve(manual, framework: .standard, opacity: true)
            == PartTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))
    }

    @Test func paletteOpacityRespectsOptInAndBothAppearances() throws {
        var value = PartPackageColorValue(source: "standard.black", customColor: "#000000", opacity: 0.2)
        value.darkOpacity = 0.7
        #expect(PartPackageColorResolver.resolve(value, framework: .standard, opacity: false) == "#000000")
        #expect(PartPackageColorResolver.resolve(value, framework: .standard, opacity: true) == "rgb(0 0 0 / 0.2)")
        #expect(PartPackageColorResolver.resolve(value, framework: .standard, opacity: true, appearance: .dark) == "rgb(0 0 0 / 0.7)")
        #expect(PartPackageColorResolver.channels(value, framework: .standard, opacity: false, appearance: .dark)?.alpha == 1)
        #expect(PartPackageColorResolver.channels(value, framework: .standard, opacity: true, appearance: .dark)?.alpha == 0.7)
        let restored = try JSONDecoder().decode(PartPackageColorValue.self, from: JSONEncoder().encode(value))
        #expect(restored == value)
    }
}
