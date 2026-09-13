import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemeEditingTests {
    @Test
    func selectingBuiltInDiscardsEditedSnapshotIncludingWhenAlreadyActive() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let defaults = ThemeBundleStore.systemTheme
        var modified = defaults
        modified.typography.headingFont.family = "Georgia"
        let custom = try defaults.colourPalettes[0].duplicated()
        modified.colourPalettes.append(custom)
        document.site.theme = modified
        editor.selectTheme(defaults, sourceID: UUID())
        editor.selectTheme(defaults, sourceID: ThemeBundleStore.systemThemeID)
        #expect(document.site.theme.savedSettings == defaults.savedSettings)
        #expect(document.site.theme.colourPalettes.contains(custom))
        #expect(!document.site.themeStates.contains { $0.sourceID == ThemeBundleStore.systemThemeID })
        document.site.theme.typography.headingFont.family = "Georgia"
        editor.selectTheme(modified, sourceID: ThemeBundleStore.systemThemeID)
        #expect(document.site.theme.savedSettings == defaults.savedSettings)
    }

    @Test
    func themeEditingPermissionFollowsBuiltInIdentity() {
        let document = FoundryDocument()
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(!session.canEditTheme)
        document.site.themeSourceID = UUID()
        #expect(session.canEditTheme)
    }

    @Test
    func colourCopiesHaveUniqueIndependentNames() {
        let model = ThemeColourPreviewModel()
        let palette = model.palettes.first { $0.name == "Accent" }!
        model.duplicate(palette)
        model.duplicate(palette)
        #expect(model.palettes[0].name == "Accent Copy 2")
        #expect(model.palettes[1].name == "Accent Copy")
        #expect(model.storedPalettes.resolvedPalette(id: palette.id)?.origin == .theme)
    }

    @Test
    func editingThemeArtworkPreservesSettingsAndIdentity() throws {
        let system = try #require(ThemeBundleStore.builtInThemes().first { $0.id == ThemeBundleStore.systemThemeID })
        let preview = try ThemeBundleStore.preview(from: system.previewURL)
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundrytheme")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try ThemeBundleStore.create(name: "Before", preview: preview, to: destination)
        let saved = try ThemeBundleStore.load(from: destination)
        let themeURL = destination.appending(path: "Contents/Resources/theme.json")
        let originalData = try Data(contentsOf: themeURL)
        let edited = try ThemeBundleStore.editArtwork(saved, name: "After", preview: preview)
        #expect(edited.id == saved.id)
        #expect(edited.metadata.createdAt == saved.metadata.createdAt)
        #expect(edited.metadata.name == "After")
        #expect(edited.theme == saved.theme)
        #expect(try Data(contentsOf: themeURL) == originalData)
        #expect(try ThemeBundleStore.editArtwork(system, name: "Not Allowed", preview: preview) == system)
    }

    @Test
    func deletingActiveThemeUsesFreshSystemDefaultsAndKeepsCustomColours() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let defaults = ThemeBundleStore.systemTheme
        var editedSystem = defaults
        editedSystem.typography.headingFont.family = "Georgia"
        editor.commitTheme(editedSystem, sourceID: ThemeBundleStore.systemThemeID)
        let otherID = UUID()
        editor.selectTheme(editedSystem, sourceID: otherID)
        let session = ThemeEditorSession(document: document, undoManager: nil)
        let custom = try defaults.colourPalettes[0].duplicated()
        session.setColourPalettes(document.site.theme.colourPalettes + [custom], session: nil)
        editor.didDeleteTheme(sourceID: otherID)
        #expect(document.site.themeSourceID == ThemeBundleStore.systemThemeID)
        #expect(document.site.theme.savedSettings == defaults.savedSettings)
        #expect(document.site.theme.colourPalettes.contains(custom))
        #expect(!document.site.themeStates.contains { $0.sourceID == otherID || $0.sourceID == ThemeBundleStore.systemThemeID })
        let before = document.site.theme
        editor.didDeleteTheme(sourceID: UUID())
        #expect(document.site.theme == before)
    }

    @Test
    func newThemeStartsFromBundledSystemUI() throws {
        let template = try #require(ThemeBundleStore.builtInThemes().first { $0.id == ThemeBundleStore.systemThemeID })
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundrytheme")
        defer { try? FileManager.default.removeItem(at: destination) }
        let created = try ThemeBundleStore.create(
            name: "Fresh Theme",
            preview: ThemeBundleStore.preview(from: template.previewURL),
            to: destination
        )
        #expect(created.id != template.id)
        #expect(created.metadata.name == "Fresh Theme")
        #expect(created.theme.savedSettings == template.theme.savedSettings)
        #expect(try ThemeBundleStore.load(from: destination).theme.savedSettings == template.theme.savedSettings)
    }

    @Test
    func addingCustomColourThroughEditorDoesNotModifySystemTheme() throws {
        let document = FoundryDocument()
        let session = ThemeEditorSession(document: document, undoManager: nil)
        let saved = ThemeBundleStore.systemTheme.savedSettings
        #expect(document.site.theme.savedSettings == saved)
        let model = ThemeColourPreviewModel(storedPalettes: document.site.theme.colourPalettes)
        model.onChange = { palettes, editSession in
            session.setColourPalettes(palettes, session: editSession)
        }
        model.add()
        #expect(document.site.theme.colourPalettes.contains { $0.origin == .custom })
        #expect(document.site.theme.savedSettings == saved)
    }

    @Test
    func modifiedStatusComparesOnlySavedThemeSettings() throws {
        let original = ThemeBundleStore.systemTheme
        var project = original
        var custom = try original.colourPalettes[0].duplicated()
        // Even a matching display name is still owned by the project.
        custom.name = original.colourPalettes[0].name
        project.colourPalettes.insert(custom, at: 0)
        #expect(project.savedSettings == original.savedSettings)
        project.colourPalettes.removeAll { $0.origin == .custom }
        #expect(project.savedSettings == original.savedSettings)

        let index = try #require(project.colourPalettes.firstIndex { $0.id == "theme.accent" })
        var shades = project.colourPalettes[index].shades
        shades[0] = "#123456"
        try project.colourPalettes[index].replaceShades(shades)
        #expect(project.savedSettings != original.savedSettings)

        project = original
        project.typography.headingFont.family = "Georgia"
        #expect(project.savedSettings != original.savedSettings)
    }

    @Test
    func paletteEditsPersistResolveAndUndoAsOneSession() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = ThemeEditorSession(document: document, undoManager: undo)
        let original = document.site.theme.colourPalettes
        #expect(!original.contains { $0.origin == .custom })
        #expect(original.filter { $0.origin == .standard }.count == 24)
        var values = original
        let index = try #require(values.firstIndex { $0.id == "theme.accent" })
        var shades = values[index].shades
        shades[10] = "#123456"
        try values[index].replaceShades(shades)
        values[index].setLightDefault(.eleven)
        let editID = UUID()
        undo.beginUndoGrouping()
        session.setColourPalettes(values, session: editID)
        undo.endUndoGrouping()
        #expect(document.site.theme.colors.accent == "#123456")
        values[index].name = "Renamed Accent"
        session.setColourPalettes(values, session: editID)
        #expect(document.mutationEvent.impact == .theme)
        let saved = try JSONEncoder().encode(document.site)
        let reopened = try JSONDecoder().decode(Site.self, from: saved)
        #expect(reopened.theme.colourPalettes == values)
        #expect(reopened.theme.colors.accent == "#123456")
        undo.undo()
        #expect(document.site.theme.colourPalettes == original)
        #expect(!undo.canUndo)
        undo.redo()
        #expect(document.site.theme.colourPalettes == values)
    }

    @Test
    func customPalettesSurviveThemeSwitchAndDeletion() throws {
        let document = FoundryDocument()
        let session = ThemeEditorSession(document: document, undoManager: UndoManager())
        let originalTheme = document.site.theme
        let originalID = document.site.themeSourceID
        let copy = try originalTheme.colourPalettes[0].duplicated()
        session.setColourPalettes(originalTheme.colourPalettes + [copy], session: nil)
        session.editor.selectTheme(originalTheme, sourceID: UUID())
        #expect(document.site.theme.colourPalettes.contains { $0.id == copy.id })
        session.setColourPalettes(document.site.theme.colourPalettes.filter { $0.id != copy.id }, session: nil)
        session.editor.selectTheme(originalTheme, sourceID: originalID)
        #expect(!document.site.theme.colourPalettes.contains { $0.id == copy.id })
    }

    @Test
    func deletingUsedColourReplacesAllReferencesAndUndoesAtomically() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = ThemeEditorSession(document: document, undoManager: undo)
        let original = try #require(document.site.theme.colourPalettes.first)
        let custom = try original.duplicated()
        document.site.theme.colourPalettes.insert(custom, at: 0)
        let value = BlockPackageColorValue(source: custom.id, customColor: "#000000",
                                              opacity: 1, shade: .eight)
        var child = BlockNode.make(.container)
        child.setProperty(.backgroundColor, value: .packageColor(value))
        var following = value
        following.shade = .one
        child.setResponsiveProperty(.backgroundColor, value: .packageColor(following), at: .medium)
        var parent = BlockNode.make(.container)
        parent.children = [child]
        document.site.pages[0].blocks = [parent]
        document.site.reusableBlocks = [.init(name: "Reusable", root: child)]
        document.site.globalBlocks = [.init(name: "Global", root: child)]
        let before = document.site
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site == before)
        undo.beginUndoGrouping()
        session.deleteColour(custom.id, replacement: original.id)
        undo.endUndoGrouping()
        #expect(!session.colourIsInUse(custom.id))
        #expect(!document.site.theme.colourPalettes.contains { $0.id == custom.id })
        var expected = value
        expected.source = original.id
        var expectedFollowing = following
        expectedFollowing.source = original.id
        for node in [document.site.pages[0].blocks[0].children[0],
                     document.site.reusableBlocks[0].root, document.site.globalBlocks[0].root] {
            #expect(node.propertyValue(.backgroundColor) == .packageColor(expected))
            #expect(node.propertyValue(.backgroundColor, at: .medium) == .packageColor(expectedFollowing))
        }
        let after = document.site
        undo.undo()
        #expect(document.site == before)
        undo.redo()
        #expect(document.site == after)
    }

    @Test
    func savedThemesExcludeProjectAndStandardColoursWithoutLosingProjectColours() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrytheme", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let session = ThemeEditorSession(document: document, undoManager: nil)
        let originalTheme = document.site.theme
        let originalID = document.site.themeSourceID
        let custom = try originalTheme.colourPalettes[0].duplicated()
        session.setColourPalettes(originalTheme.colourPalettes + [custom], session: nil)
        let id = UUID()

        // Both initial creation and replacement use the same bundle writer.
        for name in ["Created", "Updated"] {
            let saved = try ThemeBundleStore.write(
                theme: document.site.theme, name: name, preview: try ThemeBundleStore.preview(from: ThemeBundleStore.builtInThemes()[0].previewURL), id: id, to: root
            )
            let payload = try JSONDecoder().decode(Theme.self, from: Data(contentsOf:
                root.appending(path: "Contents/Resources/theme.json")))
            #expect(payload.colourPalettes == document.site.theme.fixedThemeColourPalettes)
            #expect(payload.colourPalettes.count == ThemeColorRole.allCases.count)
            let loaded = try ThemeBundleStore.load(from: root)
            #expect(loaded.theme == saved.theme)
            #expect(loaded.theme.colourPalettes.filter { $0.origin == .standard } == ColourPaletteDefaults.standard)
            #expect(!loaded.theme.colourPalettes.contains { $0.origin == .custom })

            editor.commitTheme(saved.theme, sourceID: id)
            #expect(document.site.theme.colourPalettes.first { $0.id == custom.id } == custom)
            #expect(document.site.projectThemeValues.colours == [custom])
            editor.selectTheme(originalTheme, sourceID: originalID)
            editor.selectTheme(loaded.theme, sourceID: id)
            #expect(document.site.theme.colourPalettes.first { $0.id == custom.id } == custom)
            let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
            #expect(restored.projectThemeValues.colours == [custom])
        }
    }

    @Test
    func switchingThemesPreservesEditableThemeEditsAndProjectThemeValues() throws {
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

        #expect(document.site.theme.colors.accent == systemTheme.colors.accent)
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

        #expect(firstID != BlockThemeValueSelection.manualCustom)
        #expect(firstID != BlockThemeValueSelection.manifestCustom)
        #expect(secondID != firstID)
        #expect(document.site.theme.typography.customFontSizes.contains { $0.id == firstID })
        #expect(BlockThemeValueSelection.isManualCustom(BlockThemeValueSelection.manualCustom))
    }

    @Test
    func designTokenReferencesRoundTripThroughProjectJSON() throws {
        var site = TestSiteFixtures.populatedSite()
        let blockID = try #require(site.pages.first?.blocks.first?.id)
        site.updateBlock(id: blockID) {
            $0.setProperty(.backgroundColor, value: .token(.accentColor))
            $0.setProperty(.padding, value: .token(.largeSpacing))
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let block = try #require(decoded.block(withID: blockID))

        #expect(block.propertyValue(.backgroundColor) == .token(.accentColor))
        #expect(block.propertyValue(.padding) == .token(.largeSpacing))
    }

    @Test
    func rendererResolvesBlockTokensThroughTheme() async throws {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        theme.colors.accent = "#123ABC"
        var container = BlockNode.make(.container)
        container.setProperty(.backgroundColor, value: .packageColor(.init(
            source: ThemeColorRole.accent.rawValue,
            customColor: "#000000",
            opacity: 1
        )))
        let page = Page(title: "Tokens", slug: "tokens", blocks: [container])

        let html = HTMLPageRenderer().render(page: page, theme: theme)

        #expect(html.contains("background-color: #123ABC"))
    }

    @Test @MainActor
    func paragraphColorAppliesPickerOpacityOnlyToCustomColors() async {
        await BlockPackageCatalog.shared.waitUntilLoaded()
        var paragraph = BlockNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: ThemeColorRole.accent.rawValue,
            customColor: "#000000",
            opacity: 0.5
        )))

        let page = Page(title: "Colour", slug: "colour", blocks: [paragraph])
        let themedHTML = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(themedHTML.contains("color: #5B5BD6"))
        #expect(!themedHTML.contains("color: rgb("))

        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: BlockThemeValueSelection.manualCustom,
            customColor: "#123456",
            opacity: 0.5
        )))
        let customPage = Page(title: "Colour", slug: "colour", blocks: [paragraph])
        let customHTML = HTMLPageRenderer().render(page: customPage, theme: .standard)
        #expect(customHTML.contains("color: \(BlockTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))"))
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
        editor.removeThemeSpacing(id: id, replacingWith: "md")
        #expect(document.site.theme.spacing.custom.isEmpty)
        undoManager.undo()
        #expect(document.site.theme.spacing.custom == [spacing])
    }

    @Test
    func deletingCustomThemeValueReplacesBlockReferencesAtomically() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let id = editor.addThemeFontSize()
        var block = BlockNode.make(.paragraph)
        block.setProperty(.fontSize, value: .packageFontSize(.init(
            source: id,
            customValue: "1rem",
            customLineHeight: "1.5"
        )))
        document.site.pages[0].blocks = [block]

        editor.removeThemeFontSize(id: id, replacingWith: "base")

        let updated = try #require(document.site.pages.first?.blocks.first)
        #expect(updated.propertyValue(.fontSize).stringValue == "base")
        #expect(!document.site.theme.typography.customFontSizes.contains { $0.id == id })
    }

    @Test
    func borderScalesPersistAndEmitCSSVariables() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeBorderWidth(id: "md", value: 3)
        editor.setThemeBorderRadius(id: "lg", value: 14)

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.theme.borderWidths.predefined.first { $0.id == "md" }?.value == 3)
        #expect(decoded.theme.borderRadii.predefined.first { $0.id == "lg" }?.value == 14)
        #expect(decoded.theme.borderCSSVariables.contains("--foundry-border-width-md:3px"))
        #expect(decoded.theme.borderCSSVariables.contains("--foundry-border-radius-lg:14px"))
    }

    @Test
    func legacyDefaultShadowLoadsAsSMAndStillResolves() throws {
        var theme = Theme.standard
        theme.shadows.predefined.removeAll { $0.id == "sm" }
        theme.shadows.predefined.append(.init(
            id: "default",
            title: "Default",
            layers: [.init(x: 0, y: 2, blur: 5, opacity: 0.2)]
        ))

        let data = try FoundryDocument.encoder.encode(theme)
        let decoded = try FoundryDocument.decoder.decode(Theme.self, from: data)

        #expect(!decoded.shadows.predefined.contains { $0.id == "default" })
        #expect(decoded.shadows.predefined.contains { $0.id == "sm" })
        #expect(decoded.shadowCSSVariable(for: "default") == decoded.shadowCSSVariable(for: "sm"))
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
    func shadowsCanBeEditedPersistedResolvedAndUndone() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let shadowID = editor.addThemeShadow()
        editor.setThemeShadowTitle(id: shadowID, value: "Floating Card")
        var layer = try #require(
            document.site.theme.shadows.custom
                .first(where: { $0.id == shadowID })?
                .layers.first
        )
        layer.x = 3
        layer.y = 12
        layer.blur = 28
        layer.color = "#123456"
        layer.opacity = 0.4
        editor.setThemeShadowLayer(shadowID: shadowID, layer: layer)

        let shadow = try #require(document.site.theme.shadows.custom.first(where: { $0.id == shadowID }))
        #expect(shadow.title == "Floating Card")
        #expect(shadow.cssValue.contains("3px 12px 28px"))
        #expect(document.site.theme.shadowCSSVariables.contains(shadow.cssVariable))
        #expect(BlockPackageThemeValueResolver.resolve(
            shadowID,
            from: .shadows,
            theme: document.site.theme
        ) == "var(\(shadow.cssVariable))")

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.theme.shadows.custom == [shadow])

        undoManager.undo()
        #expect(document.site.theme.shadows.custom.first?.layers.first != layer)
    }

    @Test
    func themesWithoutShadowTokensReceiveTailwindDefaults() throws {
        let encoded = try FoundryDocument.encoder.encode(Theme.standard)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "shadows")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try FoundryDocument.decoder.decode(Theme.self, from: legacyData)

        #expect(decoded.shadows == .standard)
        #expect(decoded.shadowChoices.contains { $0.value == "2xl" })
    }

    @Test
    func blockShadowValuesRoundTripAndResolveThemeOrCustomLayers() throws {
        let customLayer = ThemeShadowLayer(
            x: 3, y: 7, blur: 12, color: "#123456", opacity: 0.4
        )
        let custom = BlockPackageShadowValue(
            source: BlockThemeValueSelection.manualCustom,
            customLayers: [customLayer]
        )

        let data = try FoundryDocument.encoder.encode(BlockProperty.Value.packageShadow(custom))
        let decoded = try FoundryDocument.decoder.decode(BlockProperty.Value.self, from: data)

        #expect(decoded == .packageShadow(custom))
        #expect(BlockPackageShadowResolver.resolve(custom, theme: .standard) == customLayer.cssValue)

        let themed = BlockPackageShadowValue(source: "lg", customLayers: [customLayer])
        #expect(
            BlockPackageShadowResolver.resolve(themed, theme: .standard)
                == Theme.standard.shadowCSSVariable(for: "lg")
        )
    }

    @Test
    func themeScreensPersistContainerUnitsAndDriveResponsiveRanges() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeScreenMinimumWidth(.medium, value: 820)
        editor.setThemeScreenContainerUnit(.large, value: .viewportWidth)
        editor.setThemeScreenContainerWidth(.large, value: 92)

        #expect(ResponsiveBreakpoint.forViewportWidth(639, screens: document.site.theme.screens) == .mobile)
        #expect(ResponsiveBreakpoint.forViewportWidth(640, screens: document.site.theme.screens) == .small)
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
        #expect(screens.containerCSS.contains("1280px"))
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
        #expect(screens.enabledScreens.map(\.id).contains(.extraLarge))
        #expect(screens.enabledScreens.map(\.id).contains(.doubleExtraLarge))
        #expect(screens.activeScreen(for: 1_600).id == .doubleExtraLarge)
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

        let saved = try ThemeBundleStore.write(
            theme: theme,
            name: "Studio",
            preview: try ThemeBundleStore.preview(from: ThemeBundleStore.builtInThemes()[0].previewURL),
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
        #expect(systemTheme.theme == ThemeBundleStore.systemTheme)
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
    func bundledFontResourcesRenderForCanvasAndExport() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf"))
        let asset = ProjectAsset(filename: "Renamed.ttf", mediaType: "font/ttf", byteCount: data.count)
        let content = ProjectAssetContent(asset: asset, data: data)
        let assets = [asset.id: content]
        var theme = Theme.standard
        theme.typography.bodyFont.family = "Foundry Sans"
        theme.typography.bodyFont.source = .bundled(files: [asset.reference])

        let canvasCSS = theme.fontSourceCSS(assets: assets, destination: .canvas)
        let exportCSS = theme.fontSourceCSS(assets: assets, destination: .export)

        #expect(canvasCSS.contains("@font-face"))
        #expect(canvasCSS.contains("data:font/ttf;base64,"))
        #expect(canvasCSS.contains("font-weight:400;"))
        #expect(!canvasCSS.contains("100 900"))
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
