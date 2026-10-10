import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemeEditingTests {
    @Test
    func themeChangesPreserveProjectLayout() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        // Breakpoint choices belong to the project, not the selected appearance.
        var theme = Theme.standard
        theme.screens.update(.extraLarge) { $0.isEnabled = true }
        document.site.theme.screens = theme.screens
        let customID = UUID()
        editor.selectTheme(theme, sourceID: customID)
        #expect(document.site.theme.screens == theme.screens)
        editor.selectTheme(.standard, sourceID: UUID())
        #expect(document.site.theme.screens == theme.screens)
        editor.selectTheme(theme, sourceID: customID)
        #expect(document.site.theme.screens == theme.screens)
        #expect(document.site.theme.savedSettings.screens == Theme.standard.screens)
        let decoded = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(decoded.theme.screens == theme.screens)
        editor.resetTheme(.standard, sourceID: customID)
        #expect(document.site.theme.screens == theme.screens)
    }

    @Test
    func selectingBuiltInRestoresProjectEditsIncludingWhenAlreadyActive() throws {
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
        #expect(document.site.theme.savedSettings == modified.savedSettings)
        #expect(document.site.theme.colourPalettes.contains(custom))
        #expect(document.site.themeStates.contains { $0.sourceID == ThemeBundleStore.systemThemeID })
        document.site.theme.typography.headingFont.family = "Georgia"
        editor.selectTheme(modified, sourceID: ThemeBundleStore.systemThemeID)
        #expect(document.site.theme.savedSettings == modified.savedSettings)
    }

    @Test
    func themeEditingIsProjectLocalForEverySource() {
        let document = FoundryDocument()
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(session.canEditTheme)
        document.site.themeSourceID = UUID()
        #expect(session.canEditTheme)
    }

    @Test
    func builtInThemeBreakpointTogglesAreProjectLocalAndUndoable() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = ThemeEditorSession(document: document, undoManager: undo)
        let sourceID = document.site.themeSourceID
        let original = document.site.theme.screens
        #expect(session.canEditTheme)
        undo.beginUndoGrouping()
        session.editor.setThemeScreenEnabled(.medium, value: false)
        undo.endUndoGrouping()
        #expect(!document.site.theme.screens.screen(.medium).isEnabled)
        #expect(document.site.themeSourceID == sourceID)
        #expect(session.canEditTheme)
        let saved = try FoundryDocument.decoder.decode(Site.self, from: FoundryDocument.encoder.encode(document.site))
        #expect(!saved.theme.screens.screen(.medium).isEnabled)
        let fresh = FoundryDocument()
        #expect(fresh.site.theme.screens == original)
        undo.undo()
        #expect(document.site.theme.screens == original)
        undo.redo()
        #expect(!document.site.theme.screens.screen(.medium).isEnabled)
    }

    @Test
    func breakpointDimensionsDoNotModifySavedThemeSettings() throws {
        let builtIn = try #require(ThemeBundleStore.builtInThemes().first)
        let document = FoundryDocument()
        document.site.theme = builtIn.theme
        document.site.themeSourceID = builtIn.id
        let editor = ProjectEditor(document: document, undoManager: nil)
        editor.setThemeScreenEnabled(.extraLarge, value: false)
        #expect(document.site.theme.screens.screen(.extraLarge).isEnabled == false)
        #expect(builtIn.hasModifiedSettings(in: document.site.theme) == false)
        let savedProject = try FoundryDocument.decoder.decode(Site.self, from: FoundryDocument.encoder.encode(document.site))
        #expect(savedProject.theme.screens == document.site.theme.screens)
        #expect(try ThemeBundleStore.load(from: builtIn.bundleURL).theme.screens == builtIn.theme.screens)
        let custom = SavedTheme(metadata: builtIn.metadata, theme: builtIn.theme, bundleURL: builtIn.bundleURL, resources: builtIn.resources, isBuiltIn: false)
        #expect(custom.hasModifiedSettings(in: document.site.theme) == false)
        #expect(document.site.theme.savedSettings.screens == document.site.theme.screens)
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
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundryframework")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try ThemeBundleStore.create(name: "Before", preview: preview, to: destination)
        let saved = try ThemeBundleStore.load(from: destination)
        let themeURL = destination.appending(path: "Resources/theme.json")
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
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundryframework")
        defer { try? FileManager.default.removeItem(at: destination) }
        let created = try ThemeBundleStore.create(
            name: "Fresh Framework",
            preview: ThemeBundleStore.preview(from: template.previewURL),
            to: destination
        )
        #expect(created.id != template.id)
        #expect(created.metadata.name == "Fresh Framework")
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

        let index = try #require(project.colourPalettes.firstIndex { $0.id == "framework.accent" })
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
        #expect(original.filter { $0.origin == .standard }.count == 18)
        var values = original
        let index = try #require(values.firstIndex { $0.id == "framework.accent" })
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
        let value = custom.id
        var child = PartNode.make(.section)
        child.setProperty(.init(rawValue: "background.backgroundColor"), value: .choice(value))
        let following = value
        child.setResponsiveProperty(.init(rawValue: "background.backgroundColor"), value: .choice(following), at: .medium)
        var parent = PartNode.make(.section)
        parent.children = [child]
        document.site.pages[0].parts = [parent]
        document.site.globalPartLibrary = [.part(.init(name: "Global", root: child))]
        let before = document.site
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site == before)
        undo.beginUndoGrouping()
        session.deleteColour(custom.id, replacement: original.id)
        undo.endUndoGrouping()
        #expect(!session.colourIsInUse(custom.id))
        #expect(!document.site.theme.colourPalettes.contains { $0.id == custom.id })
        let expected = original.id
        let expectedFollowing = original.id
        for node in [document.site.pages[0].parts[0].children[0],
                     document.site.globalParts[0].root] {
            #expect(node.propertyValue(.init(rawValue: "background.backgroundColor")) == .choice(expected))
            #expect(node.propertyValue(.init(rawValue: "background.backgroundColor"), at: .medium) == .choice(expectedFollowing))
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
            .appending(path: "\(UUID().uuidString).foundryframework", directoryHint: .isDirectory)
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
            let payload = try JSONDecoder().decode(ThemePreset.self, from: Data(contentsOf:
                root.appending(path: "Resources/theme.json")))
            #expect(payload.colourPalettes == document.site.theme.fixedThemeColourPalettes)
            #expect(payload.colourPalettes.count == ThemePaletteColorRole.allCases.count)
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
        alternateTheme.bootstrapTokens.values["link-color"] = "#112233"
        let linkColour = BootstrapEditorToken("link-color")

        editor.setBootstrapToken(linkColour, value: "#AABBCC")
        editor.selectTheme(alternateTheme, sourceID: alternateID)

        #expect(document.site.theme.bootstrapTokens.values["link-color"] == "#112233")

        editor.setBootstrapToken(linkColour, value: "#445566")
        editor.selectTheme(systemTheme, sourceID: ThemeBundleStore.systemThemeID)

        // Edits belong to the theme they were made under and return with it.
        #expect(document.site.theme.bootstrapTokens.values["link-color"] == "#AABBCC")

        editor.selectTheme(alternateTheme, sourceID: alternateID)
        #expect(document.site.theme.bootstrapTokens.values["link-color"] == "#445566")
    }

    @Test
    func customFontSizeIDsCannotCollideWithManualControlSelection() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let firstID = editor.addThemeFontSize()
        let secondID = editor.addThemeFontSize()

        #expect(firstID != PartThemeValueSelection.manualCustom)
        #expect(firstID != PartThemeValueSelection.manifestCustom)
        #expect(secondID != firstID)
        #expect(document.site.theme.typography.customFontSizes.contains { $0.id == firstID })
        #expect(PartThemeValueSelection.isManualCustom(PartThemeValueSelection.manualCustom))
    }

    @Test
    func designTokenReferencesRoundTripThroughProjectJSON() throws {
        var site = TestSiteFixtures.populatedSite()
        let partID = try #require(site.pages.first?.parts.first?.id)
        let marginKey = PartProperty.Key(rawValue: "themeMargin")
        let margin = try #require(PartPackageThemeMarginControl.defaultValue(.string("7")))
        site.updatePart(id: partID) {
            $0.setProperty(.init(rawValue: "background.backgroundColor"), value: .token(.accentColor))
            $0.setProperty(marginKey, value: .themeMargin(margin))
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let part = try #require(decoded.part(withID: partID))

        #expect(part.propertyValue(.init(rawValue: "background.backgroundColor")) == .token(.accentColor))
        #expect(part.propertyValue(marginKey) == .themeMargin(margin))
    }

    @Test
    func themeChangesParticipateInUndoAndRedo() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let original = document.site.theme.colors.accent

        editor.setThemePaletteColor(.accentColor, value: "#112233")
        #expect(document.site.theme.colors.accent == "#112233")

        undoManager.undo()
        #expect(document.site.theme.colors.accent == original)

        undoManager.redo()
        #expect(document.site.theme.colors.accent == "#112233")
    }

    @Test
    func customDimensionValuesEmitCSSAndBakeOnDelete() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let widthID = editor.addThemeBorderWidth()
        editor.setThemeBorderWidthName(id: widthID, value: "Hairline Plus")
        editor.setThemeBorderWidthValue(id: widthID, value: 3)
        let width = try #require(document.site.theme.borderWidths.custom.first(where: { $0.id == widthID }))
        #expect(width.name == "Hairline Plus")
        #expect(document.site.theme.borderCSSVariables.contains("\(width.cssVariable(prefix: "border-width")):3"))
        #expect(BorderWidthPolicy.choices(in: document.site.theme).contains { $0.id == width.reference })

        let zID = editor.addThemeZIndexValue()
        editor.setThemeZIndexName(id: zID, value: "Mega Modal")
        editor.setThemeZIndexValue(id: zID, value: 1_700)
        let zIndex = try #require(document.site.theme.zIndexes.custom.first(where: { $0.id == zID }))
        #expect(document.site.theme.zIndexCSSVariables.contains("\(zIndex.cssVariable(prefix: "z-index")):1700"))
        let output = StaticSiteRenderer().render(site: document.site)
        #expect(output.files.filter { $0.path.hasSuffix(".css") }.allSatisfy {
            !$0.contents.contains(".fd-z-mega-modal")
        })

        var border = ThemeBorderWidthValue()
        border.setAll(.init(token: width.reference))
        var part = PartNode.make(.section)
        part.setProperty(.init(rawValue: "edge"), value: .themeBorderWidth(border))
        document.site.pages[0].parts = [part]

        editor.removeThemeBorderWidth(id: widthID)

        let updated = try #require(document.site.pages.first?.parts.first)
        guard case .themeBorderWidth(let baked) = updated.propertyValue(.init(rawValue: "edge")) else {
            Issue.record("Expected a border width value")
            return
        }
        for edge in ThemeBorderWidthValue.Edge.allCases {
            let value = baked.value(for: edge)
            #expect(value.isCustom)
            #expect(value.amount == 3)
            #expect(value.unit == "px")
        }
        #expect(document.site.theme.borderWidths.custom.isEmpty)
    }

    @Test
    func deletingCustomThemeValueReplacesPartReferencesAtomically() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let id = editor.addThemeFontSize()
        var part = PartNode.make(.paragraph)
        part.setProperty(.fontSize, value: .packageFontSize(.init(
            source: id,
            customValue: "1rem",
            customLineHeight: "1.5"
        )))
        document.site.pages[0].parts = [part]

        editor.removeThemeFontSize(id: id, replacingWith: "base")

        let updated = try #require(document.site.pages.first?.parts.first)
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
    func zIndexScalePersistsAndEmitsCSSVariablesAndResets() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setThemeZIndex(id: "modal", value: 1_800)

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.theme.zIndexes.predefined.first { $0.id == "modal" }?.value == 1_800)
        #expect(decoded.theme.zIndexCSSVariables.contains("--foundry-z-index-modal:1800"))

        editor.resetThemeZIndexes()
        #expect(document.site.theme.zIndexes == .standardZIndexes)
    }

    @Test
    func projectsSavedBeforeZIndexTokensUseTheStandardScale() throws {
        let encoded = try FoundryDocument.encoder.encode(Theme.standard)
        var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        object?["zIndexes"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object as Any)

        let decoded = try FoundryDocument.decoder.decode(Theme.self, from: legacyData)

        #expect(decoded.zIndexes == .standardZIndexes)
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
        #expect(PartPackageThemeValueResolver.resolve(
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
    func partShadowValuesRoundTripAndResolveThemeOrCustomLayers() throws {
        let customLayer = ThemeShadowLayer(
            x: 3, y: 7, blur: 12, color: "#123456", opacity: 0.4
        )
        let custom = PartPackageShadowValue(
            source: PartThemeValueSelection.manualCustom,
            customLayers: [customLayer]
        )

        let data = try FoundryDocument.encoder.encode(PartProperty.Value.packageShadow(custom))
        let decoded = try FoundryDocument.decoder.decode(PartProperty.Value.self, from: data)

        #expect(decoded == .packageShadow(custom))
        #expect(PartPackageShadowResolver.resolve(custom, theme: .standard) == customLayer.cssValue)

        let themed = PartPackageShadowValue(source: "lg", customLayers: [customLayer])
        #expect(
            PartPackageShadowResolver.resolve(themed, theme: .standard)
                == Theme.standard.shadowCSSVariable(for: "lg")
        )
    }

    @Test
    func themeScreensDriveResponsiveRanges() throws {
        // Breakpoint widths are Bootstrap's; only enabling a size is a theme choice.
        let document = FoundryDocument()
        #expect(ResponsiveBreakpoint.forViewportWidth(575, screens: document.site.theme.screens) == .mobile)
        #expect(ResponsiveBreakpoint.forViewportWidth(576, screens: document.site.theme.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(767, screens: document.site.theme.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(768, screens: document.site.theme.screens) == .medium)

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
        screens.update(.extraLarge) { $0.isEnabled = true }
        screens.update(.doubleExtraLarge) { $0.isEnabled = true }

        #expect(screens.enabledScreens.map(\.id).contains(.small) == false)
        #expect(screens.canvasWidth(for: screens.screen(.medium)) == 768)
        #expect(screens.activeScreen(for: 767).id == .mobile)
        #expect(screens.activeScreen(for: 768).id == .medium)
        #expect(screens.enabledScreens.map(\.id).contains(.extraLarge))
        #expect(screens.enabledScreens.map(\.id).contains(.doubleExtraLarge))
        #expect(screens.activeScreen(for: 1_600).id == .doubleExtraLarge)
    }

    @Test
    func userThemeBundleRoundTripsThemeAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundryframework", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        var theme = Theme.standard
        theme.colors.accent = "#123456"
        theme.screens.update(.medium) { $0.minimumWidth = 820 }
        theme.screens.update(.large) { $0.isEnabled = false }
        let fontData = Data("font-data".utf8)
        let fontAsset = ProjectAsset(
            filename: "Studio.woff2",
            mediaType: "font/woff2",
            byteCount: fontData.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: fontData)
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
        var expectedTheme = theme.savedSettings
        expectedTheme.colourPalettes += ColourPaletteDefaults.standard
        #expect(loaded.theme == expectedTheme)
        #expect(loaded.resources == [ProjectAssetContent(asset: fontAsset, data: fontData)])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Resources/theme.json").path))
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
    func customFontNamedForAThemeRoleOverridesThatRole() {
        var theme = Theme.standard
        let custom = ThemeCustomFont(
            name: " body ",
            font: .system(family: "Custom Body", weights: [400])
        )
        theme.typography.customFonts = [custom]

        #expect(theme.fontFamilyChoices.map(\.label) == [" body ", "Heading", "Monospaced"])
        #expect(theme.fontFamilyChoices.first?.value == ThemeFontRole.body.rawValue)
        #expect(theme.fontCSSVariable(for: ThemeFontRole.body.rawValue)
            == "var(--foundry-font-custom-\(custom.id.uuidString.lowercased()))")

        theme.typography.customFonts[0].name = "Editorial"
        #expect(theme.fontFamilyChoices.map(\.label) == ["Editorial", "Body", "Heading", "Monospaced"])
        #expect(theme.fontCSSVariable(for: ThemeFontRole.body.rawValue) == "var(--foundry-font-body)")
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
        let asset = ProjectAsset(
            filename: "Renamed.ttf",
            mediaType: "font/ttf",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data)
        )
        let content = ProjectAssetContent(asset: asset, data: data)
        let assets: ProjectAssetContents = [asset.id: content]
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
