import Foundation
import Testing
import WebKit
@testable import Foundry

struct BootstrapProseTests {
    @Test func defaultsEmitNothingAndBaseEditsPreserveWideDefaults() {
        #expect(BootstrapProseCSS.render(.init()).isEmpty)
        let css = BootstrapProseCSS.render(.init(values: ["prose-font-size": "2rem"]))
        #expect(css.contains("--bs-content-font-size:2rem"))
        #expect(css.contains("@media (width>=1024px){.prose{--bs-content-font-size:var(--bs-font-size-md)}}"))
        #expect(css.contains("heading-color") == false)
    }

    @Test func themeAndPresetRoundTrip() throws {
        var theme = Theme.standard
        theme.bootstrapTokens.values = ["prose-font-size": "2rem", "prose-heading-color-dark": "#ffffff"]
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded.bootstrapTokens == theme.bootstrapTokens)
        let preset = try JSONDecoder().decode(ThemePreset.self, from: JSONEncoder().encode(ThemePreset(theme)))
        #expect(preset.theme.bootstrapTokens == theme.bootstrapTokens)
    }

    @MainActor @Test func resetRemovesOverridesAndSupportsUndo() {
        let document = FoundryDocument()
        let undo = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undo)
        editor.setBootstrapToken(BootstrapEditorSection.prose.tokens[0], value: "2rem")
        undo.removeAllActions()
        editor.resetBootstrapTokens(.prose)
        #expect(BootstrapProseCSS.render(document.site.theme.bootstrapTokens).isEmpty)
        undo.undo()
        #expect(document.site.theme.bootstrapTokens.values["prose-font-size"] == "2rem")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [800, 1024])
    func browserResolvesSizesSpacingAndColourModes(width: Int) async throws {
        var theme = Theme.standard
        theme.bootstrapTokens.values = [
            "prose-font-size": "2rem", "prose-line-height": "2",
            "prose-wide-font-size": "1.5rem", "prose-wide-line-height": "1.75",
            "prose-gap": "3rem", "prose-heading-color-light": "#112233",
            "prose-heading-color-dark": "#ddeeff"
        ]
        let browser = BootstrapTokenBrowser()
        browser.web.frame.size.width = CGFloat(width)
        try await browser.load("""
        <!doctype html><html><head><style>\(BootstrapColourCatalogue.sourceCSS)\(BootstrapThemeCSS.render(theme: theme))</style></head>
        <body><div class="prose"><h2>Heading</h2><p>Text</p></div><div id="ordinary">Ordinary text</div></body></html>
        """)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [], prose = document.querySelector('.prose');
          const wide = innerWidth >= 1024;
          const style = getComputedStyle(prose);
          if (style.fontSize !== (wide ? '24px' : '32px')) errors.push('font size: ' + style.fontSize);
          if (style.lineHeight !== (wide ? '42px' : '64px')) errors.push('line height: ' + style.lineHeight);
          if (style.gap !== '48px') errors.push('gap: ' + style.gap);
          if (getComputedStyle(document.getElementById('ordinary')).fontSize !== '16px') errors.push('leaked size');
          for (const [mode, expected] of [['light', 'rgb(17, 34, 51)'], ['dark', 'rgb(221, 238, 255)']]) {
            document.documentElement.setAttribute('data-bs-theme', mode);
            const colour = getComputedStyle(prose.querySelector('h2')).color;
            if (colour !== expected) errors.push(mode + ': ' + colour);
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }
}
