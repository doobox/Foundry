import Foundation
import Testing
@testable import Foundry

@MainActor
struct FrameworkEditingTests {
    @Test
    func frameworkChangesPreserveProjectBreakpoints() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        var screens = document.site.framework.screens
        screens.update(.medium) { $0.minimumWidth = 850; $0.container = .init(value: 90, unit: .percent) }
        screens.update(.large) { $0.isEnabled = false }
        document.site.framework.screens = screens
        let customID = UUID()
        editor.selectFramework(.standard, sourceID: customID)
        #expect(document.site.framework.screens == screens)
        editor.selectFramework(FrameworkBundleStore.systemFramework, sourceID: FrameworkBundleStore.systemFrameworkID)
        #expect(document.site.framework.screens == screens)
        editor.selectFramework(.standard, sourceID: customID)
        #expect(document.site.framework.screens == screens)
        editor.resetFramework(.standard, sourceID: customID)
        #expect(document.site.framework.screens == screens)
        editor.commitFramework(.standard, sourceID: customID)
        #expect(document.site.framework.screens == screens)
        editor.didDeleteFramework(sourceID: customID)
        #expect(document.site.framework.screens == screens)
        #expect(document.site.framework.savedSettings.screens == .standard)
        let decoded = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(decoded.framework.screens == screens)
    }

    @Test
    func selectingBuiltInDiscardsEditedSnapshotIncludingWhenAlreadyActive() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let defaults = FrameworkBundleStore.systemFramework
        var modified = defaults
        modified.typography.headingFont.family = "Georgia"
        let custom = try defaults.colourPalettes[0].duplicated()
        modified.colourPalettes.append(custom)
        document.site.framework = modified
        editor.selectFramework(defaults, sourceID: UUID())
        editor.selectFramework(defaults, sourceID: FrameworkBundleStore.systemFrameworkID)
        #expect(document.site.framework.savedSettings == defaults.savedSettings)
        #expect(document.site.framework.colourPalettes.contains(custom))
        #expect(!document.site.frameworkStates.contains { $0.sourceID == FrameworkBundleStore.systemFrameworkID })
        document.site.framework.typography.headingFont.family = "Georgia"
        editor.selectFramework(modified, sourceID: FrameworkBundleStore.systemFrameworkID)
        #expect(document.site.framework.savedSettings == defaults.savedSettings)
    }

    @Test
    func frameworkEditingPermissionFollowsBuiltInIdentity() {
        let document = FoundryDocument()
        let session = FrameworkEditorSession(document: document, undoManager: nil)
        #expect(!session.canEditFramework)
        document.site.frameworkSourceID = UUID()
        #expect(session.canEditFramework)
    }

    @Test
    func builtInFrameworkBreakpointTogglesAreProjectLocalAndUndoable() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = FrameworkEditorSession(document: document, undoManager: undo)
        let sourceID = document.site.frameworkSourceID
        let original = document.site.framework.screens
        #expect(!session.canEditFramework)
        undo.beginUndoGrouping()
        session.editor.setFrameworkScreenEnabled(.medium, value: false)
        undo.endUndoGrouping()
        #expect(!document.site.framework.screens.screen(.medium).isEnabled)
        #expect(document.site.frameworkSourceID == sourceID)
        #expect(!session.canEditFramework)
        let saved = try FoundryDocument.decoder.decode(Site.self, from: FoundryDocument.encoder.encode(document.site))
        #expect(!saved.framework.screens.screen(.medium).isEnabled)
        let fresh = FoundryDocument()
        #expect(fresh.site.framework.screens == original)
        undo.undo()
        #expect(document.site.framework.screens == original)
        undo.redo()
        #expect(!document.site.framework.screens.screen(.medium).isEnabled)
    }

    @Test
    func breakpointDimensionsAreProjectLocalForEveryFramework() throws {
        let builtIn = try #require(FrameworkBundleStore.builtInFrameworks().first)
        let document = FoundryDocument()
        document.site.framework = builtIn.framework
        document.site.frameworkSourceID = builtIn.id
        let editor = ProjectEditor(document: document, undoManager: nil)
        editor.setFrameworkScreenEnabled(.extraLarge, value: false)
        editor.setFrameworkScreenMinimumWidth(.medium, value: 820)
        editor.setFrameworkScreenContainerUnit(.mobile, value: .percent)
        editor.setFrameworkScreenContainerWidth(.mobile, value: 92)
        #expect(document.site.framework.screens.screen(.medium).minimumWidth == 820)
        #expect(document.site.framework.screens.screen(.mobile).container.value == 92)
        #expect(!builtIn.hasModifiedSettings(in: document.site.framework))
        let savedProject = try FoundryDocument.decoder.decode(Site.self, from: FoundryDocument.encoder.encode(document.site))
        #expect(savedProject.framework.screens == document.site.framework.screens)
        #expect(try FrameworkBundleStore.load(from: builtIn.bundleURL).framework.screens == builtIn.framework.screens)
        let custom = SavedFramework(metadata: builtIn.metadata, framework: builtIn.framework, bundleURL: builtIn.bundleURL, resources: builtIn.resources, isBuiltIn: false)
        #expect(!custom.hasModifiedSettings(in: document.site.framework))
        #expect(document.site.framework.savedSettings.screens == .standard)
    }

    @Test
    func colourCopiesHaveUniqueIndependentNames() {
        let model = FrameworkColourPreviewModel()
        let palette = model.palettes.first { $0.name == "Accent" }!
        model.duplicate(palette)
        model.duplicate(palette)
        #expect(model.palettes[0].name == "Accent Copy 2")
        #expect(model.palettes[1].name == "Accent Copy")
        #expect(model.storedPalettes.resolvedPalette(id: palette.id)?.origin == .framework)
    }

    @Test
    func editingFrameworkArtworkPreservesSettingsAndIdentity() throws {
        let system = try #require(FrameworkBundleStore.builtInFrameworks().first { $0.id == FrameworkBundleStore.systemFrameworkID })
        let preview = try FrameworkBundleStore.preview(from: system.previewURL)
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundryframework")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try FrameworkBundleStore.create(name: "Before", preview: preview, to: destination)
        let saved = try FrameworkBundleStore.load(from: destination)
        let frameworkURL = destination.appending(path: "Contents/Resources/framework.json")
        let originalData = try Data(contentsOf: frameworkURL)
        let edited = try FrameworkBundleStore.editArtwork(saved, name: "After", preview: preview)
        #expect(edited.id == saved.id)
        #expect(edited.metadata.createdAt == saved.metadata.createdAt)
        #expect(edited.metadata.name == "After")
        #expect(edited.framework == saved.framework)
        #expect(try Data(contentsOf: frameworkURL) == originalData)
        #expect(try FrameworkBundleStore.editArtwork(system, name: "Not Allowed", preview: preview) == system)
    }

    @Test
    func deletingActiveFrameworkUsesFreshSystemDefaultsAndKeepsCustomColours() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let defaults = FrameworkBundleStore.systemFramework
        var editedSystem = defaults
        editedSystem.typography.headingFont.family = "Georgia"
        editor.commitFramework(editedSystem, sourceID: FrameworkBundleStore.systemFrameworkID)
        let otherID = UUID()
        editor.selectFramework(editedSystem, sourceID: otherID)
        let session = FrameworkEditorSession(document: document, undoManager: nil)
        let custom = try defaults.colourPalettes[0].duplicated()
        session.setColourPalettes(document.site.framework.colourPalettes + [custom], session: nil)
        editor.didDeleteFramework(sourceID: otherID)
        #expect(document.site.frameworkSourceID == FrameworkBundleStore.systemFrameworkID)
        #expect(document.site.framework.savedSettings == defaults.savedSettings)
        #expect(document.site.framework.colourPalettes.contains(custom))
        #expect(!document.site.frameworkStates.contains { $0.sourceID == otherID || $0.sourceID == FrameworkBundleStore.systemFrameworkID })
        let before = document.site.framework
        editor.didDeleteFramework(sourceID: UUID())
        #expect(document.site.framework == before)
    }

    @Test
    func newFrameworkStartsFromBundledSystemUI() throws {
        let template = try #require(FrameworkBundleStore.builtInFrameworks().first { $0.id == FrameworkBundleStore.systemFrameworkID })
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).foundryframework")
        defer { try? FileManager.default.removeItem(at: destination) }
        let created = try FrameworkBundleStore.create(
            name: "Fresh Framework",
            preview: FrameworkBundleStore.preview(from: template.previewURL),
            to: destination
        )
        #expect(created.id != template.id)
        #expect(created.metadata.name == "Fresh Framework")
        #expect(created.framework.savedSettings == template.framework.savedSettings)
        #expect(try FrameworkBundleStore.load(from: destination).framework.savedSettings == template.framework.savedSettings)
    }

    @Test
    func addingCustomColourThroughEditorDoesNotModifySystemFramework() throws {
        let document = FoundryDocument()
        let session = FrameworkEditorSession(document: document, undoManager: nil)
        let saved = FrameworkBundleStore.systemFramework.savedSettings
        #expect(document.site.framework.savedSettings == saved)
        let model = FrameworkColourPreviewModel(storedPalettes: document.site.framework.colourPalettes)
        model.onChange = { palettes, editSession in
            session.setColourPalettes(palettes, session: editSession)
        }
        model.add()
        #expect(document.site.framework.colourPalettes.contains { $0.origin == .custom })
        #expect(document.site.framework.savedSettings == saved)
    }

    @Test
    func modifiedStatusComparesOnlySavedFrameworkSettings() throws {
        let original = FrameworkBundleStore.systemFramework
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
        let session = FrameworkEditorSession(document: document, undoManager: undo)
        let original = document.site.framework.colourPalettes
        #expect(!original.contains { $0.origin == .custom })
        #expect(original.filter { $0.origin == .standard }.count == 24)
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
        #expect(document.site.framework.colors.accent == "#123456")
        values[index].name = "Renamed Accent"
        session.setColourPalettes(values, session: editID)
        #expect(document.mutationEvent.impact == .framework)
        let saved = try JSONEncoder().encode(document.site)
        let reopened = try JSONDecoder().decode(Site.self, from: saved)
        #expect(reopened.framework.colourPalettes == values)
        #expect(reopened.framework.colors.accent == "#123456")
        undo.undo()
        #expect(document.site.framework.colourPalettes == original)
        #expect(!undo.canUndo)
        undo.redo()
        #expect(document.site.framework.colourPalettes == values)
    }

    @Test
    func customPalettesSurviveFrameworkSwitchAndDeletion() throws {
        let document = FoundryDocument()
        let session = FrameworkEditorSession(document: document, undoManager: UndoManager())
        let originalFramework = document.site.framework
        let originalID = document.site.frameworkSourceID
        let copy = try originalFramework.colourPalettes[0].duplicated()
        session.setColourPalettes(originalFramework.colourPalettes + [copy], session: nil)
        session.editor.selectFramework(originalFramework, sourceID: UUID())
        #expect(document.site.framework.colourPalettes.contains { $0.id == copy.id })
        session.setColourPalettes(document.site.framework.colourPalettes.filter { $0.id != copy.id }, session: nil)
        session.editor.selectFramework(originalFramework, sourceID: originalID)
        #expect(!document.site.framework.colourPalettes.contains { $0.id == copy.id })
    }

    @Test
    func deletingUsedColourReplacesAllReferencesAndUndoesAtomically() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = FrameworkEditorSession(document: document, undoManager: undo)
        let original = try #require(document.site.framework.colourPalettes.first)
        let custom = try original.duplicated()
        document.site.framework.colourPalettes.insert(custom, at: 0)
        let value = PartPackageColorValue(source: custom.id, customColor: "#000000",
                                              opacity: 1, shade: .eight)
        var child = PartNode.make(.container)
        child.setProperty(.backgroundColor, value: .packageColor(value))
        var following = value
        following.shade = .one
        child.setResponsiveProperty(.backgroundColor, value: .packageColor(following), at: .medium)
        var parent = PartNode.make(.container)
        parent.children = [child]
        document.site.pages[0].parts = [parent]
        document.site.reusableParts = [.init(name: "Reusable", root: child)]
        document.site.globalParts = [.init(name: "Global", root: child)]
        let before = document.site
        #expect(session.colourIsInUse(custom.id))
        session.deleteColour(custom.id, replacement: nil)
        #expect(document.site == before)
        undo.beginUndoGrouping()
        session.deleteColour(custom.id, replacement: original.id)
        undo.endUndoGrouping()
        #expect(!session.colourIsInUse(custom.id))
        #expect(!document.site.framework.colourPalettes.contains { $0.id == custom.id })
        var expected = value
        expected.source = original.id
        var expectedFollowing = following
        expectedFollowing.source = original.id
        for node in [document.site.pages[0].parts[0].children[0],
                     document.site.reusableParts[0].root, document.site.globalParts[0].root] {
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
    func savedFrameworksExcludeProjectAndStandardColoursWithoutLosingProjectColours() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundryframework", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let session = FrameworkEditorSession(document: document, undoManager: nil)
        let originalFramework = document.site.framework
        let originalID = document.site.frameworkSourceID
        let custom = try originalFramework.colourPalettes[0].duplicated()
        session.setColourPalettes(originalFramework.colourPalettes + [custom], session: nil)
        let id = UUID()

        // Both initial creation and replacement use the same bundle writer.
        for name in ["Created", "Updated"] {
            let saved = try FrameworkBundleStore.write(
                framework: document.site.framework, name: name, preview: try FrameworkBundleStore.preview(from: FrameworkBundleStore.builtInFrameworks()[0].previewURL), id: id, to: root
            )
            let payload = try JSONDecoder().decode(Framework.self, from: Data(contentsOf:
                root.appending(path: "Contents/Resources/framework.json")))
            #expect(payload.colourPalettes == document.site.framework.fixedFrameworkColourPalettes)
            #expect(payload.colourPalettes.count == FrameworkColorRole.allCases.count)
            let loaded = try FrameworkBundleStore.load(from: root)
            #expect(loaded.framework == saved.framework)
            #expect(loaded.framework.colourPalettes.filter { $0.origin == .standard } == ColourPaletteDefaults.standard)
            #expect(!loaded.framework.colourPalettes.contains { $0.origin == .custom })

            editor.commitFramework(saved.framework, sourceID: id)
            #expect(document.site.framework.colourPalettes.first { $0.id == custom.id } == custom)
            #expect(document.site.projectFrameworkValues.colours == [custom])
            editor.selectFramework(originalFramework, sourceID: originalID)
            editor.selectFramework(loaded.framework, sourceID: id)
            #expect(document.site.framework.colourPalettes.first { $0.id == custom.id } == custom)
            let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
            #expect(restored.projectFrameworkValues.colours == [custom])
        }
    }

    @Test
    func switchingFrameworksPreservesEditableFrameworkEditsAndProjectFrameworkValues() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let systemFramework = document.site.framework
        let alternateID = UUID()
        var alternateFramework = systemFramework
        alternateFramework.colors.accent = "#112233"

        let customSpacingID = editor.addFrameworkSpacing()
        editor.setFrameworkColor(.accentColor, value: "#AABBCC")
        editor.selectFramework(alternateFramework, sourceID: alternateID)

        #expect(document.site.framework.colors.accent == "#112233")
        #expect(document.site.framework.spacing.custom.contains { $0.id == customSpacingID })

        editor.setFrameworkColor(.accentColor, value: "#445566")
        editor.selectFramework(systemFramework, sourceID: FrameworkBundleStore.systemFrameworkID)

        #expect(document.site.framework.colors.accent == systemFramework.colors.accent)
        #expect(document.site.framework.spacing.custom.contains { $0.id == customSpacingID })

        editor.selectFramework(alternateFramework, sourceID: alternateID)
        #expect(document.site.framework.colors.accent == "#445566")
        #expect(document.site.framework.spacing.custom.contains { $0.id == customSpacingID })
    }

    @Test
    func customFontSizeIDsCannotCollideWithManualControlSelection() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        let firstID = editor.addFrameworkFontSize()
        let secondID = editor.addFrameworkFontSize()

        #expect(firstID != PartFrameworkValueSelection.manualCustom)
        #expect(firstID != PartFrameworkValueSelection.manifestCustom)
        #expect(secondID != firstID)
        #expect(document.site.framework.typography.customFontSizes.contains { $0.id == firstID })
        #expect(PartFrameworkValueSelection.isManualCustom(PartFrameworkValueSelection.manualCustom))
    }

    @Test
    func designTokenReferencesRoundTripThroughProjectJSON() throws {
        var site = TestSiteFixtures.populatedSite()
        let partID = try #require(site.pages.first?.parts.first?.id)
        let marginKey = PartProperty.Key(rawValue: "frameworkMargin")
        let margin = try #require(PartPackageFrameworkMarginControl.defaultValue(.string("lg")))
        site.updatePart(id: partID) {
            $0.setProperty(.backgroundColor, value: .token(.accentColor))
            $0.setProperty(marginKey, value: .frameworkMargin(margin))
        }

        let data = try FoundryDocument.encoder.encode(site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        let part = try #require(decoded.part(withID: partID))

        #expect(part.propertyValue(.backgroundColor) == .token(.accentColor))
        #expect(part.propertyValue(marginKey) == .frameworkMargin(margin))
    }

    @Test
    func rendererResolvesPartTokensThroughFramework() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var framework = Framework.standard
        framework.colors.accent = "#123ABC"
        var container = PartNode.make(.container)
        container.setProperty(.init(rawValue: "backgroundMode"), value: .choice("static"))
        container.setProperty(.backgroundColor, value: .packageColor(.init(
            source: FrameworkColorRole.accent.rawValue,
            customColor: "#000000",
            opacity: 1
        )))
        let page = Page(title: "Tokens", slug: "tokens", parts: [container])

        let html = HTMLPageRenderer().render(page: page, framework: framework)

        #expect(html.contains("background-color: #123ABC"))
    }

    @Test @MainActor
    func paragraphColorAppliesPickerOpacityOnlyToCustomColors() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var paragraph = PartNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: FrameworkColorRole.accent.rawValue,
            customColor: "#000000",
            opacity: 0.5
        )))

        let page = Page(title: "Colour", slug: "colour", parts: [paragraph])
        let frameworkdHTML = HTMLPageRenderer().render(page: page, framework: .standard)

        #expect(frameworkdHTML.contains("color: #5B5BD6"))
        #expect(!frameworkdHTML.contains("color: rgb("))

        paragraph.setProperty(.init(rawValue: "textColor"), value: .packageColor(.init(
            source: PartFrameworkValueSelection.manualCustom,
            customColor: "#123456",
            opacity: 0.5
        )))
        let customPage = Page(title: "Colour", slug: "colour", parts: [paragraph])
        let customHTML = HTMLPageRenderer().render(page: customPage, framework: .standard)
        #expect(customHTML.contains("color: \(PartTemplateRenderer.colorWithAlpha("#123456", alpha: 0.5))"))
    }

    @Test
    func frameworkChangesParticipateInUndoAndRedo() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let original = document.site.framework.colors.accent

        editor.setFrameworkColor(.accentColor, value: "#112233")
        #expect(document.site.framework.colors.accent == "#112233")

        undoManager.undo()
        #expect(document.site.framework.colors.accent == original)

        undoManager.redo()
        #expect(document.site.framework.colors.accent == "#112233")
    }

    @Test
    func customSpacingsCanBeAddedEditedPersistedAndRemoved() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        let id = editor.addFrameworkSpacing()
        editor.setFrameworkSpacingName(id: id, value: "Hero Gap")
        editor.setFrameworkSpacingValue(id: id, value: 18)

        let spacing = try #require(document.site.framework.spacing.custom.first(where: { $0.id == id }))
        #expect(spacing.name == "Hero Gap")
        #expect(spacing.value == 18)
        #expect(document.site.framework.spacingCSSVariables.contains("\(spacing.cssVariable):calc(var(--foundry-spacing-base) * 18.0)"))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.framework.spacing.custom == [spacing])

        undoManager.removeAllActions()
        editor.removeFrameworkSpacing(id: id, replacingWith: "md")
        #expect(document.site.framework.spacing.custom.isEmpty)
        undoManager.undo()
        #expect(document.site.framework.spacing.custom == [spacing])
    }

    @Test
    func deletingCustomFrameworkValueReplacesPartReferencesAtomically() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let id = editor.addFrameworkFontSize()
        var part = PartNode.make(.paragraph)
        part.setProperty(.fontSize, value: .packageFontSize(.init(
            source: id,
            customValue: "1rem",
            customLineHeight: "1.5"
        )))
        document.site.pages[0].parts = [part]

        editor.removeFrameworkFontSize(id: id, replacingWith: "base")

        let updated = try #require(document.site.pages.first?.parts.first)
        #expect(updated.propertyValue(.fontSize).stringValue == "base")
        #expect(!document.site.framework.typography.customFontSizes.contains { $0.id == id })
    }

    @Test
    func borderScalesPersistAndEmitCSSVariables() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setFrameworkBorderWidth(id: "md", value: 3)
        editor.setFrameworkBorderRadius(id: "lg", value: 14)

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.framework.borderWidths.predefined.first { $0.id == "md" }?.value == 3)
        #expect(decoded.framework.borderRadii.predefined.first { $0.id == "lg" }?.value == 14)
        #expect(decoded.framework.borderCSSVariables.contains("--foundry-border-width-md:3px"))
        #expect(decoded.framework.borderCSSVariables.contains("--foundry-border-radius-lg:14px"))
    }

    @Test
    func zIndexScalePersistsAndEmitsCSSVariablesAndResets() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setFrameworkZIndex(id: "modal", value: 1_800)

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.framework.zIndexes.predefined.first { $0.id == "modal" }?.value == 1_800)
        #expect(decoded.framework.zIndexCSSVariables.contains("--foundry-z-index-modal:1800"))

        editor.resetFrameworkZIndexes()
        #expect(document.site.framework.zIndexes == .standardZIndexes)
    }

    @Test
    func projectsSavedBeforeZIndexTokensUseTheStandardScale() throws {
        let encoded = try FoundryDocument.encoder.encode(Framework.standard)
        var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        object?["zIndexes"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object as Any)

        let decoded = try FoundryDocument.decoder.decode(Framework.self, from: legacyData)

        #expect(decoded.zIndexes == .standardZIndexes)
    }

    @Test
    func legacyDefaultShadowLoadsAsSMAndStillResolves() throws {
        var framework = Framework.standard
        framework.shadows.predefined.removeAll { $0.id == "sm" }
        framework.shadows.predefined.append(.init(
            id: "default",
            title: "Default",
            layers: [.init(x: 0, y: 2, blur: 5, opacity: 0.2)]
        ))

        let data = try FoundryDocument.encoder.encode(framework)
        let decoded = try FoundryDocument.decoder.decode(Framework.self, from: data)

        #expect(!decoded.shadows.predefined.contains { $0.id == "default" })
        #expect(decoded.shadows.predefined.contains { $0.id == "sm" })
        #expect(decoded.shadowCSSVariable(for: "default") == decoded.shadowCSSVariable(for: "sm"))
    }

    @Test
    func predefinedSpacingScaleCanResetWithoutRemovingCustomSpacings() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        let customID = editor.addFrameworkSpacing()
        editor.setFrameworkSpacing(.extraSmallSpacing, value: 6)
        editor.setFrameworkSpacing(.mediumSpacing, value: 23.5)

        editor.resetFrameworkSpacingScale()

        #expect(document.site.framework.spacing.usesStandardPredefinedScale)
        #expect(document.site.framework.spacing.custom.map(\.id) == [customID])
    }

    @Test
    func shadowsCanBeEditedPersistedResolvedAndUndone() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let shadowID = editor.addFrameworkShadow()
        editor.setFrameworkShadowTitle(id: shadowID, value: "Floating Card")
        var layer = try #require(
            document.site.framework.shadows.custom
                .first(where: { $0.id == shadowID })?
                .layers.first
        )
        layer.x = 3
        layer.y = 12
        layer.blur = 28
        layer.color = "#123456"
        layer.opacity = 0.4
        editor.setFrameworkShadowLayer(shadowID: shadowID, layer: layer)

        let shadow = try #require(document.site.framework.shadows.custom.first(where: { $0.id == shadowID }))
        #expect(shadow.title == "Floating Card")
        #expect(shadow.cssValue.contains("3px 12px 28px"))
        #expect(document.site.framework.shadowCSSVariables.contains(shadow.cssVariable))
        #expect(PartPackageFrameworkValueResolver.resolve(
            shadowID,
            from: .shadows,
            framework: document.site.framework
        ) == "var(\(shadow.cssVariable))")

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.framework.shadows.custom == [shadow])

        undoManager.undo()
        #expect(document.site.framework.shadows.custom.first?.layers.first != layer)
    }

    @Test
    func frameworksWithoutShadowTokensReceiveTailwindDefaults() throws {
        let encoded = try FoundryDocument.encoder.encode(Framework.standard)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "shadows")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try FoundryDocument.decoder.decode(Framework.self, from: legacyData)

        #expect(decoded.shadows == .standard)
        #expect(decoded.shadowChoices.contains { $0.value == "2xl" })
    }

    @Test
    func partShadowValuesRoundTripAndResolveFrameworkOrCustomLayers() throws {
        let customLayer = FrameworkShadowLayer(
            x: 3, y: 7, blur: 12, color: "#123456", opacity: 0.4
        )
        let custom = PartPackageShadowValue(
            source: PartFrameworkValueSelection.manualCustom,
            customLayers: [customLayer]
        )

        let data = try FoundryDocument.encoder.encode(PartProperty.Value.packageShadow(custom))
        let decoded = try FoundryDocument.decoder.decode(PartProperty.Value.self, from: data)

        #expect(decoded == .packageShadow(custom))
        #expect(PartPackageShadowResolver.resolve(custom, framework: .standard) == customLayer.cssValue)

        let frameworkd = PartPackageShadowValue(source: "lg", customLayers: [customLayer])
        #expect(
            PartPackageShadowResolver.resolve(frameworkd, framework: .standard)
                == Framework.standard.shadowCSSVariable(for: "lg")
        )
    }

    @Test
    func frameworkScreensPersistContainerUnitsAndDriveResponsiveRanges() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setFrameworkScreenMinimumWidth(.medium, value: 820)
        editor.setFrameworkScreenContainerUnit(.large, value: .viewportWidth)
        editor.setFrameworkScreenContainerWidth(.large, value: 92)

        #expect(ResponsiveBreakpoint.forViewportWidth(639, screens: document.site.framework.screens) == .mobile)
        #expect(ResponsiveBreakpoint.forViewportWidth(640, screens: document.site.framework.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(819, screens: document.site.framework.screens) == .small)
        #expect(ResponsiveBreakpoint.forViewportWidth(820, screens: document.site.framework.screens) == .medium)
        #expect(document.site.framework.screens.containerCSS.contains("92vw"))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(decoded.framework.screens == document.site.framework.screens)
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
    func canvasScreenPresetsFollowEnabledFrameworkBreakpoints() {
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
    func userFrameworkBundleRoundTripsFrameworkAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundryframework", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        var framework = Framework.standard
        framework.colors.accent = "#123456"
        framework.screens.update(.medium) { $0.minimumWidth = 820 }
        framework.screens.update(.large) { $0.isEnabled = false }
        let fontData = Data("font-data".utf8)
        let fontAsset = ProjectAsset(
            filename: "Studio.woff2",
            mediaType: "font/woff2",
            byteCount: fontData.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: fontData)
        )
        framework.typography.bodyFont.source = .bundled(files: [fontAsset.reference])

        let saved = try FrameworkBundleStore.write(
            framework: framework,
            name: "Studio",
            preview: try FrameworkBundleStore.preview(from: FrameworkBundleStore.builtInFrameworks()[0].previewURL),
            assetContents: [fontAsset.id: ProjectAssetContent(asset: fontAsset, data: fontData)],
            to: root
        )
        let loaded = try FrameworkBundleStore.load(from: root)

        #expect(loaded.id == saved.id)
        #expect(loaded.metadata.name == "Studio")
        var expectedFramework = framework
        expectedFramework.screens = .standard
        #expect(loaded.framework == expectedFramework)
        #expect(loaded.resources == [ProjectAssetContent(asset: fontAsset, data: fontData)])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Contents/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Contents/Resources/framework.json").path))
        #expect(FileManager.default.fileExists(atPath: loaded.previewURL.path))
    }

    @Test
    func systemUIFrameworkLoadsFromTheBuiltInFrameworkBundle() throws {
        let systemFramework = try #require(
            FrameworkBundleStore.builtInFrameworks().first(where: { $0.id == FrameworkBundleStore.systemFrameworkID })
        )

        #expect(systemFramework.isBuiltIn)
        #expect(systemFramework.metadata.name == "System UI")
        #expect(systemFramework.framework == FrameworkBundleStore.systemFramework)
    }

    @Test
    func fontNamesUpdateFamilyFallbacksAndSource() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setFrameworkFontNames("Inter, system-ui, sans-serif", reference: .role(.body))

        let font = document.site.framework.typography.bodyFont
        #expect(font.family == "Inter")
        #expect(font.fallbacks == ["system-ui", "sans-serif"])
        #expect(font.source == .system)
    }

    @Test
    func googleFontSelectionCreatesAWorkingStylesheetSource() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())

        editor.setFrameworkGoogleFont("Libre Franklin", reference: .role(.heading))

        let font = document.site.framework.typography.headingFont
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
        site.framework.typography.bodyFont.family = "Libre Franklin"
        site.framework.typography.bodyFont.fallbacks = []
        site.framework.typography.bodyFont.source = .remote(stylesheetURL: try #require(
            FrameworkFontDefinition.googleStylesheetURL(for: "Libre Franklin")
        ))
        site.framework.typography.bodyFont.systemFontNames = ["Avenir Next", "system-ui", "sans-serif"]
        let document = FoundryDocument(site: site)
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)

        editor.restoreFrameworkFontNames(reference: .role(.body))

        let restored = document.site.framework.typography.bodyFont
        #expect(restored.family == "Avenir Next")
        #expect(restored.fallbacks == ["system-ui", "sans-serif"])
        #expect(restored.source == .system)

        undoManager.undo()
        #expect(document.site.framework.typography.bodyFont.family == "Libre Franklin")
    }

    @Test
    func fontNameMemoryRoundTripsWithTheProject() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: UndoManager())
        editor.setFrameworkFontNames("Charter, serif", reference: .role(.heading))
        editor.setFrameworkGoogleFont("ABeeZee", reference: .role(.heading))

        let data = try FoundryDocument.encoder.encode(document.site)
        let decoded = try FoundryDocument.decoder.decode(Site.self, from: data)

        #expect(decoded.framework.typography.headingFont.systemFontNames == ["Charter", "serif"])
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
        var framework = Framework.standard
        framework.typography.bodyFont.family = "Foundry Sans"
        framework.typography.bodyFont.source = .bundled(files: [asset.reference])

        let canvasCSS = framework.fontSourceCSS(assets: assets, destination: .canvas)
        let exportCSS = framework.fontSourceCSS(assets: assets, destination: .export)

        #expect(canvasCSS.contains("@font-face"))
        #expect(canvasCSS.contains("data:font/ttf;base64,"))
        #expect(canvasCSS.contains("font-weight:400;"))
        #expect(!canvasCSS.contains("100 900"))
        #expect(exportCSS.contains("url('\(asset.storageFilename)')"))
    }

    @Test
    func duplicateRemoteFontSourcesProduceOneStylesheetImport() throws {
        var framework = Framework.standard
        let url = try #require(FrameworkFontDefinition.googleStylesheetURL(for: "Inter"))
        framework.typography.bodyFont.source = .remote(stylesheetURL: url)
        framework.typography.headingFont.source = .remote(stylesheetURL: url)

        let css = framework.fontSourceCSS(assets: [:], destination: .export)

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
    func frameworkWindowRegistryPreservesTheLiveDocumentAndUndoManager() throws {
        let id = UUID()
        let document = FoundryDocument()
        let undoManager = UndoManager()

        FrameworkWindowRegistry.shared.register(
            id: id,
            document: document,
            undoManager: undoManager
        )
        let context = try #require(FrameworkWindowRegistry.shared.context(for: id))

        #expect(context.session.document === document)
        #expect(context.session.editor.undoManager === undoManager)

        FrameworkWindowRegistry.shared.remove(id: id)
        #expect(FrameworkWindowRegistry.shared.context(for: id) == nil)
    }

    @Test
    func browsingGoogleFontsDoesNotMutateTheDocumentUntilCommitted() {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let session = FrameworkEditorSession(document: document, undoManager: undoManager)
        let original = document.site.framework.typography.bodyFont

        session.previewGoogleFont("Inter", for: .role(.body))
        session.previewGoogleFont("Libre Franklin", for: .role(.body))

        #expect(document.site.framework.typography.bodyFont == original)
        #expect(session.font(for: .role(.body)).family == "Libre Franklin")
        #expect(!undoManager.canUndo)

        session.commitFontPreview()

        #expect(document.site.framework.typography.bodyFont.family == "Libre Franklin")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(document.site.framework.typography.bodyFont == original)
    }

    @Test
    func discardingGoogleFontPreviewLeavesTheDocumentUntouched() {
        let document = FoundryDocument()
        let session = FrameworkEditorSession(document: document, undoManager: UndoManager())
        let original = document.site.framework.typography.headingFont

        session.previewGoogleFont("Roboto", for: .role(.heading))
        session.discardFontPreview()

        #expect(session.font(for: .role(.heading)) == original)
        #expect(document.site.framework.typography.headingFont == original)
    }
}
