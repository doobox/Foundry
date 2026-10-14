import Testing
@testable import Foundry

struct ForegroundColourPreviewTests {
    @Test
    func genericForegroundGroupUsesForegroundThemeRole() {
        #expect(PartColourPurpose.previewRole(purpose: nil, group: .foreground) == "fg")
        #expect(PartColourPurpose.previewRole(purpose: nil, group: .foreground, variant: "emphasis") == "fg-emphasis")
        #expect(PartColourPurpose.previewRole(purpose: nil, group: .foreground, variant: "contrast") == "contrast")
        #expect(PartColourPurpose.previewRole(purpose: .foreground, group: nil) == "fg")
        #expect(PartColourPurpose.previewRole(purpose: nil, group: nil) == "bg")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func themeForegroundResolvesDistinctLightAndDarkSwatches() async throws {
        let theme = Theme.standard
        let css = BootstrapColourCatalogue.sourceCSS
            + BootstrapColorCSS.export(theme: theme, mode: .both)
            + BootstrapThemeCSS.render(theme: theme)
        let expressions = ["var(--bs-primary-fg)", "var(--bs-primary-fg-emphasis)", "var(--bs-primary-bg)"]
        let resolver = BootstrapScalePreviewResolver()
        let light = try await resolver.resolve(expressions: expressions, css: css, mode: "light")
        let dark = try await resolver.resolve(expressions: expressions, css: css, mode: "dark")

        #expect(light[0] != dark[0])
        #expect(light[1] != dark[1])
        #expect(light[2] == dark[2])
    }
}
