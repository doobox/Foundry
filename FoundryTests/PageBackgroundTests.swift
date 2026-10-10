import Foundation
import Testing
@testable import Foundry

@MainActor
struct PageBackgroundTests {
    @Test func inheritanceOverrideResetAndUndo() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let page = document.site.pages[0]
        #expect(page.backgroundOverride == nil)
        #expect(page.backgroundColour(theme: document.site.theme, appearance: .dark) == "var(--bs-bg-body)")
        let selection = "token:bg-1"
        undo.beginUndoGrouping()
        editor.setPageBackground(id: page.id, value: selection)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        editor.setPageBackground(id: page.id, value: nil)
        undo.endUndoGrouping()
        #expect(document.site.pages[0].backgroundOverride == nil)
        undo.undo()
        #expect(document.site.pages[0].backgroundOverride == selection)
        undo.redo()
        #expect(document.site.pages[0].backgroundOverride == nil)
    }

    @Test func semanticBackgroundsPersistDuplicateAndRenderInBothAppearances() throws {
        var site = Site.starter()
        site.appearanceMode = .both
        let selection = "token:bg-1"
        site.pages[0].parts = []
        site.pages[0].backgroundOverride = selection
        let page = site.pages[0]
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(restored.pages[0].backgroundOverride == selection)
        #expect(page.duplicated(title: "Copy", slug: "copy").backgroundOverride == selection)
        #expect(HTMLPageRenderer(appearance: .light).render(page: page, theme: site.theme).contains("body { background: var(--bs-bg-1); }"))
        #expect(HTMLPageRenderer(appearance: .dark).render(page: page, theme: site.theme).contains("body { background: var(--bs-bg-1); }"))
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(html.contains("background-color: var(--bs-bg-1)"))
        site.appearanceMode = .dark
        #expect(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents.contains("background-color: var(--bs-bg-1)") == true)
    }

    @Test func obsoletePalettePropertyValuesAreRejected() {
        let data = Data(##"{"packageColor":{"_0":{"source":"primary","customColor":"#000000","opacity":1}}}"##.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PartProperty.Value.self, from: data) }
    }

    @Test func obsoletePageBackgroundObjectsAreRejected() throws {
        let page = Page(title: "Home", slug: "index")
        let data = try JSONEncoder().encode(page)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["backgroundOverride"] = ["source": "primary", "shade": 7]
        let obsolete = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Page.self, from: obsolete) }
    }

    @Test func pageThemeUsageRequiresReplacement() throws {
        let document = FoundryDocument()
        let custom = try document.site.theme.colourPalettes[0].duplicated()
        document.site.theme.colourPalettes.insert(custom, at: 0)
        document.site.pages[0].backgroundOverride = custom.id
        let session = ThemeEditorSession(document: document, undoManager: UndoManager())
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site.theme.colourPalettes.contains { $0.id == custom.id })
        session.deleteColour(custom.id, replacement: "framework.primary")
        #expect(!document.site.theme.colourPalettes.contains { $0.id == custom.id })
        #expect(document.site.pages[0].backgroundOverride == "framework.primary")
    }
}
