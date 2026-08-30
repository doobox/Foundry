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

    @Test
    func fontNamesUpdateFamilyFallbacksAndSource() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeFontNames("Inter, system-ui, sans-serif", reference: .role(.body))

        let font = document.site.theme.typography.bodyFont
        #expect(font.family == "Inter")
        #expect(font.fallbacks == ["system-ui", "sans-serif"])
        #expect(font.source == .system)
    }

    @Test
    func googleFontSelectionCreatesAWorkingStylesheetSource() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeGoogleFont("Libre Franklin", reference: .role(.heading))

        let font = document.site.theme.typography.headingFont
        #expect(font.family == "Libre Franklin")
        guard case .remote(let source) = font.source else {
            Issue.record("Expected a remote Google Fonts source")
            return
        }
        #expect(source.absoluteString == "https://fonts.googleapis.com/css2?family=Libre+Franklin&display=swap")
    }

    @Test
    func bundledFontResourcesRenderForCanvasAndExport() {
        let asset = ProjectAsset(filename: "Foundry Sans.woff2", mediaType: "font/woff2", byteCount: 3)
        let content = ProjectAssetContent(asset: asset, data: Data([1, 2, 3]))
        let assets = [asset.id: content]
        var theme = Theme.standard
        theme.typography.bodyFont.family = "Foundry Sans"
        theme.typography.bodyFont.source = .bundled(files: [asset.reference])

        let canvasCSS = theme.fontSourceCSS(assets: assets, destination: .canvas)
        let exportCSS = theme.fontSourceCSS(assets: assets, destination: .export)

        #expect(canvasCSS.contains("@font-face"))
        #expect(canvasCSS.contains("data:font/woff2;base64,AQID"))
        #expect(exportCSS.contains("url('images/\(asset.storageFilename)')"))
    }
}
