import Foundation
import Testing
@testable import Foundry

@Suite("Bootstrap 6 colors")
struct BootstrapColorCSSTests {
    @Test func paletteUsesBootstrapScaleStops() {
        #expect(ColourShade.allCases.count == 13)
        #expect(ColourShade.allCases.map(\.bootstrapLabel) == [
            "025", "050", "100", "200", "300", "400", "500",
            "600", "700", "800", "900", "950", "975"
        ])
        #expect(Framework.standard.fixedFrameworkColourPalettes.count == FrameworkColorRole.allCases.count)
    }

    @Test func exportOverridesEveryThemeRoleAndAdaptiveLayer() throws {
        let framework = Framework.standard
        let css = BootstrapColorCSS.export(framework: framework, mode: .both)
        for role in ["primary", "accent", "success", "danger", "warning", "info", "inverse", "secondary"] {
            #expect(css.contains("--bs-\(role)-base:"), "Missing Bootstrap base token for \(role)")
            #expect(css.contains("--bs-\(role)-fg:"), "Missing Bootstrap foreground token for \(role)")
            #expect(css.contains("--bs-\(role)-contrast:"), "Missing Bootstrap contrast token for \(role)")
        }
        #expect(css.contains("--bs-bg-body:light-dark("))
        #expect(css.contains("--bs-fg-body:light-dark("))
        #expect(css.contains("--bs-border-body:light-dark("))
        #expect(css.contains("--bs-primary-focus-ring:light-dark(color-mix(in oklch,"))
    }

    @Test func canvasSelectsASchemeAndPreservesAdaptiveTokens() {
        let light = BootstrapColorCSS.canvas(framework: .standard, appearance: .light)
        let dark = BootstrapColorCSS.canvas(framework: .standard, appearance: .dark)
        #expect(light.contains("color-scheme:light;"))
        #expect(dark.contains("color-scheme:dark;"))
        #expect(light.contains("light-dark("))
        #expect(dark.contains("light-dark("))
        #expect(light != dark)
    }

    @Test func bootstrapIsTheGlobalRenderedFramework() {
        let requirements = FoundryWebLibraryRegistry.uniqueRequirements(in: [])
        #expect(requirements.first == FoundryWebLibraryRegistry.bootstrapRequirement)
        #expect(FoundryWebLibraryRegistry.canvasCSS(for: []).contains("--bs-primary-base"))
        #expect(FoundryWebLibraryRegistry.exportScripts(for: [], prefix: "files/libraries", placement: .beforePage)
            .contains { $0.isModule && $0.path.contains("bootstrap-6.0.0-alpha.1.bundle.min.js") })
    }
}
