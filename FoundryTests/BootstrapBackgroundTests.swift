import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapBackgroundTests {
    @Test func capabilitiesArePartSpecific() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        #expect(PartType.button.definition.package?.manifest.controlGroups.contains { $0.type == .background } == false)
        for type in [PartType.container, .flex, .grid] {
            let group = try #require(type.definition.package?.manifest.controlGroups.first { $0.type == .background })
            #expect(group.backgroundTypes.contains(.video) == (type == .container))
            #expect(group.colourSections == ["blackWhite", "surfaces"])
            #expect(group.properties.contains { $0.control.type.rawValue == "themePaletteColor" } == false)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func backgroundMatchesNativeColourAndResponsiveGradient(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var colour = PartNode.make(.container)
        var theme = Theme.standard
        let base = BootstrapColourCatalogue.palette(role: .primary)
        theme.colourPalettes.append(try ColourPalette(id: "custom.brand", name: "brand", origin: .custom,
            shades: base.shades, lightDefaultShade: base.lightDefaultShade))
        colour.anchor = "colour"
        colour.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        colour.setProperty(.init(rawValue: "background.backgroundColor"), value: .choice("custom.brand"))
        colour.setProperty(.init(rawValue: "background.backgroundColorVariant"), value: .choice("bg-subtle"))
        colour.setProperty(.init(rawValue: "background.backgroundColorOpacity"), value: .number(50))
        var gradient = PartNode.make(.container)
        gradient.anchor = "gradient"
        gradient.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
        gradient.setProperty(.init(rawValue: "background.backgroundStyle"), value: .choice("gradient"))
        gradient.setProperty(.init(rawValue: "background.backgroundGradientFrom"), value: .choice("custom.brand"))
        gradient.setResponsiveProperty(.init(rawValue: "background.backgroundGradientType"), value: .choice("radial"), at: .medium)
        let page = Page(title: "Backgrounds", slug: "index", parts: [colour, gradient])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .mobile)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Backgrounds", pages: [page], theme: theme))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        #expect(html.contains("bg-subtle-brand bg-50"))
        #expect(html.contains("var(--bs-brand-bg)"))
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let result = try await browser.web.evaluateJavaScript("""
          (() => { const ref=document.createElement('div');ref.style.backgroundColor='color-mix(in oklch, var(--bs-brand-bg-subtle) 50%, transparent)';document.body.append(ref);
          const errors=[];for(const mode of ['light','dark']) {document.documentElement.dataset.bsTheme=mode;
          if(getComputedStyle(ref).backgroundColor!==getComputedStyle(document.getElementById('colour')).backgroundColor) errors.push(mode);}
          const sample=document.createElement('div');document.body.append(sample);
          for(const theme of ['primary','brand']) for(const role of ['bg','bg-subtle','bg-muted']) for(const opacity of [0,50,100]) {
            sample.className=opacity===0?'bg-transparent':role+'-'+theme+(opacity<100?' bg-'+opacity:'');
            ref.style.backgroundColor=opacity===0?'transparent':opacity===100?'var(--bs-'+theme+'-'+role+')':'color-mix(in oklch, var(--bs-'+theme+'-'+role+') '+opacity+'%, transparent)';
            if(getComputedStyle(ref).backgroundColor!==getComputedStyle(sample).backgroundColor) errors.push(theme+role+opacity);
          }
          if(!getComputedStyle(document.getElementById('gradient')).backgroundImage.startsWith('radial-gradient')) errors.push('responsive gradient');
          return errors; })()
          """) as? [String]
        #expect(result == [])
    }

    @Test func arbitraryOpacityUsesGeneratedCSS() {
        let group = PartPackageControlGroup(type: .background, id: "surface")
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("static"),
            "surface.backgroundColor": .string("theme-primary"),
            "surface.backgroundColorOpacity": .number(55)
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        #expect(values["surface.classes"]?.stringValue.contains("bg-55") != true)
        #expect(PartPackageBackgroundResolver.stylesheet(values).contains("55%"))
        values["surface.backgroundColorOpacity"] = .number(0)
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        #expect(values["surface.classes"] == .string("bg-transparent"))
    }

    @Test func themePaintTokensAreValidatedAndKeepLiveReferences() {
        #expect(PartColourToken.groups(for: ["surfaces", "blackWhite"]).map(\.0) == ["Surfaces", "Black & White"])
        #expect(PartColourToken.groups(for: []).isEmpty)
        for token in PartColourToken.all {
            #expect(BootstrapColourCatalogue.declarations["--bs-" + token.id] != nil)
            #expect(BootstrapPaletteTheme.resolve(token.selection, theme: .standard) == token.selection)
            #expect(BootstrapBackgroundColour.paint(token.selection) == token.expression)
            #expect(BootstrapBackgroundColour.paint(token.selection, opacity: 20).contains(token.expression + " 20%"))
        }
        #expect(PartColourToken.parse("token:black;}body{") == nil)
        #expect(PartColourToken.parse("token:missing") == nil)
    }

    @Test func unusedBackgroundProducesNothingAndVideoIsDecorative() {
        let group = PartPackageControlGroup(type: .background, id: "surface")
        var values: [String: PartPackageValue] = ["surface.backgroundMode": .string("none")]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        #expect(values["surface.classes"] == .string(""))
        #expect(values["surface.stylesheet"] == .string(""))
        #expect(PartBackgroundVideoPlayback.javaScript.contains("prefers-reduced-motion"))
        #expect(PartBackgroundVideoPlayback.javaScript.contains("document.hidden"))
        #expect(PartBackgroundVideoPlayback.javaScript.contains("IntersectionObserver"))
    }
}
