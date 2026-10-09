import Foundation
import Testing
@testable import Foundry

@MainActor
struct BootstrapTokenEditingTests {
    @Test(.timeLimit(.minutes(1)), arguments: [
        ("oklch(0% 0 0)", "#FFFFFF"),
        ("oklch(30% 0.12 25)", "#FFFFFF"),
        ("oklch(50% 0.15 25)", "#FFFFFF"),
        ("oklch(60% 0.24 240)", "#FFFFFF"),
        ("oklch(60% 0.22 4)", "#FFFFFF"),
        ("oklch(100% 0 0)", "#000000"),
        ("oklch(85% 0.15 90)", "#000000")
    ])
    func generatedContrastSwitchesWithBackground(sample: (String, String)) async throws {
        let scale = try #require(BootstrapColourScale(base: sample.0))
        let generated = try await BootstrapThemeGenerator.generate(role: .primary, scale: scale)
        #expect(generated.bootstrapTokens.isEmpty)
        #expect(generated.bootstrapScale == scale)
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(generated))
        #expect(restored == generated)
        var framework = Framework.standard
        framework.colourPalettes[0] = restored
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        for mode in ["light", "dark"] {
            let colours = try await BootstrapScalePreviewResolver().resolve(
                expressions: ["var(--bs-primary-bg)", "var(--bs-primary-contrast)"], css: css, mode: mode)
            #expect(colours[1] == sample.1)
            #expect(try #require(BootstrapColourContrast.ratio(colours[0], colours[1])) >= 3)
            let channels = try #require(PartColorChannels(hex: colours[0]))
            #expect(colours[1] == channels.preferredContrastColor)
            #expect(channels.derivedValues["contrastColor"] == .string(colours[1]))
        }
    }

    @Test(arguments: ["#0087FE", "#FF0000", "#FF3366"])
    func visualPreferenceDoesNotSuppressNormalTextWarning(hex: String) throws {
        let channels = try #require(PartColorChannels(hex: hex))
        #expect(channels.preferredContrastColor == "#FFFFFF")
        let ratio = try #require(BootstrapColourContrast.ratio(hex, channels.preferredContrastColor))
        #expect(ratio >= 3)
        #expect(ratio < 4.5)
    }

    @Test func tokenEditsSurviveSaveUndoAndReset() throws {
        let original = BootstrapColourCatalogue.palette(role: .primary)
        var edited = original
        edited.bootstrapTokens["primary-contrast"] = BootstrapTokenColour(light: BootstrapColourScale.native("black"))
        let model = FrameworkColourPreviewModel(storedPalettes: [original])
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.update(PreviewColourPalette(stored: edited), session: UUID(), undoManager: undo)
        undo.endUndoGrouping()
        let restored = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(model.storedPalettes[0]))
        #expect(restored == edited)
        undo.undo()
        #expect(model.storedPalettes == [original])
        undo.redo()
        #expect(model.storedPalettes == [edited])
        var framework = Framework.standard
        framework.colourPalettes[0] = restored
        let saved = try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(framework.savedSettings))
        #expect(saved.colourPalettes[0].bootstrapTokens == edited.bootstrapTokens)
        framework.colourPalettes[0] = original
        #expect(BootstrapColorCSS.export(framework: framework, mode: .both) == BootstrapColorCSS.export(framework: .standard, mode: .both))
    }

    @Test(.timeLimit(.minutes(1)))
    func tokenModesAndLayersResolveIndependently() async throws {
        var framework = Framework.standard
        let primary = try #require(framework.colourPalettes.firstIndex { $0.id == "framework.primary" })
        let background = try #require(framework.colourPalettes.firstIndex { $0.id == "framework.background" })
        framework.colourPalettes[primary].bootstrapTokens["primary-bg"] = BootstrapTokenColour(light: BootstrapColourScale.native("black"))
        framework.colourPalettes[background].bootstrapTokens["bg-body"] = BootstrapTokenColour(
            light: BootstrapColourScale.native("black"), dark: BootstrapColourScale.native("white"))
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        let tokens = ["primary-bg", "primary-contrast", "bg-body", "primary-bg-subtle"]
        let expressions = tokens.map { "var(--bs-\($0))" }
        let light = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: "light")
        let dark = try await BootstrapScalePreviewResolver().resolve(expressions: expressions, css: css, mode: "dark")
        #expect(light[0] == "#000000")
        #expect(dark[0] == BootstrapColourCatalogue.previews.palettes["blue"]?[6])
        #expect(light[1] == "#FFFFFF")
        #expect(dark[1] == "#FFFFFF")
        #expect(light[2] == "#000000")
        #expect(dark[2] == "#FFFFFF")
        #expect(light[3] != dark[3])
    }

    @Test func contrastIsReportedNotSubstituted() throws {
        #expect(try #require(BootstrapColourContrast.ratio("#000000", "#FFFFFF")) == 21)
        #expect(try #require(BootstrapColourContrast.ratio("#FFFFFF", "#FFFFFF")) == 1)
        let pink = try #require(BootstrapColourCatalogue.previews.palettes["pink"]?[6])
        #expect(try #require(BootstrapColourContrast.ratio(pink, "#FFFFFF")) < 4.5)
    }
}
