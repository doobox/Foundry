import Testing
@testable import Foundry

struct BootstrapTextSizeTests {
    @Test(arguments: [("0.75rem", 1.25), ("1rem", 1.5), ("2.5rem", 1.2), ("3rem", 1.1), ("8rem", 1.0), ("44px", 1.15), ("clamp(1rem, 2vw, 3rem)", 1.1)])
    func automaticHeightFollowsBootstrapPairs(sample: (String, Double)) {
        #expect(abs(BootstrapTextSize.lineHeight(for: sample.0) - sample.1) < 0.00001)
    }

    @Test func customSizesExposeOnlySizeAndIgnoreSavedLineHeight() {
        #expect(BootstrapEditorSection.fontSize.customTokens(named: "hero").map(\.id) == ["font-size-hero"])
        var theme = Theme.standard
        theme.bootstrapTokens.custom["fontSize"] = ["hero"]
        theme.bootstrapTokens.values = ["font-size-hero": "3rem", "line-height-hero": "2.8", "font-size-md": "8rem"]
        let css = BootstrapEditorCSS.render(theme)
        #expect(css.contains("--bs-line-height-hero:1.1"))
        #expect(css.contains("--bs-font-size-md:") == false)
        theme.bootstrapTokens.values["font-size-hero"] = "5rem"
        #expect(BootstrapEditorCSS.render(theme).contains("--bs-line-height-hero:1"))
        theme.bootstrapTokens.custom["fontSize"] = []
        #expect(BootstrapEditorCSS.render(theme).contains("hero") == false)
    }
}
