import Testing
import WebKit
@testable import Foundry

@MainActor
struct LayoutColourInheritanceTests {
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [PartType.container, .flex, .grid])
    func nestedLinksRespectInheritance(environment: PartTemplateEnvironment, layout: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "editorial", kind: .link)
        var palette = try #require(model.storedPalettes.last)
        palette.bootstrapTokens[palette.colourTokens[0]] = .init(light: .native("red"), dark: .native("green"))
        palette.bootstrapTokens[palette.colourTokens[1]] = .init(light: .native("pink"), dark: .native("blue"))
        var theme = Theme.standard
        theme.colourPalettes.append(palette)
        var parent = PartNode.make(layout)
        let groups = try #require(parent.type.definition.package?.manifest.controlGroups)
        #expect(groups.contains { $0.type == .background })
        #expect(groups.contains { $0.type == .foreground })
        #expect(groups.contains { $0.type == .linkStyling })
        let group = try #require(groups.first { $0.type == .linkStyling })
        #expect(BootstrapLinkStyling.css(node: parent, group: group, theme: theme).isEmpty)
        parent.setProperty(.init(rawValue: "links.colour"), value: .choice("token:" + palette.colourTokens[0]))
        parent.setProperty(.init(rawValue: "links.decoration"), value: .choice("off"))
        func paragraph(_ id: String) -> PartNode {
            var node = PartNode.make(.paragraph)
            node.setProperty(.init(rawValue: "content"), value: .string(FoundryRichTextCodec.storageValue(forHTMLFragment:
                "<a id=\"\(id)\" href=\"/\">Link</a>")))
            return node
        }
        let inherited = paragraph("inherited")
        var explicit = paragraph("explicit")
        explicit.setProperty(.init(rawValue: "links.colour"), value: .choice("token:link-color"))
        explicit.setProperty(.init(rawValue: "links.decoration"), value: .choice("underline"))
        var nested = PartNode.make(layout)
        nested.children = [inherited, explicit]
        parent.children = [nested]
        let page = Page(title: "Links", slug: "index", parts: [parent, paragraph("outside")])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: theme)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Links", pages: [page], theme: theme))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            let css = try #require(bundle.file(at: "files/site.css")?.contents) + (try #require(bundle.file(at: "files/page.css")?.contents))
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
            (()=>{const errors=[],s=id=>getComputedStyle(document.getElementById(id)),ref=document.createElement('span');document.body.append(ref);
            for(const mode of ['light','dark']){
              document.documentElement.dataset.bsTheme=mode;
              ref.style.color=mode==='light'?'var(--bs-red-500)':'var(--bs-green-500)';
              if(s('inherited').color!==getComputedStyle(ref).color)errors.push(mode+' inherited');
              if(s('explicit').color!==s('outside').color)errors.push(mode+' explicit');
              if(s('inherited').textDecorationLine!=='none')errors.push(mode+' decoration inherited');
              if(s('explicit').textDecorationLine!=='underline')errors.push(mode+' decoration explicit');
            }return errors;})()
            """) as? [String]
        #expect(errors == [])
    }
}
