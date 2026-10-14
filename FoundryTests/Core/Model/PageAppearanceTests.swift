import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct PageAppearanceTests {
    @Test func siteBrowserDefaultDoesNotDisableEitherAppearance() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        #expect(document.site.appearanceMode == .both)
        #expect(document.site.appearanceMode.cssColorScheme == "light dark")
        for mode in SiteAppearanceMode.allCases {
            undo.beginUndoGrouping()
            editor.setSiteAppearanceMode(mode)
            undo.endUndoGrouping()
            #expect(document.site.appearanceMode == mode)
            #expect(mode.cssColorScheme == "light dark")
            #expect(mode.colour(light: "red", dark: "blue") == "light-dark(red, blue)")
            #expect(mode.bootstrap(siteID: document.site.id).contains("let current = '\(mode.defaultMode)'"))
        }
        undo.undo()
        #expect(document.site.appearanceMode == .dark)
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(restored.appearanceMode == .dark)
    }

    @Test func publishedPageKeepsBrowserDefaultWithoutSwitcher() throws {
        var site = Site.starter()
        site.pages[0].parts = []
        for mode in SiteAppearanceMode.allCases {
            site.appearanceMode = mode
            let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
            #expect(html.contains("<meta name=\"color-scheme\" content=\"light dark\">"))
            #expect(html.contains("let current = '\(mode.defaultMode)'"))
            #expect(html.contains("window.foundryAppearance ="))
        }
    }

    @Test func persistsDuplicatesAndUndoes() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let id = document.site.pages[0].id
        #expect(document.site.pages[0].appearanceOverride == nil)
        undo.beginUndoGrouping()
        editor.setPageAppearance(id: id, value: .dark)
        undo.endUndoGrouping()
        let page = document.site.pages[0]
        #expect(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)).appearanceOverride == .dark)
        #expect(page.duplicated(title: "Copy", slug: "copy").appearanceOverride == .dark)
        undo.undo()
        #expect(document.site.pages[0].appearanceOverride == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [SiteAppearance.light, .dark], [PartTemplateEnvironment.canvas, .preview, .published])
    func fixedModeWinsOverSiteAndVisitorChoice(mode: SiteAppearance, environment: PartTemplateEnvironment) async throws {
        var site = Site.starter()
        site.appearanceMode = mode == .dark ? .light : .dark
        site.pages[0].parts = []
        site.pages[0].appearanceOverride = mode
        var html = environment == .canvas
            ? HTMLPageRenderer(appearance: mode == .dark ? .light : .dark).render(page: site.pages[0], theme: site.theme)
            : try #require(StaticSiteRenderer(environment: environment).render(site: site).file(at: "index.html")?.contents)
        #expect(html.contains("<body data-bs-theme=\"\(mode.rawValue)\""))
        #expect(html.contains("<html lang=\"en\">"))
        let script = SiteAppearanceMode.both.bootstrap(siteID: site.id)
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(BootstrapColourCatalogue.sourceCSS)</style>\(script)</head>")
        html = html.replacingOccurrences(of: "</body>", with: "<div id=\"nested\" data-bs-theme=\"\(mode == .dark ? "light" : "dark")\" class=\"bg-body\">Nested part</div></body>")
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let result = try await browser.web.evaluateJavaScript("""
        (() => {
          window.foundryAppearance.set('\(mode == .dark ? "light" : "dark")');
          const parentMode = getComputedStyle(document.documentElement).colorScheme;
          const pageMode = getComputedStyle(document.body).colorScheme;
          const nestedMode = getComputedStyle(document.getElementById('nested')).colorScheme;
          const pageColour = getComputedStyle(document.body).backgroundColor;
          const partColour = getComputedStyle(document.getElementById('nested')).backgroundColor;
          const visitorChoice = window.foundryAppearance.get();
          document.body.removeAttribute('data-bs-theme');
          const inheritedMode = getComputedStyle(document.body).colorScheme;
          window.foundryAppearance.set('system');
          return [parentMode, pageMode, nestedMode, visitorChoice, inheritedMode,
                  String(pageColour !== partColour), String(document.documentElement.hasAttribute('data-bs-theme'))];
        })()
        """) as? [String]
        let other = mode == .dark ? "light" : "dark"
        #expect(result == [other, mode.rawValue, other, other, other, "true", "false"])
    }

    @Test func inheritedModeKeepsVisitorPreferenceSupport() {
        let script = SiteAppearanceMode.both.bootstrap(siteID: UUID())
        #expect(script.contains("localStorage.getItem"))
        #expect(script.contains("localStorage.setItem"))
        #expect(script.contains("locked:true") == false)
        #expect(SiteAppearanceMode.light.bootstrap(siteID: UUID()).contains("let current = 'light'"))
    }
}
