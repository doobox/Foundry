import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct PageColourOverrideTests {
    @Test func persistenceDuplicationUndoAndReset() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let id = document.site.pages[0].id
        for (key, value) in [(\Page.foregroundOverride, "token:fg-2"), (\Page.borderOverride, "token:border-subtle"), (\Page.linksOverride, "token:link-color")] {
            undo.beginUndoGrouping()
            editor.setPageColour(id: id, key: key, value: value, label: "Colour")
            undo.endUndoGrouping()
            let page = document.site.pages[0]
            #expect(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))[keyPath: key] == value)
            #expect(page.duplicated(title: "Copy", slug: "copy")[keyPath: key] == value)
            undo.undo()
            #expect(document.site.pages[0][keyPath: key] == nil)
        }
        #expect(BootstrapPageColours.css(page: document.site.pages[0], theme: document.site.theme).isEmpty)
    }

    @Test func customLinkPairAndDeletionReplacement() throws {
        let document = FoundryDocument()
        var palette = try document.site.theme.colourPalettes[0].duplicated()
        palette.name = "brand-links"
        palette.customKind = .link
        document.site.theme.colourPalettes.append(palette)
        document.site.pages[0].linksOverride = "token:" + palette.colourTokens[0]
        let css = BootstrapPageColours.css(page: document.site.pages[0], theme: document.site.theme)
        #expect(css.contains("--bs-link-color:var(--bs-\(palette.colourTokens[0]))"))
        #expect(css.contains("--bs-link-hover-color:var(--bs-\(palette.colourTokens[1]))"))
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(session.colourIsInUse(palette.id))
        session.deleteColour(palette.id, replacement: "inherit")
        #expect(document.site.pages[0].linksOverride == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func browserInheritanceAndExplicitOverrides(environment: PartTemplateEnvironment) async throws {
        var site = Site.starter()
        site.pages[0].parts = []
        site.pages[0].themeOverride = "theme-danger"
        site.pages[0].foregroundOverride = "token:fg-2"
        site.pages[0].borderOverride = "token:border-subtle"
        site.pages[0].linksOverride = "token:link-color"
        site.theme.bootstrapTokens.values["link-color"] = "#123456"
        site.theme.bootstrapTokens.values["link-hover-color"] = "#654321"
        let css = BootstrapPageColours.css(page: site.pages[0], theme: site.theme)
        let output = environment == .canvas
            ? HTMLPageRenderer().render(page: site.pages[0], theme: site.theme)
            : try #require(StaticSiteRenderer(environment: environment).render(site: site).file(at: "index.html")?.contents)
        #expect(output.contains(css))
        let browser = BootstrapTokenBrowser()
        try await browser.load("""
        <!doctype html><style>\(BootstrapColourCatalogue.sourceCSS)\(BootstrapThemeCSS.render(theme: site.theme))\(css)
        @layer utilities{@scope(.part-links){:where(a){color:rgb(100, 0, 0)}}}
        </style><body class="theme-danger">
        <span id="text">Text</span><span id="fg" class="fg-2">Reference</span>
        <span id="explicit" class="fg-white">Explicit</span>
        <div id="border" class="border">Border</div><div id="refborder" class="border border-subtle">Reference</div>
        <div id="borderwhite" class="border border-white">Explicit border</div><div id="plain">No border</div>
        <a id="link" href="#">Link</a><div class="part-links"><a id="partlink" href="#">Part link</a></div>
        </body>
        """)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [], style = id => getComputedStyle(document.getElementById(id));
          for (const mode of ['light', 'dark']) {
            document.documentElement.setAttribute('data-bs-theme', mode);
            if(style('text').color !== style('fg').color) errors.push(mode + ': foreground');
            if(style('explicit').color === style('text').color) errors.push(mode + ': explicit foreground');
            if(style('border').borderTopColor !== style('refborder').borderTopColor) errors.push(mode + ': border');
            if(style('borderwhite').borderTopColor === style('border').borderTopColor) errors.push(mode + ': explicit border');
            if(style('plain').borderTopWidth !== '0px') errors.push('added border');
            if(style('link').color !== 'rgb(18, 52, 86)') errors.push(mode + ': link ' + style('link').color);
            if(style('partlink').color !== 'rgb(100, 0, 0)') errors.push(mode + ': part link');
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }
}
