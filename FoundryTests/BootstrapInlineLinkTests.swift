import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapInlineLinkTests {
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func inlineLinksAreScopedAndFollowThemeTokens(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "editorial", kind: .link)
        var palette = try #require(model.storedPalettes.first { $0.name == "editorial" })
        palette.bootstrapTokens[palette.colourTokens[0]] = .init(light: .native("red"), dark: .native("green"))
        palette.bootstrapTokens[palette.colourTokens[1]] = .init(light: .native("blue"), dark: .native("pink"))
        var theme = Theme.standard
        theme.colourPalettes.append(palette)
        var paragraph = PartNode.make(.paragraph)
        paragraph.anchor = "styled"
        paragraph.setProperty(.init(rawValue: "content"), value: .string(FoundryRichTextCodec.storageValue(forHTMLFragment:
            #"Plain <a id="inline" href="/">Link</a> <a id="button" class="btn btn-solid theme-primary" href="/">Button</a>"#)))
        var untouched = PartNode.make(.paragraph)
        untouched.anchor = "untouched"
        untouched.setProperty(.init(rawValue: "content"), value: .string(FoundryRichTextCodec.storageValue(forHTMLFragment:
            #"Plain <a id="other" href="/">Link</a> <a id="other-button" class="btn btn-solid theme-primary" href="/">Button</a>"#)))
        for (key, value) in ["colour":"token:" + palette.colourTokens[0], "decoration":"hover"] {
            paragraph.setProperty(.init(rawValue: "links." + key), value: .choice(value))
        }
        let page = Page(title: "Inline links", slug: "index", parts: [paragraph, untouched])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: theme)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Links", pages: [page], theme: theme))
            #expect(bundle.errors.isEmpty)
            let document = try #require(bundle.file(at: "index.html")?.contents)
            // Match the document's actual stylesheet order: vendor/site before page.
            let css = (try #require(bundle.file(at: "files/site.css")?.contents))
                + (try #require(bundle.file(at: "files/page.css")?.contents))
            html = document.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (()=>{const errors=[],s=id=>getComputedStyle(document.getElementById(id)),ref=document.createElement('a');document.body.append(ref);
          for(const mode of ['light','dark']) {
            document.documentElement.dataset.bsTheme=mode;
            ref.style.color=mode==='light'?'var(--bs-red-500)':'var(--bs-green-500)';
            if(s('inline').color!==getComputedStyle(ref).color)errors.push(mode+' colour');
            if(s('inline').textDecorationLine!=='none')errors.push('decoration');
            if(s('styled').color!==s('untouched').color)errors.push('ordinary text changed');
            if(s('button').color!==s('other-button').color||s('button').textDecorationLine!==s('other-button').textDecorationLine)errors.push('button changed');
            if(s('other').textDecorationLine!=='underline')errors.push('other link changed');
          }ref.remove();return errors;})()
        """) as? [String]
        #expect(errors == [])
        let group = try #require(paragraph.type.definition.package?.manifest.controlGroups.first { $0.type == .linkStyling })
        let css = BootstrapLinkStyling.css(node: paragraph, group: group, theme: theme)
        #expect(css.contains("@media(hover:hover)"))
        // Exercise the same hover declarations deterministically without moving the user's pointer.
        let hoverCSS = css.replacingOccurrences(of: "@media(hover:hover)", with: "@media all").replacingOccurrences(of: ":hover{", with: ".test-hover{")
        let hover = try await browser.web.callAsyncJavaScript("""
            const style=document.createElement('style');style.textContent=css;document.head.append(style);
            document.getElementById('inline').classList.add('test-hover');
            const ref=document.createElement('span');ref.style.color='var(--bs-pink-500)';document.body.append(ref);
            const actual=getComputedStyle(document.getElementById('inline'));
            const result=[actual.color===getComputedStyle(ref).color,actual.textDecorationLine==='underline'];ref.remove();return result;
            """, arguments: ["css": hoverCSS], in: nil, contentWorld: .page) as? [Bool]
        #expect(hover == [true, true])
        #expect(BootstrapLinkStyling.css(node: untouched, group: group, theme: theme).isEmpty)
    }
}
