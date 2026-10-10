import Foundation
import Testing
@testable import Foundry

@MainActor
struct CustomThemeColourTests {
    @Test(.timeLimit(.minutes(1)), arguments: [FrameworkColorRole.background, .foreground, .border])
    func layerGroupsGenerateEditAndReset(role: FrameworkColorRole) async throws {
        let model = FrameworkColourPreviewModel()
        model.addTheme(named: "brand")
        let original = model.storedPalettes
        let scale = try #require(BootstrapColourScale(base: "oklch(55% 0.12 250)"))
        var generated = try await BootstrapThemeGenerator.generate(role: role, scale: scale)
        #expect(generated.bootstrapScale == scale)
        #expect(generated.bootstrapTokens.isEmpty)
        #expect(generated.bootstrapGeneratedContrast == nil)
        var framework = Framework.standard
        framework.colourPalettes = [generated]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        let expressions = BootstrapColourCatalogue.tokens(for: role.rawValue).map { "var(--bs-\($0))" }
        for mode in ["light", "dark"] {
            let values = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: mode)
            let defaults = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: BootstrapColourCatalogue.sourceCSS, mode: mode)
            #expect(values != defaults)
        }
        let token = try #require(BootstrapColourCatalogue.tokens(for: role.rawValue).first)
        generated.bootstrapTokens[token] = BootstrapTokenColour(light: .native("white"), dark: .native("black"))
        framework.colourPalettes = [generated]
        let editedCSS = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        for mode in ["light", "dark"] {
            let values = try await BootstrapScalePreviewResolver().resolve(expressions: ["var(--bs-\(token))"], css: editedCSS, mode: mode)
            #expect(values == [mode == "light" ? "#FFFFFF" : "#000000"])
        }
        #expect(try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(generated)) == generated)
        model.update(PreviewColourPalette(stored: generated), session: UUID(), undoManager: nil)
        let group = PreviewColourPalette(stored: generated).group
        #expect(model.canReset(group))
        #expect(model.canReset(.theme) == false)
        let edited = model.storedPalettes
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.reset(group, undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.storedPalettes == original)
        #expect(model.canReset(group) == false)
        undo.undo()
        #expect(model.storedPalettes == edited)
        undo.redo()
        #expect(model.storedPalettes == original)
    }

    @Test func renamePreservesIdentityTokensAndUndo() throws {
        let model = FrameworkColourPreviewModel()
        model.addTheme(named: "brand")
        var original = try #require(model.storedPalettes.last)
        original.bootstrapTokens["brand-contrast"] = BootstrapTokenColour(light: .native("black"))
        model.update(PreviewColourPalette(stored: original), session: UUID(), undoManager: nil)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.renameTheme(id: original.id, name: "ocean", undoManager: undo)
        undo.endUndoGrouping()
        let renamed = try #require(model.storedPalettes.last)
        #expect(renamed.id == original.id)
        #expect(renamed.name == "ocean")
        #expect(renamed.bootstrapTokens["ocean-contrast"] == original.bootstrapTokens["brand-contrast"])
        #expect(renamed.bootstrapTokens["brand-contrast"] == nil)
        var framework = Framework.standard
        framework.colourPalettes = model.storedPalettes
        #expect(BootstrapPaletteTheme.resolve(original.id, framework: framework) == "theme-ocean")
        let css = BootstrapColorCSS.export(framework: framework, mode: .both)
        #expect(css.contains(".theme-ocean{"))
        #expect(css.contains(".theme-brand{") == false)
        #expect(try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(renamed)) == renamed)
        undo.undo()
        #expect(model.storedPalettes.last == original)
        undo.redo()
        #expect(model.storedPalettes.last == renamed)
        model.addTheme(named: "brand")
        #expect(model.storedPalettes.last?.id != original.id)
        #expect(model.canAddTheme(named: "brand", excluding: original.id) == false)
        model.renameTheme(id: original.id, name: "blue", undoManager: nil)
        #expect(model.storedPalettes.first { $0.id == original.id }?.name == "ocean")
    }

    @Test func namesAndPersistence() throws {
        let model = FrameworkColourPreviewModel()
        for name in ["blue", "white", "reset", "subtle-primary", "", "a b", "1brand", "x;}body{"] {
            #expect(model.canAddTheme(named: name) == false, "Reserved or invalid name: \(name)")
        }
        model.addTheme(named: "brand")
        let palette = try #require(model.storedPalettes.last)
        #expect(palette.id == "custom.brand")
        #expect(model.canAddTheme(named: "brand") == false)
        var framework = Framework.standard
        framework.colourPalettes = model.storedPalettes
        #expect(BootstrapPaletteTheme.selectablePalettes(in: framework).contains(palette))
        #expect(BootstrapPaletteTheme.resolve(palette.id, framework: framework) == "theme-brand")
        let site = Site(name: "Custom themes", pages: [], framework: framework)
        let saved = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(saved.framework.colourPalettes.contains(palette))
        var part = PartNode.make(.button)
        part.setProperty(.init(rawValue: "theme"), value: .choice(palette.id))
        part.replaceFrameworkReference(palette.id, with: "framework.accent")
        #expect(part.property(.init(rawValue: "theme")) == "framework.accent")
    }

    @Test(arguments: BootstrapColourCatalogue.themeRoles)
    func oldNamedOverridesBecomeDirectThemeEdits(name: String) throws {
        let document = FoundryDocument()
        let model = FrameworkColourPreviewModel(storedPalettes: document.site.framework.colourPalettes)
        #expect(model.canAddTheme(named: name) == false)
        let role = try #require(FrameworkColorRole(rawValue: name))
        var custom = try BootstrapColourCatalogue.palette(role: role, hue: "pink").duplicated()
        custom.name = name
        custom.bootstrapTokens[name + "-contrast"] = BootstrapTokenColour(light: .native("black"))
        document.site.framework.colourPalettes.append(custom)
        var part = PartNode.make(.button)
        part.setProperty(.init(rawValue: "theme"), value: .choice(custom.id))
        document.site.pages = [Page(title: "Test", slug: "index", parts: [part])]
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(restored.hasNamedThemeOverrides == false)
        let session = FrameworkEditorSession(document: document, undoManager: nil)
        #expect(session.canEditFramework)
        #expect(document.site.framework.colourPalettes.contains { $0.id == custom.id } == false)
        #expect(document.site.pages[0].parts[0].property(.init(rawValue: "theme")) == "framework." + name)
        let migrated = try #require(BootstrapPaletteTheme.effectivePalette("framework." + name, in: document.site.framework))
        #expect(migrated.origin == .framework)
        #expect(migrated.bootstrapScale == custom.bootstrapScale)
        #expect(migrated.bootstrapTokens == custom.bootstrapTokens)
        #expect(restored.framework == document.site.framework)
        #expect(BootstrapPaletteTheme.resolve(migrated.id, framework: restored.framework) == "theme-" + name)
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedCustomTokensMatchNativeThemeInBothModes() async throws {
        let model = FrameworkColourPreviewModel()
        model.addTheme(named: "brand")
        let original = try #require(model.storedPalettes.last)
        let scale = try #require(BootstrapColourScale(base: "oklch(35% 0.12 25)"))
        let generated = try await BootstrapThemeGenerator.generate(role: .primary, scale: scale)
        var custom = BootstrapPaletteTheme.applying(generated, to: original)
        #expect(custom.id == original.id)
        custom.bootstrapTokens["brand-bg-subtle"] = BootstrapTokenColour(light: .native("white"), dark: .native("black"))
        var framework = Framework.standard
        framework.colourPalettes = [generated, custom]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        #expect(css.contains(".theme-brand{"))
        #expect(css.contains(".fg-brand{"))
        for mode in ["light", "dark"] {
            let values = try await BootstrapScalePreviewResolver().resolve(expressions: [
                "var(--bs-brand-bg)", "var(--bs-primary-bg)", "var(--bs-brand-contrast)",
                "var(--bs-primary-contrast)", "var(--bs-brand-bg-subtle)"
            ], css: css, mode: mode)
            #expect(values[0] == values[1])
            #expect(values[2] == values[3])
            #expect(values[2] == "#FFFFFF")
            #expect(values[4] == (mode == "light" ? "#FFFFFF" : "#000000"))
        }
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.update(PreviewColourPalette(stored: custom), session: UUID(), undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        #expect(model.storedPalettes.last == original)
        undo.redo()
        #expect(model.storedPalettes.last == custom)
    }
}
