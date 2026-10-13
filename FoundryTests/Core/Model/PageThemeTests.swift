import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct PageThemeTests {
    @Test func persistenceDuplicationResetAndUndo() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let id = document.site.pages[0].id
        #expect(document.site.pages[0].themeClass(theme: document.site.theme).isEmpty)
        undo.beginUndoGrouping()
        editor.setPageTheme(id: id, value: "theme-accent")
        undo.endUndoGrouping()
        let page = document.site.pages[0]
        let decoded = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        #expect(decoded.themeOverride == "theme-accent")
        #expect(page.duplicated(title: "Copy", slug: "copy").themeOverride == "theme-accent")
        undo.beginUndoGrouping()
        editor.setPageTheme(id: id, value: "inherit")
        undo.endUndoGrouping()
        #expect(document.site.pages[0].themeOverride == nil)
        undo.undo()
        #expect(document.site.pages[0].themeOverride == "theme-accent")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        legacy.removeValue(forKey: "themeOverride")
        let oldPage = try JSONDecoder().decode(Page.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(oldPage.themeOverride == nil)
    }

    @Test func customThemeDeletionRequiresReplacement() throws {
        let document = FoundryDocument()
        var custom = try document.site.theme.colourPalettes[0].duplicated()
        custom.name = "brand"
        document.site.theme.colourPalettes.insert(custom, at: 0)
        document.site.pages[0].themeOverride = custom.id
        #expect(document.site.pages[0].themeClass(theme: document.site.theme) == "theme-" + custom.name)
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site.theme.colourPalettes.contains { $0.id == custom.id })
        session.deleteColour(custom.id, replacement: "framework.primary")
        #expect(document.site.pages[0].themeClass(theme: document.site.theme) == "theme-primary")
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func themeAppliesInEveryOutputWithoutReplacingExplicitThemes(environment: PartTemplateEnvironment) async throws {
        var site = Site.starter()
        site.pages[0].parts = []
        site.pages[0].themeOverride = "theme-accent"
        site.pages[0].backgroundOverride = "token:bg-2"
        var html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: site.pages[0], theme: site.theme)
        } else {
            html = try #require(StaticSiteRenderer(environment: environment).render(site: site).file(at: "index.html")?.contents)
        }
        #expect(html.contains("<body class=\"theme-accent\""))
        #expect(html.contains("var(--bs-bg-2)"))
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(BootstrapColourCatalogue.sourceCSS)</style></head>")
        html = html.replacingOccurrences(of: "</body>", with: """
        <button id="inherited" class="btn btn-solid">Inherited</button>
        <button id="reference" class="btn btn-solid theme-accent">Reference</button>
        <button id="explicit" class="btn btn-solid theme-danger">Explicit</button></body>
        """)
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [];
          for (const mode of ['light', 'dark']) {
            document.documentElement.setAttribute('data-bs-theme', mode);
            const colour = id => getComputedStyle(document.getElementById(id)).backgroundColor;
            if (colour('inherited') !== colour('reference')) errors.push(mode + ': inheritance');
            if (colour('inherited') === colour('explicit')) errors.push(mode + ': explicit override');
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }
}
