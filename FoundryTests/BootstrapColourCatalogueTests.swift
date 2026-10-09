import CryptoKit
import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapColourCatalogueTests {
    @Test func catalogueMatchesTheBundledStylesheet() throws {
        let css = BootstrapColourCatalogue.sourceCSS
        let hash = SHA256.hash(data: Data(css.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(hash == BootstrapColourCatalogue.previews.cssSHA256)
        let names = Set(ColourPaletteDefaults.standard.map(\.name))
        #expect(names == Set(["Black", "White", "Blue", "Indigo", "Violet", "Purple", "Pink", "Red",
            "Orange", "Amber", "Yellow", "Lime", "Green", "Teal", "Cyan", "Brown", "Gray", "Pewter"]))
        for hue in BootstrapColourCatalogue.hues {
            for shade in ColourShade.allCases {
                #expect(BootstrapColourCatalogue.declarations["--bs-\(hue)-\(shade.bootstrapLabel)"] != nil)
            }
        }
    }

    @Test func nativeHueSelectionSurvivesEditorStorageAndUndo() throws {
        let original = BootstrapColourCatalogue.palette(role: .primary)
        let selected = BootstrapColourCatalogue.palette(role: .primary, hue: "purple")
        let model = FrameworkColourPreviewModel(storedPalettes: [original])
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.update(PreviewColourPalette(stored: selected), session: UUID(), undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.storedPalettes == [selected])
        let stored = try JSONDecoder().decode([ColourPalette].self, from: JSONEncoder().encode(model.storedPalettes))
        #expect(stored[0].bootstrapHue == "purple")
        #expect(PreviewColourPalette(stored: stored[0]).storedValue == selected)
        undo.undo()
        #expect(model.storedPalettes == [original])
        undo.redo()
        #expect(model.storedPalettes == [selected])
        var framework = Framework.standard
        framework.colourPalettes[0] = stored[0]
        #expect(BootstrapColorCSS.export(framework: framework, mode: .both).contains("--bs-primary-bg:var(--bs-purple-500)"))
        #expect(PartPackageColorResolver.resolve(.init(source: "primary", customColor: "#000000", opacity: 1),
            framework: framework, opacity: false) == "var(--bs-purple-500)")
    }

    @Test(.timeLimit(.minutes(1)))
    func defaultSemanticColoursMatchBootstrapInBothModesAndNestedScopes() async throws {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        defer { view.stopLoading() }
        view.loadHTMLString("<!doctype html><html><head><style>\(BootstrapColourCatalogue.sourceCSS)</style></head><body><div id='scope'><span id='probe'>Colour</span></div></body></html>", baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('probe')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let tokens = FrameworkColorRole.allCases.flatMap { BootstrapColourCatalogue.tokens(for: $0.rawValue) }
        let result = try #require(try await view.callAsyncJavaScript("""
            const probe = document.getElementById('probe'), scope = document.getElementById('scope');
            function sample() {
                const values = {};
                for (const mode of ['light','dark']) {
                    document.documentElement.dataset.bsTheme = mode;
                    for (const nested of ['', 'light', 'dark']) {
                        if (nested) scope.dataset.bsTheme = nested; else delete scope.dataset.bsTheme;
                        for (const token of tokens) {
                            probe.style.color = `var(--bs-${token})`;
                            values[`${mode}/${nested}/${token}`] = getComputedStyle(probe).color;
                        }
                    }
                }
                return values;
            }
            const expected = sample();
            const style = document.createElement('style'); style.textContent = overrides; document.head.append(style);
            const actual = sample();
            return Object.keys(expected).filter(k => actual[k] !== expected[k]).map(k => `${k}: ${actual[k]} != ${expected[k]}`);
            """, arguments: ["tokens": tokens, "overrides": BootstrapColorCSS.export(framework: .standard, mode: .both)],
            in: nil, contentWorld: .defaultClient) as? [String])
        if !result.isEmpty { Issue.record("\(result.prefix(10).joined(separator: "\n"))") }
    }
}
