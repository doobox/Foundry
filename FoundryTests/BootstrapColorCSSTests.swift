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
        #expect(Theme.standard.fixedThemeColourPalettes.count == ThemePaletteColorRole.allCases.count)
    }

    @Test func defaultThemeUsesBundledBootstrapColours() throws {
        #expect(BootstrapColorCSS.export(theme: .standard, mode: .both).isEmpty)
        #expect(FoundryWebLibraryRegistry.canvasCSS(for: []).contains("--bs-primary-base:"))
        #expect(FoundryWebLibraryRegistry.canvasCSS(for: []).contains("--bs-bg-body:"))
    }

    @Test func fixedUtilitiesAreSharedRatherThanGeneratedIntoAnEmptySite() throws {
        let site = Site(name: "Empty", pages: [Page(title: "Home", slug: "index")])
        let output = StaticSiteRenderer(environment: .preview).render(site: site)
        let siteCSS = try #require(output.file(at: "files/site.css")?.contents)
        let utilities = try #require(output.file(at: FoundryWebLibraryRegistry.sharedUtilityPath)?.contents)
        let html = try #require(output.file(at: "index.html")?.contents)
        #expect(!siteCSS.contains(".sm\\:fs-xs"))
        #expect(!siteCSS.contains("--bs-primary-base:"))
        #expect(!siteCSS.contains("--bs-font-heading:"))
        #expect(utilities.contains(".sm\\:fs-xs"))
        #expect(utilities.contains(".font-heading"))
        #expect(html.contains("files/libraries/foundry/foundry-utilities.css"))
    }

    @Test func canvasSelectsASchemeAndPreservesAdaptiveTokens() {
        let light = BootstrapColorCSS.canvas(theme: .standard, appearance: .light)
        let dark = BootstrapColorCSS.canvas(theme: .standard, appearance: .dark)
        #expect(light.contains("color-scheme:light;"))
        #expect(dark.contains("color-scheme:dark;"))
        #expect(!light.contains("--bs-primary-base:"))
        #expect(!dark.contains("--bs-primary-base:"))
        #expect(light != dark)
    }

    @Test func bootstrapIsTheGlobalRenderedTheme() {
        let requirements = FoundryWebLibraryRegistry.uniqueRequirements(in: [])
        #expect(requirements.first == FoundryWebLibraryRegistry.bootstrapRequirement)
        #expect(FoundryWebLibraryRegistry.canvasCSS(for: []).contains("--bs-primary-base"))
        #expect(FoundryWebLibraryRegistry.exportScripts(for: [], prefix: "files/libraries", placement: .beforePage)
            .contains { $0.isModule && $0.path.contains("bootstrap-6.0.0-alpha.1.bundle.min.js") })
    }

    @Test func bootstrapIconsAreAvailableWithoutPartDependencies() throws {
        #expect(FoundryWebLibraryRegistry.uniqueRequirements(in: []) == [
            FoundryWebLibraryRegistry.bootstrapRequirement,
            FoundryWebLibraryRegistry.iconRequirement
        ])
        let canvasCSS = FoundryWebLibraryRegistry.canvasCSS(for: [])
        #expect(canvasCSS.contains(".bi-magic::before"))
        #expect(canvasCSS.contains("data:font/woff2;base64,"))
        let exportCSS = try #require(FoundryWebLibraryRegistry.exportFiles(for: []).first {
            $0.path == "files/libraries/bootstrapIcons/bootstrap-icons.css"
        }).contents
        #expect(exportCSS.contains(".bi-magic::before"))
        #expect(exportCSS.contains("./bootstrap-icons.woff2"))
        #expect(FoundryWebLibraryRegistry.themeOverridesCSS(for: []).isEmpty)
        let fonts = FoundryWebLibraryRegistry.exportFiles(for: []).filter {
            $0.path == "files/libraries/bootstrapIcons/bootstrap-icons.woff2"
        }
        #expect(fonts.count == 1)
    }
    @Test func namedCustomColourFamiliesEmitReadableUtilities() throws {
        var theme = Theme.standard
        let base = BootstrapColourCatalogue.palette(role: .primary)
        for kind in [BootstrapColourKind.surface, .foreground, .border, .link] {
            var palette = try ColourPalette(id: "custom.new-\(kind.rawValue)", name: "new-\(kind.rawValue)",
                origin: .custom, shades: base.shades, lightDefaultShade: base.lightDefaultShade)
            palette.customKind = kind
            theme.colourPalettes.append(palette)
        }
        let css = BootstrapColorCSS.export(theme: theme, mode: .both)
        #expect(css.contains(".bg-new-surface-3{--bs-bg:var(--bs-"))
        #expect(css.contains(".fg-new-foreground-2{--bs-fg:var(--bs-"))
        #expect(css.contains(".border-new-border-subtle{--bs-bc:var(--bs-"))
        #expect(css.contains(".link-new-link{--bs-link-color:var(--bs-"))
        #expect(css.contains(".link-new-link-hover{color:var(--bs-"))
        #expect(!css.contains(".fd-bg--custom-"))
        for (kind, source, expected) in [
            (BootstrapColourKind.surface, "bg-3", "bg-new-surface-3"),
            (.foreground, "fg-2", "fg-new-foreground-2"),
            (.border, "border-subtle", "border-new-border-subtle"),
            (.link, "link-color", "link-new-link")
        ] {
            let palette = try #require(theme.colourPalettes.first { $0.customKind == kind })
            let purpose: PartColourPurpose = switch kind {
            case .surface: .background
            case .foreground: .foreground
            case .border: .border
            case .link: .link
            case .theme: .background
            }
            let result = purpose.resolve("token:" + palette.colourToken(source), theme: theme)
            #expect(result.className == expected)
            #expect(result.css.isEmpty)
        }
    }
}
