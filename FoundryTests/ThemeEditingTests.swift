import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemeEditingTests {
    @Test
    func switchingThemesPreservesPerThemeEditsAndProjectThemeValues() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let systemTheme = document.site.theme
        let alternateID = UUID()
        var alternateTheme = systemTheme
        alternateTheme.colors.accent = "#112233"

        let customSpacingID = editor.addThemeSpacing()
        editor.setThemeColor(.accentColor, value: "#AABBCC")
        editor.selectTheme(alternateTheme, sourceID: alternateID)

        #expect(document.site.theme.colors.accent == "#112233")
        #expect(document.site.theme.spacing.custom.contains { $0.id == customSpacingID })

        editor.setThemeColor(.accentColor, value: "#445566")
        editor.selectTheme(systemTheme, sourceID: ThemeBundleStore.systemThemeID)

        #expect(document.site.theme.colors.accent == "#AABBCC")
        #expect(document.site.theme.spacing.custom.contains { $0.id == customSpacingID })

        editor.selectTheme(alternateTheme, sourceID: alternateID)
        #expect(document.site.theme.colors.accent == "#445566")
        #expect(document.site.theme.spacing.custom.contains { $0.id == customSpacingID })
    }

    @Test
    func customFontSizeIDsCannotCollideWithManualControlSelection() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let firstID = editor.addThemeFontSize()
        let secondID = editor.addThemeFontSize()

        #expect(firstID != ComponentThemeValueSelection.manualCustom)
        #expect(firstID != ComponentThemeValueSelection.legacyManualCustom)
        #expect(secondID != firstID)
        #expect(document.site.theme.typography.customFontSizes.contains { $0.id == firstID })
        #expect(ComponentThemeValueSelection.isManualCustom(
            ComponentThemeValueSelection.manualCustom,
            themeChoices: document.site.theme.fontSizeChoices
        ))
    }

    @Test
    func legacyCustomFontSizeIDIsTreatedAsAThemeChoiceWhenPresent() {
        var theme = Theme.standard
        theme.typography.customFontSizes.append(
            .init(id: "custom", title: "Legacy Custom", size: 2, lineHeight: 1.5)
        )

        #expect(!ComponentThemeValueSelection.isManualCustom(
            "custom",
            themeChoices: theme.fontSizeChoices
        ))
        #expect(theme.fontSizeCSSVariable(for: "custom") == "var(--foundry-font-size-custom)")
    }

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
        container.setProperty(.backgroundColor, value: .packageColor(.init(
            source: ThemeColorRole.accent.rawValue,
            customColor: "#000000",
            adjustment: 0,
            opacity: 1
        )))
        container.setProperty(.padding, value: .packageSpacing(.init(
            sources: ["lg", "lg", "lg", "lg"],
            customValues: [0, 0, 0, 0]
        )))
        let page = Page(title: "Tokens", slug: "tokens", components: [container])

        let html = HTMLPageRenderer().render(page: page, theme: theme)

        #expect(html.contains("background-color: #123ABC"))
        #expect(html.contains("padding: var(--foundry-space-lg) var(--foundry-space-lg) var(--foundry-space-lg) var(--foundry-space-lg)"))
    }

    @Test
    func legacyThemeColorsUseAccentForLinks() throws {
        let data = Data("{\"background\":\"#FFFFFF\",\"surface\":\"#EEEEEE\",\"text\":\"#111111\",\"accent\":\"#123ABC\"}".utf8)
        let colors = try JSONDecoder().decode(ColorTokens.self, from: data)

        #expect(colors.links == "#123ABC")
    }

    @Test @MainActor
    func paragraphColorAppliesPickerOpacityOnlyToCustomColors() {
        _ = ComponentPackageCatalog.shared
        var paragraph = ComponentNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: ThemeColorRole.accent.rawValue,
            customColor: "#000000",
            adjustment: -20,
            opacity: 0.5
        )))

        let darkened = ComponentTemplateRenderer.transformColor("#5B5BD6", target: 0, amount: 0.2)
        let page = Page(title: "Colour", slug: "colour", components: [paragraph])
        let themedHTML = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(themedHTML.contains("color: \(darkened)"))
        #expect(!themedHTML.contains("color: rgb("))

        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: "custom",
            customColor: "#123456",
            adjustment: 0,
            opacity: 0.5
        )))
        let customPage = Page(title: "Colour", slug: "colour", components: [paragraph])
        let customHTML = HTMLPageRenderer().render(page: customPage, theme: .standard)
        #expect(customHTML.contains("color: \(ComponentTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))"))
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
        #expect(document.site.theme.spacingCSSVariables.contains("\(spacing.cssVariable):calc(var(--foundry-spacing-base) * 18.0)"))

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
    func incompleteSpacingScaleGetsNewPredefinedDefaults() throws {
        let data = Data(#"{"large":32}"#.utf8)
        let spacing = try JSONDecoder().decode(SpacingTokens.self, from: data)

        #expect(spacing.threeExtraSmall == 1)
        #expect(spacing.doubleExtraSmall == 2)
        #expect(spacing.extraSmall == 3)
        #expect(spacing.small == 4)
        #expect(spacing.medium == 6)
        #expect(spacing.large == 32)
        #expect(spacing.extraLarge == 12)
        #expect(spacing.doubleExtraLarge == 16)
        #expect(spacing.threeExtraLarge == 24)
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
    func themeScreensPersistContainerUnitsAndDriveResponsiveRanges() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeScreenMinimumWidth(.medium, value: 820)
        editor.setThemeScreenContainerUnit(.large, value: .viewportWidth)
        editor.setThemeScreenContainerWidth(.large, value: 92)

        #expect(ResponsiveBreakpoint.forViewportWidth(575, screens: document.site.theme.screens) == .mobile)
        #expect(ResponsiveBreakpoint.forViewportWidth(576, screens: document.site.theme.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(819, screens: document.site.theme.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(820, screens: document.site.theme.screens) == .medium)
        #expect(document.site.theme.screens.containerCSS.contains("92vw"))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.theme.screens == document.site.theme.screens)
    }

    @Test
    func screenContainerCSSSupportsAutoPixelsViewportAndPercent() {
        var screens = ScreenTokens.standard
        screens.update(.extraLarge) { $0.isEnabled = true }
        screens.update(.small) { $0.container = .init(value: 700, unit: .pixels) }
        screens.update(.medium) { $0.container = .init(value: 88, unit: .viewportWidth) }
        screens.update(.large) { $0.container = .init(value: 94, unit: .percent) }

        #expect(screens.containerCSS.contains("--foundry-container-width:none"))
        #expect(screens.containerCSS.contains("700px"))
        #expect(screens.containerCSS.contains("88vw"))
        #expect(screens.containerCSS.contains("94%"))
        #expect(screens.containerCSS.contains("1200px"))
    }

    @Test
    func canvasScreenPresetsFollowEnabledThemeBreakpoints() {
        var screens = ScreenTokens.standard
        screens.update(.small) { $0.isEnabled = false }
        screens.update(.medium) { $0.minimumWidth = 800 }

        #expect(screens.enabledScreens.map(\.id).contains(.small) == false)
        #expect(screens.canvasWidth(for: screens.screen(.medium)) == 800)
        #expect(screens.activeScreen(for: 799).id == .mobile)
        #expect(screens.activeScreen(for: 800).id == .medium)
        #expect(screens.enabledScreens.map(\.id).contains(.extraLarge) == false)
        #expect(screens.enabledScreens.map(\.id).contains(.doubleExtraLarge) == false)
        #expect(screens.activeScreen(for: 1_600).id == .large)
    }

    @Test
    func userThemeBundleRoundTripsThemeAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrytheme", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        var theme = Theme.standard
        theme.colors.accent = "#123456"
        let fontData = Data("font-data".utf8)
        let fontAsset = ProjectAsset(
            filename: "Studio.woff2",
            mediaType: "font/woff2",
            byteCount: fontData.count
        )
        theme.typography.bodyFont.source = .bundled(files: [fontAsset.reference])
        let systemTheme = try #require(
            ThemeBundleStore.builtInThemes().first(where: { $0.id == ThemeBundleStore.systemThemeID })
        )
        let preview = try ThemeBundleStore.preview(from: systemTheme.previewURL)

        let saved = try ThemeBundleStore.write(
            theme: theme,
            name: "Studio",
            preview: preview,
            assetContents: [fontAsset.id: ProjectAssetContent(asset: fontAsset, data: fontData)],
            to: root
        )
        let loaded = try ThemeBundleStore.load(from: root)

        #expect(loaded.id == saved.id)
        #expect(loaded.metadata.name == "Studio")
        #expect(loaded.theme == theme)
        #expect(loaded.resources == [ProjectAssetContent(asset: fontAsset, data: fontData)])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Contents/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Contents/Resources/theme.json").path))
        #expect(FileManager.default.fileExists(atPath: loaded.previewURL.path))
    }

    @Test
    func systemUIThemeLoadsFromTheBuiltInThemeBundle() throws {
        let systemTheme = try #require(
            ThemeBundleStore.builtInThemes().first(where: { $0.id == ThemeBundleStore.systemThemeID })
        )

        #expect(systemTheme.isBuiltIn)
        #expect(systemTheme.metadata.name == "System UI")
        #expect(systemTheme.theme == Theme.standard)
        #expect(systemTheme.metadata.previewFilename == "preview.png")
        #expect(ThemeBundleStore.systemTheme == Theme.standard)
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
        #expect(exportCSS.contains("url('\(asset.storageFilename)')"))
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
