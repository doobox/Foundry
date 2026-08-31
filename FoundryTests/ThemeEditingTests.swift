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
    func customSpacingsCanBeAddedEditedPersistedAndRemoved() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        let id = editor.addThemeSpacing()
        editor.setThemeSpacingName(id: id, value: "Hero Gap")
        editor.setThemeSpacingValue(id: id, value: 18)

        let spacing = try #require(document.site.theme.spacing.custom.first(where: { $0.id == id }))
        #expect(spacing.name == "Hero Gap")
        #expect(spacing.value == 18)
        #expect(document.site.theme.spacingCSSVariables.contains("\(spacing.cssVariable):calc(var(--spacing) * 18.0)"))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.theme.spacing.custom == [spacing])

        undoManager.removeAllActions()
        editor.removeThemeSpacing(id: id)
        #expect(document.site.theme.spacing.custom.isEmpty)
        undoManager.undo()
        #expect(document.site.theme.spacing.custom == [spacing])
    }

    @Test
    func legacySpacingScaleGetsNewPredefinedDefaults() throws {
        let data = Data(#"{"small":8,"medium":16,"large":32}"#.utf8)
        let spacing = try JSONDecoder().decode(SpacingTokens.self, from: data)

        #expect(spacing.extraSmall == 1)
        #expect(spacing.extraLarge == 16)
        #expect(spacing.custom.isEmpty)
    }

    @Test
    func predefinedSpacingScaleCanResetWithoutRemovingCustomSpacings() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let customID = editor.addThemeSpacing()
        editor.setThemeSpacing(.extraSmallSpacing, value: 6)
        editor.setThemeSpacing(.mediumSpacing, value: 23.5)

        editor.resetThemeSpacingScale()

        #expect(document.site.theme.spacing.usesStandardPredefinedScale)
        #expect(document.site.theme.spacing.custom.map(\.id) == [customID])
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
    func switchingBackFromGoogleRestoresTheLastFontNames() throws {
        var site = Site.starter()
        site.theme.typography.bodyFont.family = "Libre Franklin"
        site.theme.typography.bodyFont.fallbacks = []
        site.theme.typography.bodyFont.source = .remote(stylesheetURL: try #require(
            ThemeFontDefinition.googleStylesheetURL(for: "Libre Franklin")
        ))
        site.theme.typography.bodyFont.systemFontNames = ["Avenir Next", "system-ui", "sans-serif"]
        let document = FoundryDocument(site: site)
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        editor.restoreThemeFontNames(reference: .role(.body))

        let restored = document.site.theme.typography.bodyFont
        #expect(restored.family == "Avenir Next")
        #expect(restored.fallbacks == ["system-ui", "sans-serif"])
        #expect(restored.source == .system)

        undoManager.undo()
        #expect(document.site.theme.typography.bodyFont.family == "Libre Franklin")
    }

    @Test
    func fontNameMemoryRoundTripsWithTheProject() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        editor.setThemeFontNames("Charter, serif", reference: .role(.heading))
        editor.setThemeGoogleFont("ABeeZee", reference: .role(.heading))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.theme.typography.headingFont.systemFontNames == ["Charter", "serif"])
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

    @Test
    func duplicateRemoteFontSourcesProduceOneStylesheetImport() throws {
        var theme = Theme.standard
        let url = try #require(ThemeFontDefinition.googleStylesheetURL(for: "Inter"))
        theme.typography.bodyFont.source = .remote(stylesheetURL: url)
        theme.typography.headingFont.source = .remote(stylesheetURL: url)

        let css = theme.fontSourceCSS(assets: [:], destination: .export)

        #expect(css.components(separatedBy: url.absoluteString).count - 1 == 1)
    }

    @Test
    func googleFontMetadataDecodesIntoSortedFamilies() throws {
        let data = Data("""
        )]}'{
          "familyMetadataList": [
            {"family":"Zulu","category":"SERIF","fonts":{"400":{}}},
            {"family":"Alpha Sans","category":"SANS_SERIF","fonts":{"400":{},"700":{}}}
          ]
        }
        """.utf8)

        let families = try GoogleFontsService.decodeFamilies(from: data)

        #expect(families.map(\.family) == ["Alpha Sans", "Zulu"])
        #expect(families[0].category == "Sans Serif")
        #expect(families[0].styleCount == 2)
    }

    @Test
    func themeWindowRegistryPreservesTheLiveDocumentAndUndoManager() throws {
        let id = UUID()
        let document = FoundryDocument()
        let undoManager = UndoManager()

        ThemeWindowRegistry.shared.register(
            id: id,
            document: document,
            undoManager: undoManager
        )
        let context = try #require(ThemeWindowRegistry.shared.context(for: id))

        #expect(context.session.document === document)
        #expect(context.session.editor.undoManager === undoManager)

        ThemeWindowRegistry.shared.remove(id: id)
        #expect(ThemeWindowRegistry.shared.context(for: id) == nil)
    }

    @Test
    func browsingGoogleFontsDoesNotMutateTheDocumentUntilCommitted() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let session = ThemeEditorSession(document: document, undoManager: undoManager)
        let original = document.site.theme.typography.bodyFont

        session.previewGoogleFont("Inter", for: .role(.body))
        session.previewGoogleFont("Libre Franklin", for: .role(.body))

        #expect(document.site.theme.typography.bodyFont == original)
        #expect(session.font(for: .role(.body)).family == "Libre Franklin")
        #expect(!undoManager.canUndo)

        session.commitFontPreview()

        #expect(document.site.theme.typography.bodyFont.family == "Libre Franklin")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(document.site.theme.typography.bodyFont == original)
    }

    @Test
    func discardingGoogleFontPreviewLeavesTheDocumentUntouched() {
        let document = FoundryDocument()
        let session = ThemeEditorSession(document: document, undoManager: UndoManager())
        let original = document.site.theme.typography.headingFont

        session.previewGoogleFont("Roboto", for: .role(.heading))
        session.discardFontPreview()

        #expect(session.font(for: .role(.heading)) == original)
        #expect(document.site.theme.typography.headingFont == original)
    }
}
