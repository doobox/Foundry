import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemeEditingTests {
    @Test
    func designTokenReferencesRoundTripThroughProjectJSON() throws {
        var site = Site.starter()
        let componentID = try #require(site.pages.first?.components.first?.id)
        site.updateComponent(id: componentID) {
            $0.setProperty(.backgroundColor, value: .token(.accentColor))
            $0.setProperty(.padding, value: .token(.largeSpacing))
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let component = try #require(decoded.component(withID: componentID))

        #expect(component.propertyValue(.backgroundColor) == .token(.accentColor))
        #expect(component.propertyValue(.padding) == .token(.largeSpacing))
    }

    @Test
    func rendererResolvesComponentTokensThroughTheme() throws {
        var theme = Theme.standard
        theme.colors.accent = "#123ABC"
        theme.spacing.large = 44
        var container = ComponentNode.make(.container)
        container.setProperty(.backgroundColor, value: .choice("accent"))
        container.setProperty(.padding, value: .token(.largeSpacing))
        let page = Page(title: "Tokens", slug: "tokens", components: [container])

        let html = HTMLPageRenderer().render(page: page, theme: theme)

        #expect(html.contains("background-color: #123ABC"))
        #expect(html.contains("padding: 44px"))
    }

    @Test @MainActor
    func paragraphColorResolvesThemeRoleMathAndOpacity() {
        _ = ComponentPackageCatalog.shared
        var paragraph = ComponentNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "textColor"), value: .choice(ThemeColorRole.accent.rawValue))
        paragraph.setProperty(.init(rawValue: "textColorColorMath"), value: .number(-20))
        paragraph.setProperty(.init(rawValue: "textColorOpacity"), value: .number(0.5))

        let darkened = ComponentTemplateRenderer.transformColor("#5B5BD6", target: 0, amount: 0.2)
        let expected = ComponentTemplateRenderer.colorWithAlpha(darkened, alpha: 0.5)
        let page = Page(title: "Colour", slug: "colour", components: [paragraph])
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("color: \(expected)"))
    }

    @Test
    func themeChangesParticipateInUndoAndRedo() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let original = document.site.theme.colors.accent

        editor.setThemeColor(.accentColor, value: "#112233")
        #expect(document.site.theme.colors.accent == "#112233")

        undoManager.undo()
        #expect(document.site.theme.colors.accent == original)

        undoManager.redo()
        #expect(document.site.theme.colors.accent == "#112233")
    }
}
