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
        let index = try #require(document.site.framework.colourPalettes.firstIndex { $0.id == "framework.page" })
        var framework = document.site.framework
        framework.colourPalettes[index].setLightDefault(.two)
        framework.colourPalettes[index].setDarkDefault(.nine)
        #expect(page.backgroundOverride == nil)
        #expect(page.backgroundColour(framework: framework, appearance: .dark) == framework.color(for: .page, appearance: .dark))
        let selection = page.backgroundSelection(framework: framework)
        #expect(selection.shade == .two)
        #expect(selection.darkShade == .nine)
        undo.beginUndoGrouping()
        editor.setPageBackground(id: page.id, value: selection)
        undo.endUndoGrouping()
        let selectedColour = document.site.pages[0].backgroundColour(framework: framework, appearance: .light)
        framework.colourPalettes[index].setLightDefault(.four)
        #expect(document.site.pages[0].backgroundColour(framework: framework, appearance: .light) == selectedColour)
        undo.beginUndoGrouping()
        editor.setPageBackground(id: page.id, value: nil)
        undo.endUndoGrouping()
        #expect(document.site.pages[0].backgroundOverride == nil)
        undo.undo()
        #expect(document.site.pages[0].backgroundOverride == selection)
        undo.redo()
        #expect(document.site.pages[0].backgroundOverride == nil)
    }

    @Test func literalBackgroundsPersistDuplicateAndRenderInBothAppearances() throws {
        var site = Site.starter()
        site.appearanceMode = .both
        var selection = PartPackageColorValue(source: PartFrameworkValueSelection.manualCustom,
            customColor: "#123456", opacity: 1)
        selection.darkCustomColor = "#ABCDEF"
        site.pages[0].parts = []
        site.pages[0].backgroundOverride = selection
        let page = site.pages[0]
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(restored.pages[0].backgroundOverride == selection)
        #expect(page.duplicated(title: "Copy", slug: "copy").backgroundOverride == selection)
        #expect(HTMLPageRenderer(appearance: .light).render(page: page, framework: site.framework).contains("body { background: #123456; }"))
        #expect(HTMLPageRenderer(appearance: .dark).render(page: page, framework: site.framework).contains("body { background: #ABCDEF; }"))
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(html.contains("background-color: light-dark(#123456, #ABCDEF)"))
        site.appearanceMode = .dark
        #expect(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents.contains("background-color: #ABCDEF") == true)
    }

    @Test func pagePaletteUsageRequiresReplacementAndPreservesShades() throws {
        let document = FoundryDocument()
        let custom = try document.site.framework.colourPalettes[0].duplicated()
        document.site.framework.colourPalettes.insert(custom, at: 0)
        document.site.pages[0].backgroundOverride = .init(source: custom.id, customColor: "#000000", opacity: 1,
                                                       shade: .three, darkShade: .eight)
        let session = FrameworkEditorSession(document: document, undoManager: UndoManager())
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site.framework.colourPalettes.contains { $0.id == custom.id })
        session.deleteColour(custom.id, replacement: "framework.page")
        #expect(!document.site.framework.colourPalettes.contains { $0.id == custom.id })
        #expect(document.site.pages[0].backgroundOverride?.paletteID == "framework.page")
        #expect(document.site.pages[0].backgroundOverride?.shade == .three)
        #expect(document.site.pages[0].backgroundOverride?.darkShade == .eight)
    }
}
