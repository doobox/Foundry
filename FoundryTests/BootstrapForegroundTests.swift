import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapForegroundTests {
    @Test func colourSectionsRespectDeclaredOrderWithoutDuplicates() {
        #expect(PartColourToken.groups(for: ["foregrounds", "blackWhite"]).map(\.0) == ["Foregrounds", "Black & White"])
        #expect(PartColourToken.groups(for: ["surfaces", "links", "foregrounds"]).map(\.0) == ["Surfaces", "Links", "Foregrounds"])
        #expect(PartColourToken.groups(for: ["foregrounds", "foregrounds", "unknown"]).map(\.0) == ["Foregrounds"])
        #expect(PartColourToken.groups(for: []).isEmpty)
    }

    @Test func removedOneOffColoursDoNotGenerateThemes() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.paragraph)
        node.setProperty(.init(rawValue: "foreground.theme"), value: .choice("palette:yellow:500"))
        #expect(BootstrapPaletteTheme.resolve("palette:yellow:500", framework: .standard) == "theme-reset")
        #expect(BootstrapControlGroupClasses.resolve(node: node, key: .init(rawValue: "foreground.theme"), framework: .standard) == "")
        #expect(BootstrapPartUtilityCSS.render(node: node, framework: .standard).isEmpty)
        let page = Page(title: "Removed colour", slug: "index", parts: [node])
        #expect(HTMLPageRenderer().render(page: page, framework: .standard).contains("theme-palette--") == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func foregroundVariantsAndOpacity(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var parts: [PartNode] = []
        for colour in ["theme-primary", "theme-warning", "token:fg-bg", "token:link-color"] {
            for variant in ["normal", "emphasis", "contrast"] {
                for opacity in [0, 50, 55, 100] {
                    var node = PartNode.make(.paragraph)
                    node.anchor = "sample-\(parts.count)"
                    node.setProperty(.init(rawValue: "foreground.theme"), value: .choice(colour))
                    node.setProperty(.init(rawValue: "foreground.variant"), value: .choice(variant))
                    node.setProperty(.init(rawValue: "foreground.opacity"), value: .number(Double(opacity)))
                    let prefix = variant == "normal" ? "fg-" : "fg-\(variant)-"
                    let expected = colour == "theme-primary" ? prefix + "primary" : colour == "theme-warning" ? prefix + "warning" : colour == "token:fg-bg" ? "fg-bg" : "fg-token--link-color"
                    let actual = BootstrapControlGroupClasses.resolve(node: node, key: .init(rawValue: "foreground.theme"), framework: .standard)
                    #expect(actual == expected)
                    parts.append(node)
                }
            }
        }
        let page = Page(title: "Variants", slug: "index", parts: parts)
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, framework: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Variants", pages: [page]))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
          (() => {const errors=[],ref=document.createElement('span');document.body.append(ref);
          for(const mode of ['light','dark']) {
            document.documentElement.dataset.bsTheme=mode;
            for(let i=0;i<48;i++) {
              const el=document.getElementById('sample-'+i), amount=[0,50,55,100][i%4];
              const fg=getComputedStyle(el).getPropertyValue('--bs-fg');
              if(!fg.trim()) errors.push(mode+i+' missing colour');
              ref.style.setProperty('--bs-fg',fg);
              ref.style.color=amount===100?'var(--bs-fg)':`color-mix(in oklch,var(--bs-fg) ${amount}%,transparent)`;
              if(getComputedStyle(el).color!==getComputedStyle(ref).color) errors.push(mode+i+' opacity');
              if(getComputedStyle(el).opacity!=='1') errors.push(mode+i+' element opacity');
            }
          }return errors;})()
          """) as? [String]
        #expect(errors == [])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [PartType.container, .flex, .grid])
    func foregroundInheritanceAndOverrides(environment: PartTemplateEnvironment, layout: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var container = PartNode.make(layout)
        container.anchor = "parent"
        container.setProperty(.init(rawValue: "foreground.theme"), value: .choice("token:fg-1"))
        var inherited = PartNode.make(.paragraph)
        inherited.anchor = "inherited"
        let colourKey = PartProperty.Key(rawValue: "foreground.theme")
        #expect(inherited.property(colourKey) == "inherit")
        #expect(inherited.type.definition.package?.manifest.resolvedProperties.contains { $0.id == "foreground.enabled" } == false)
        inherited.setProperty(colourKey, value: .choice("theme-warning"))
        #expect(BootstrapControlGroupClasses.resolve(node: inherited, key: colourKey, framework: .standard) == "fg-warning")
        inherited.setProperty(colourKey, value: .choice("inherit"))
        inherited.setProperty(.init(rawValue: "foreground.opacity"), value: .number(55))
        #expect(BootstrapPartUtilityCSS.render(node: inherited, framework: .standard).isEmpty)
        #expect(BootstrapControlGroupClasses.resolve(node: inherited, key: .init(rawValue: "foreground.opacity"), framework: .standard) == "")
        #expect(BootstrapControlGroupClasses.resolve(node: inherited, key: colourKey, framework: .standard) == "")
        var explicit = PartNode.make(.paragraph)
        explicit.anchor = "explicit"
        explicit.setProperty(.init(rawValue: "foreground.theme"), value: .choice("token:black"))
        container.children = [inherited, explicit]
        for type in [PartType.container, .paragraph] {
            let group = try #require(type.definition.package?.manifest.controlGroups.first { $0.type == .foreground })
            #expect(group.colourSections == ["foregrounds", "blackWhite"])
        }
        let page = Page(title: "Foreground", slug: "index", parts: [container])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, framework: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Foreground", pages: [page]))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
          (() => {const errors=[],ref=document.createElement('span');document.body.append(ref);
          for(const mode of ['light','dark']) {
            document.documentElement.dataset.bsTheme=mode;
            ref.style.color='var(--bs-fg-1)';
            for(const id of ['parent','inherited']) if(getComputedStyle(document.getElementById(id)).color!==getComputedStyle(ref).color) errors.push(mode+id);
            ref.style.color='var(--bs-black)';
            if(getComputedStyle(document.getElementById('explicit')).color!==getComputedStyle(ref).color) errors.push(mode+'explicit');
          }return errors;})()
          """) as? [String]
        #expect(errors == [])
    }
}
