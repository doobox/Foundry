import Foundation
import Testing
@testable import Foundry

@MainActor
struct CustomThemeColourTests {
    @Test(.timeLimit(.minutes(1)), arguments: [ThemePaletteColorRole.background, .foreground, .border])
    func layerGroupsGenerateEditAndReset(role: ThemePaletteColorRole) async throws {
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "brand")
        let original = model.storedPalettes
        let scale = try #require(BootstrapColourScale(base: "oklch(55% 0.12 250)"))
        var generated = try await BootstrapThemeGenerator.generate(role: role, scale: scale)
        #expect(generated.bootstrapScale == scale)
        #expect(generated.bootstrapTokens.isEmpty)
        #expect(generated.bootstrapGeneratedContrast == nil)
        var theme = Theme.standard
        theme.colourPalettes = [generated]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both)
        let expressions = BootstrapColourCatalogue.tokens(for: role.rawValue).map { "var(--bs-\($0))" }
        for mode in ["light", "dark"] {
            let values = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: mode)
            let defaults = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: BootstrapColourCatalogue.sourceCSS, mode: mode)
            #expect(values != defaults)
        }
        let token = try #require(BootstrapColourCatalogue.tokens(for: role.rawValue).first)
        generated.bootstrapTokens[token] = BootstrapTokenColour(light: .native("white"), dark: .native("black"))
        theme.colourPalettes = [generated]
        let editedCSS = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both)
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
        let model = ThemeColourPreviewModel()
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
        var theme = Theme.standard
        theme.colourPalettes = model.storedPalettes
        #expect(BootstrapPaletteTheme.resolve(original.id, theme: theme) == "theme-ocean")
        let css = BootstrapColorCSS.export(theme: theme, mode: .both)
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
        let model = ThemeColourPreviewModel()
        for name in ["blue", "white", "reset", "subtle-primary", "", "a b", "1brand", "x;}body{"] {
            #expect(model.canAddTheme(named: name) == false, "Reserved or invalid name: \(name)")
        }
        model.addTheme(named: "brand")
        let palette = try #require(model.storedPalettes.last)
        #expect(palette.id == "custom.brand")
        #expect(model.canAddTheme(named: "brand") == false)
        var theme = Theme.standard
        theme.colourPalettes = model.storedPalettes
        #expect(BootstrapPaletteTheme.selectablePalettes(in: theme).contains(palette))
        #expect(BootstrapPaletteTheme.resolve(palette.id, theme: theme) == "theme-brand")
        let site = Site(name: "Custom themes", pages: [], theme: theme)
        let saved = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        #expect(saved.theme.colourPalettes.contains(palette))
        var part = PartNode.make(.button)
        part.setProperty(.init(rawValue: "theme"), value: .choice(palette.id))
        part.replaceThemeReference(palette.id, with: "framework.accent")
        #expect(part.property(.init(rawValue: "theme")) == "framework.accent")
    }

    @Test(arguments: BootstrapColourCatalogue.themeRoles)
    func oldNamedOverridesBecomeDirectThemeEdits(name: String) throws {
        let document = FoundryDocument()
        let model = ThemeColourPreviewModel(storedPalettes: document.site.theme.colourPalettes)
        #expect(model.canAddTheme(named: name) == false)
        let role = try #require(ThemePaletteColorRole(rawValue: name))
        var custom = try BootstrapColourCatalogue.palette(role: role, hue: "pink").duplicated()
        custom.name = name
        custom.bootstrapTokens[name + "-contrast"] = BootstrapTokenColour(light: .native("black"))
        document.site.theme.colourPalettes.append(custom)
        var part = PartNode.make(.button)
        part.setProperty(.init(rawValue: "theme"), value: .choice(custom.id))
        document.site.pages = [Page(title: "Test", slug: "index", parts: [part])]
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(restored.hasNamedThemeOverrides == false)
        let session = ThemeEditorSession(document: document, undoManager: nil)
        #expect(session.canEditTheme)
        #expect(document.site.theme.colourPalettes.contains { $0.id == custom.id } == false)
        #expect(document.site.pages[0].parts[0].property(.init(rawValue: "theme")) == "framework." + name)
        let migrated = try #require(BootstrapPaletteTheme.effectivePalette("framework." + name, in: document.site.theme))
        #expect(migrated.origin == .theme)
        #expect(migrated.bootstrapScale == custom.bootstrapScale)
        #expect(migrated.bootstrapTokens == custom.bootstrapTokens)
        #expect(restored.theme == document.site.theme)
        #expect(BootstrapPaletteTheme.resolve(migrated.id, theme: restored.theme) == "theme-" + name)
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedCustomTokensMatchNativeThemeInBothModes() async throws {
        let model = ThemeColourPreviewModel()
        model.addTheme(named: "brand")
        let original = try #require(model.storedPalettes.last)
        let scale = try #require(BootstrapColourScale(base: "oklch(35% 0.12 25)"))
        let generated = try await BootstrapThemeGenerator.generate(role: .primary, scale: scale)
        var custom = BootstrapPaletteTheme.applying(generated, to: original)
        #expect(custom.id == original.id)
        custom.bootstrapTokens["brand-bg-subtle"] = BootstrapTokenColour(light: .native("white"), dark: .native("black"))
        var theme = Theme.standard
        theme.colourPalettes = [generated, custom]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(theme: theme, mode: .both)
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
