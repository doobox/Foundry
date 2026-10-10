import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemePresetTests {
    @Test func presetContainsOnlyReusableAppearance() throws {
        var theme = Theme.standard
        let original = ThemePreset(theme)
        theme.screens.update(.extraLarge) { $0.isEnabled = true }
        theme.spacing.custom = [.init(name: "hero", value: 8)]
        theme.typography.customFonts = [.init(name: "Editorial", font: .system(family: "Georgia", weights: [400]))]
        theme.bootstrapTokens.custom["fontSize"] = ["hero"]
        theme.bootstrapTokens.values["font-size-hero"] = "4rem"
        theme.colourPalettes.append(try theme.colourPalettes[0].duplicated())
        #expect(ThemePreset(theme) == original)
        let data = try JSONEncoder().encode(ThemePreset(theme))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "colourPalettes", "bodyFont", "headingFont", "monospacedFont", "bootstrapTokens"])
        #expect(try JSONDecoder().decode(ThemePreset.self, from: data) == original)
        theme.bootstrapTokens.values["link-color"] = "#123456"
        #expect(ThemePreset(theme) != original)
        #expect(ThemePreset(theme).bootstrapTokens.custom.isEmpty)
    }

    @Test func updatingResettingAndDeletingPreserveProjectValues() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        document.site.theme.screens.update(.extraLarge) { $0.isEnabled = true }
        document.site.theme.spacing.custom = [.init(name: "hero", value: 8)]
        document.site.theme.bootstrapTokens.custom["fontSize"] = ["hero"]
        document.site.theme.bootstrapTokens.values["font-size-hero"] = "4rem"
        let screens = document.site.theme.screens
        let spacing = document.site.theme.spacing
        let id = UUID()
        for operation in 0...2 {
            if operation == 0 { editor.commitTheme(.standard, sourceID: id) }
            if operation == 1 { editor.resetTheme(.standard, sourceID: id) }
            if operation == 2 { editor.didDeleteTheme(sourceID: id) }
            #expect(document.site.theme.screens == screens)
            #expect(document.site.theme.spacing == spacing)
            #expect(document.site.theme.bootstrapTokens.values["font-size-hero"] == "4rem")
            #expect(document.site.theme.savedSettings == Theme.standard.savedSettings)
        }
    }

    @Test func readsLegacyAndRejectsFutureVersions() throws {
        var old = Theme.standard
        old.typography.headingFont.family = "Georgia"
        old.bootstrapTokens.values["link-color"] = "#123456"
        let preset = try JSONDecoder().decode(ThemePreset.self, from: JSONEncoder().encode(old))
        #expect(preset == ThemePreset(old))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ThemePreset.self, from: Data(#"{"schemaVersion":99}"#.utf8))
        }
        let defaults = try JSONDecoder().decode(ThemePreset.self, from: Data(#"{"schemaVersion":1}"#.utf8))
        #expect(defaults == ThemePreset(.standard))
    }

    @Test func appearanceRoundTripPreservesGeneratedCSS() throws {
        var original = Theme.standard
        original.bootstrapTokens.values["link-color"] = "light-dark(#123456, #abcdef)"
        original.bootstrapTokens.values["radius-5"] = "0.75rem"
        let index = try #require(original.colourPalettes.firstIndex { $0.id == "framework.primary" })
        original.colourPalettes[index].bootstrapTokens["primary-fg"] = BootstrapTokenColour(
            light: BootstrapColourScale.native("indigo"), dark: BootstrapColourScale.native("yellow"))
        let restored = try JSONDecoder().decode(ThemePreset.self, from: JSONEncoder().encode(ThemePreset(original))).theme
        #expect(BootstrapColorCSS.export(theme: restored, mode: .both) == BootstrapColorCSS.export(theme: original, mode: .both))
        #expect(BootstrapThemeCSS.render(theme: restored) == BootstrapThemeCSS.render(theme: original))
    }

    @Test func exportWritesCurrentPresetAndReloads() throws {
        let source = try #require(ThemeBundleStore.builtInThemes().first)
        let destination = FileManager.default.temporaryDirectory.appending(path: "theme-export-\(UUID()).foundrypack")
        defer { try? FileManager.default.removeItem(at: destination) }
        try FoundryPackLoader.exportTheme(source, to: destination)
        let bundle = destination.appending(path: "Themes/\(source.id.uuidString)")
        let data = try Data(contentsOf: bundle.appending(path: "Resources/theme.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["screens"] == nil)
        #expect(json["spacing"] == nil)
        let loaded = try ThemeBundleStore.load(from: bundle)
        #expect(loaded.id == source.id)
        #expect(ThemePreset(loaded.theme) == ThemePreset(source.theme))
        #expect(ThemeBundleStore.isThemeURL(bundle))
        #expect(try FoundryPackLoader.load(from: destination).themeURLs.map(\.path) == [bundle.path])
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Frameworks").path) == false)
        #expect(FileManager.default.fileExists(atPath: bundle.appending(path: "Resources/framework.json").path) == false)
    }

    @Test func rejectsOldThemePaths() throws {
        let source = try #require(ThemeBundleStore.builtInThemes().first)
        let destination = FileManager.default.temporaryDirectory.appending(path: "old-theme-paths-\(UUID()).foundrypack")
        defer { try? FileManager.default.removeItem(at: destination) }
        try FoundryPackLoader.exportTheme(source, to: destination)
        let bundle = destination.appending(path: "Themes/\(source.id.uuidString)")
        try FileManager.default.moveItem(at: bundle.appending(path: "Resources/theme.json"),
                                        to: bundle.appending(path: "Resources/framework.json"))
        #expect(ThemeBundleStore.isThemeURL(bundle) == false)
        #expect(throws: ThemeBundleError.self) { try ThemeBundleStore.load(from: bundle) }
        try FileManager.default.moveItem(at: destination.appending(path: "Themes"),
                                        to: destination.appending(path: "Frameworks"))
        #expect(throws: FoundryPackLoadingError.self) { try FoundryPackLoader.load(from: destination) }
    }
}
