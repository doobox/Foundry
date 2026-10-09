import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapEditorTokenTests {
    @Test func defaultsAreNativeAndShadowGeometryRoundTrips() throws {
        #expect(BootstrapEditorCSS.render(.standard).isEmpty)
        for section in BootstrapEditorSection.allCases {
            #expect(section.tokens.isEmpty == false)
            for token in section.tokens {
                #expect(BootstrapEditorToken.safeValue(token.defaultValue), "\(token.id)")
                #expect(token.defaultValue.isEmpty == false)
                if token.id.hasPrefix("box-shadow") {
                    let geometry = BootstrapShadowGeometry.parse(token.defaultValue)
                    #expect(geometry.isEmpty == false, "\(token.id)")
                    #expect(BootstrapShadowGeometry.parse(geometry.map(\.css).joined(separator: ", ")) == geometry)
                }
            }
        }
        #expect(1070.0.bootstrapCSSNumber == "1070")
        #expect(0.125.bootstrapCSSNumber == "0.125")
        #expect(BootstrapEditorToken("z-menu").acceptsNumber(1.5) == false)
        #expect(BootstrapEditorToken("radius-5").acceptsNumber(-1) == false)
        #expect(BootstrapEditorToken("control-disabled-opacity").acceptsNumber(2) == false)
        #expect(BootstrapEditorToken("focus-ring-offset").acceptsNumber(-2))
    }

    @Test func customTokensResetPersistAndUndo() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.addBootstrapToken("hero", section: .fontSize)
        let token = try #require(BootstrapEditorSection.fontSize.tokens.first)
        editor.setBootstrapToken(token, value: "2rem")
        undo.endUndoGrouping()
        let edited = document.site.framework
        #expect(edited.bootstrapTokens.isChanged(.fontSize))
        #expect(BootstrapCustomTokenClasses.choices(existing: ["fs-md"], framework: edited) == ["fs-hero"])
        undo.beginUndoGrouping()
        editor.resetBootstrapTokens(.fontSize)
        undo.endUndoGrouping()
        #expect(document.site.framework.bootstrapTokens.isChanged(.fontSize) == false)
        #expect(document.site.framework.bootstrapTokens.custom["fontSize"] == ["hero"])
        undo.undo()
        #expect(document.site.framework == edited)
        let restored = try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(edited))
        #expect(restored == edited)
        undo.beginUndoGrouping()
        editor.selectFramework(.standard, sourceID: UUID())
        editor.selectFramework(.standard, sourceID: FrameworkBundleStore.systemFrameworkID)
        undo.endUndoGrouping()
        #expect(document.site.framework.bootstrapTokens == edited.bootstrapTokens)
        for name in ["md", "none", "bad name", "x;}body{", "primary"] {
            #expect(editor.canAddBootstrapToken(name, section: .fontSize) == false)
        }
        #expect(BootstrapEditorToken.safeValue("1rem;}body{display:none") == false)
        #expect(editor.canAddBootstrapToken("13", section: .borderRadius))
    }

    @Test(.timeLimit(.minutes(1)))
    func editedScalesReachNativeUtilitiesAndComponents() async throws {
        var framework = Framework.standard
        framework.bootstrapTokens.values = [
            "font-size-md": "2rem", "line-height-md": "1.75", "font-weight-bold": "800",
            "border-width-2": "7px", "radius-5": "1.25rem", "z-menu": "1200",
            "body-font-size": "1.125rem", "body-line-height": "1.6", "link-color": "#123456",
            "focus-ring-width": "5px", "btn-input-padding-x": "2rem",
            "box-shadow-sm": "0 4px 8px oklch(from var(--bs-sc, var(--bs-shadow-color)) l c h / calc(.2 * var(--bs-shadow-strength) * var(--bs-so, 1)))",
            "shadow-strength-light": "1.5", "shadow-strength-dark": "3"
        ]
        framework.bootstrapTokens.custom["fontSize"] = ["hero"]
        framework.bootstrapTokens.values["font-size-hero"] = "3rem"
        framework.typography.bodyFont = .system(family: "serif", weights: [400])
        let browser = BootstrapTokenBrowser()
        try await browser.load("""
            <html data-bs-theme="light"><head><style>\(BootstrapColourCatalogue.sourceCSS)</style><style id="theme">\(BootstrapThemeCSS.render(framework: framework))</style></head><body>
            <div id="text" class="text-md fw-bold">Test</div><div id="hero" class="fs-hero">Hero</div>
            <div id="border" class="border border-2 rounded-5"></div><div id="edge" class="rounded-top-5"></div>
            <div id="z" class="z-menu"></div><a id="link" href="#">Link</a>
            <button id="button" class="btn btn-solid">Button</button><div id="shadow" class="shadow-sm shadow-primary"></div>
            </body></html>
            """)
        let values = try #require(try await browser.web.evaluateJavaScript("""
            (() => { const s=id=>getComputedStyle(document.getElementById(id));return [
            s('text').fontSize,s('text').lineHeight,s('text').fontWeight,s('hero').fontSize,
            s('border').borderTopWidth,s('border').borderTopLeftRadius,s('edge').borderTopLeftRadius,
            s('z').zIndex,s('button').paddingLeft,getComputedStyle(document.body).fontSize,
            getComputedStyle(document.body).fontFamily,getComputedStyle(document.documentElement).getPropertyValue('--bs-focus-ring-width').trim()];})()
            """) as? [String])
        #expect(values == ["32px", "56px", "800", "48px", "7px", "20px", "20px", "1200", "32px", "18px", "serif", "5px"])
        let light = try #require(try await browser.web.evaluateJavaScript("getComputedStyle(document.getElementById('shadow')).boxShadow") as? String)
        #expect(light.contains("4px 8px"))
        let dark = try #require(try await browser.web.evaluateJavaScript("document.documentElement.dataset.bsTheme='dark'; getComputedStyle(document.getElementById('shadow')).boxShadow") as? String)
        #expect(light != dark)
        let before = try #require(try await browser.web.evaluateJavaScript("getComputedStyle(document.getElementById('text')).fontSize") as? String)
        framework.bootstrapTokens.values["font-size-md"] = "2.5rem"
        let css = String(decoding: try JSONEncoder().encode(BootstrapThemeCSS.render(framework: framework)), as: UTF8.self)
        let after = try #require(try await browser.web.evaluateJavaScript("document.getElementById('theme').textContent=\(css);getComputedStyle(document.getElementById('text')).fontSize") as? String)
        #expect(before == "32px")
        #expect(after == "40px")
    }
}
