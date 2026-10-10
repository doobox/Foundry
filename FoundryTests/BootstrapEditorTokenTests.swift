import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapEditorTokenTests {
    @Test func globalColourScalesGenerateAllShadesAndResetIndependently() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        #expect(BootstrapEditorSection.colourScales.tokens.count == 16 * 13)
        for hue in BootstrapColourCatalogue.hues {
            let native = try #require(BootstrapColourScale.native(hue))
            for shade in ColourShade.allCases {
                #expect(native.expression(at: shade) == BootstrapColourCatalogue.declarations["--bs-\(hue)-\(shade.bootstrapLabel)"])
            }
        }
        let scale = try #require(BootstrapColourScale(base: "oklch(55% 0.15 120)"))
        undo.beginUndoGrouping()
        editor.setBootstrapColourScale("blue", scale: scale)
        editor.setBootstrapToken(BootstrapEditorToken("link-color"), value: "#123456")
        undo.endUndoGrouping()
        let edited = document.site.framework
        for shade in ColourShade.allCases {
            #expect(edited.bootstrapTokens.values["blue-" + shade.bootstrapLabel] == scale.expression(at: shade))
        }
        undo.beginUndoGrouping()
        editor.resetBootstrapTokens(.colourScales)
        undo.endUndoGrouping()
        #expect(document.site.framework.bootstrapTokens.isChanged(.colourScales) == false)
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == "#123456")
        undo.undo()
        #expect(document.site.framework == edited)
        #expect(try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(edited)) == edited)
    }

    @Test func colourGroupSourcesRegenerateHoverAndKeepLiveReferences() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        #expect(BootstrapColourSource.selected(in: .standard, section: .linkColours) == "default")
        let blue = try #require(BootstrapColourSource.choices(for: .linkColours).first { $0.id == "hue-blue" })
        document.site.framework.bootstrapTokens.values["link-hover-color"] = "#abcdef"
        undo.beginUndoGrouping()
        editor.setBootstrapColourGroup(.linkColours, base: blue.expression)
        undo.endUndoGrouping()
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == blue.expression)
        #expect(document.site.framework.bootstrapTokens.values["link-hover-color"] == nil)
        #expect(BootstrapColourSource.selected(in: document.site.framework, section: .linkColours) == "hue-blue")
        undo.undo()
        #expect(document.site.framework.bootstrapTokens.values["link-hover-color"] == "#abcdef")
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == nil)
        undo.beginUndoGrouping()
        editor.setBootstrapColourGroup(.linkColours, base: "#123456")
        editor.setBootstrapColourGroup(.shadowColours, base: "var(--bs-gray-500)")
        undo.endUndoGrouping()
        #expect(BootstrapColourSource.selected(in: document.site.framework, section: .linkColours) == "custom")
        #expect(BootstrapColourSource.selected(in: document.site.framework, section: .shadowColours) == "hue-gray")
        #expect(BootstrapEditorCSS.render(document.site.framework).contains("--bs-shadow-color:var(--bs-gray-500)"))
    }

    @Test func blackWhiteResetPreservesOtherColours() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        #expect(BootstrapEditorSection.blackWhite.tokens.map(\.id) == ["black", "white"])
        for token in BootstrapEditorSection.blackWhite.tokens {
            #expect(token.defaultValue == BootstrapColourCatalogue.declarations["--bs-" + token.id])
            editor.setBootstrapToken(token, value: token.id == "black" ? "#112233" : "#eeeeee")
        }
        editor.setBootstrapToken(BootstrapEditorToken("link-color"), value: "#123456")
        let edited = document.site.framework
        #expect(BootstrapEditorCSS.render(edited).contains("--bs-black:#112233"))
        #expect(BootstrapEditorCSS.render(edited).contains("--bs-white:#eeeeee"))
        #expect(try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(edited)) == edited)
        editor.resetBootstrapTokens(.blackWhite)
        #expect(document.site.framework.bootstrapTokens.isChanged(.blackWhite) == false)
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == "#123456")
    }

    @Test func shadowColourAndStrengthResetIndependently() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        document.site.framework.bootstrapTokens.values = [
            "shadow-color": "#123456", "shadow-strength-light": "1.5", "shadow-strength-dark": "3"
        ]
        #expect(BootstrapEditorSection.shadows.tokens.map(\.id) == ["shadow-strength-light", "shadow-strength-dark"])
        #expect(BootstrapEditorSection.shadowColours.tokens.map(\.id) == ["shadow-color"])
        editor.resetBootstrapTokens(.shadows)
        #expect(document.site.framework.bootstrapTokens.values["shadow-color"] == "#123456")
        #expect(document.site.framework.bootstrapTokens.values["shadow-strength-light"] == nil)
        #expect(document.site.framework.bootstrapTokens.values["shadow-strength-dark"] == nil)
        #expect(BootstrapEditorCSS.render(document.site.framework).contains("--bs-shadow-color:#123456"))
        editor.setBootstrapToken(BootstrapEditorToken("shadow-strength-dark"), value: "3")
        editor.resetBootstrapTokens(.shadowColours)
        #expect(document.site.framework.bootstrapTokens.values["shadow-color"] == nil)
        #expect(document.site.framework.bootstrapTokens.values["shadow-strength-dark"] == "3")
    }

    @Test func linkColoursAndLinkLayoutResetIndependently() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        document.site.framework.bootstrapTokens.values = [
            "link-color": "#123456", "link-hover-color": "#abcdef", "link-decoration": "none"
        ]
        #expect(BootstrapEditorSection.links.tokens.map(\.id) == ["link-decoration", "link-underline-offset"])
        #expect(BootstrapEditorSection.linkColours.tokens.map(\.id) == ["link-color", "link-hover-color"])
        #expect(BootstrapEditorCSS.render(document.site.framework).contains("--bs-link-color:#123456"))
        editor.resetBootstrapTokens(.links)
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == "#123456")
        #expect(document.site.framework.bootstrapTokens.values["link-hover-color"] == "#abcdef")
        #expect(document.site.framework.bootstrapTokens.values["link-decoration"] == nil)
        editor.setBootstrapToken(BootstrapEditorToken("link-decoration"), value: "none")
        editor.resetBootstrapTokens(.linkColours)
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == nil)
        #expect(document.site.framework.bootstrapTokens.values["link-hover-color"] == nil)
        #expect(document.site.framework.bootstrapTokens.values["link-decoration"] == "none")
    }

    @Test func defaultsAreNativeAndBootstrapScalesStayFixed() throws {
        // Defaults need only Foundry's heading-font extension, not token overrides.
        #expect(BootstrapEditorCSS.render(.standard) == ":root,:host{--bs-font-heading:inherit}@layer content{h1,h2,h3,h4,h5,h6,.h1,.h2,.h3,.h4,.h5,.h6{font-family:var(--bs-font-heading)}}@layer utilities{.font-heading{font-family:var(--bs-font-heading)}}")
        #expect(BootstrapEditorSection.fontSize.tokens.isEmpty)
        for section in BootstrapEditorSection.allCases where section != .fontSize {
            #expect(section.tokens.isEmpty == false, "\(section)")
            for token in section.tokens {
                #expect(BootstrapEditorToken.safeValue(token.defaultValue), "\(token.id)")
                #expect(token.defaultValue.isEmpty == false)
            }
        }
        // Bootstrap bakes these scales into its utilities, so Foundry never edits them.
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        for id in ["font-size-md", "line-height-md", "font-weight-bold", "border-width-2", "border-width-keyline", "radius-3", "box-shadow-sm", "z-1", "spacer-5"] {
            editor.setBootstrapToken(.init(id), value: "9px")
            #expect(document.site.framework.bootstrapTokens.values[id] == nil, "\(id)")
        }
        // Component tokens and project additions remain editable.
        editor.setBootstrapToken(.init("radius-7"), value: "1rem")
        #expect(document.site.framework.bootstrapTokens.values["radius-7"] == "1rem")
        editor.addBootstrapToken("soft", section: .shadows)
        let custom = try #require(BootstrapEditorSection.shadows.customTokens(named: "soft").first)
        let geometry = BootstrapShadowGeometry.parse(custom.defaultValue)
        #expect(geometry.isEmpty == false)
        #expect(BootstrapShadowGeometry.parse(geometry.map(\.css).joined(separator: ", ")) == geometry)
        editor.setBootstrapToken(custom, value: "0 2px 4px black")
        #expect(document.site.framework.bootstrapTokens.values[custom.id] == "0 2px 4px black")
        #expect(BootstrapEditorCSS.render(document.site.framework).contains(".shadow-soft{box-shadow:0 2px 4px black}"))
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
        let token = try #require(BootstrapEditorSection.fontSize.customTokens(named: "hero").first)
        editor.setBootstrapToken(token, value: "2rem")
        undo.endUndoGrouping()
        let edited = document.site.framework
        #expect(edited.bootstrapTokens.value(token) == "2rem")
        #expect(BootstrapCustomTokenClasses.choices(existing: ["fs-md"], framework: edited) == ["fs-hero"])
        undo.beginUndoGrouping()
        editor.setBootstrapToken(token, value: "3rem")
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
    func editedTokensReachComponentsWhileUtilitiesStayNative() async throws {
        var framework = Framework.standard
        framework.bootstrapTokens.values = [
            "radius-7": "1.25rem", "border-width": "3px", "z-menu": "1200",
            "body-font-size": "1.125rem", "body-line-height": "1.6", "link-color": "#123456",
            "focus-ring-width": "5px", "btn-input-padding-x": "2rem",
            "shadow-strength-light": "1.5", "shadow-strength-dark": "3"
        ]
        framework.bootstrapTokens.custom["fontSize"] = ["hero"]
        framework.bootstrapTokens.values["font-size-hero"] = "3rem"
        framework.typography.bodyFont = .system(family: "serif", weights: [400])
        let browser = BootstrapTokenBrowser()
        try await browser.load("""
            <html data-bs-theme="light"><head><style>\(BootstrapColourCatalogue.sourceCSS)</style><style id="theme">\(BootstrapThemeCSS.render(framework: framework))</style></head><body>
            <div id="text" class="text-md fw-bold">Test</div><div id="hero" class="fs-hero">Hero</div>
            <div id="card" class="card"><div class="card-body">Card</div></div><div id="border" class="border border-2 rounded-5"></div>
            <div id="z" class="z-menu"></div><a id="link" href="#">Link</a>
            <button id="button" class="btn btn-solid">Button</button><div id="shadow" class="shadow-sm shadow-primary"></div>
            </body></html>
            """)
        let values = try #require(try await browser.web.evaluateJavaScript("""
            (() => { const s=id=>getComputedStyle(document.getElementById(id));return [
            s('text').fontSize,s('text').lineHeight,s('text').fontWeight,s('hero').fontSize,
            s('card').borderTopLeftRadius,s('card').borderTopWidth,s('border').borderTopWidth,
            s('z').zIndex,getComputedStyle(document.documentElement).getPropertyValue('--bs-z-menu').trim(),
            s('button').paddingLeft,getComputedStyle(document.body).fontSize,
            getComputedStyle(document.body).fontFamily,getComputedStyle(document.documentElement).getPropertyValue('--bs-focus-ring-width').trim()];})()
            """) as? [String])
        // Components follow the edited variables. Utilities keep Bootstrap's fixed values:
        // `border-2` stays 2px and `z-menu` stays 1000 while the component layer variable moves to 1200.
        #expect(values == ["16px", "24px", "700", "48px", "20px", "3px", "2px", "1000", "1200", "32px", "18px", "serif", "5px"])
        let light = try #require(try await browser.web.evaluateJavaScript("getComputedStyle(document.getElementById('shadow')).boxShadow") as? String)
        let dark = try #require(try await browser.web.evaluateJavaScript("document.documentElement.dataset.bsTheme='dark'; getComputedStyle(document.getElementById('shadow')).boxShadow") as? String)
        #expect(light != dark)
        let before = try #require(try await browser.web.evaluateJavaScript("getComputedStyle(document.getElementById('text')).fontSize") as? String)
        framework.bootstrapTokens.values["font-size-md"] = "2.5rem"
        let css = String(decoding: try JSONEncoder().encode(BootstrapThemeCSS.render(framework: framework)), as: UTF8.self)
        let after = try #require(try await browser.web.evaluateJavaScript("document.getElementById('theme').textContent=\(css);getComputedStyle(document.getElementById('text')).fontSize") as? String)
        #expect(before == "16px")
        #expect(after == "16px")
        framework.bootstrapTokens.values["blue-500"] = "#123456"
        let scaleCSS = String(decoding: try JSONEncoder().encode(BootstrapThemeCSS.render(framework: framework)), as: UTF8.self)
        let themeColour = try #require(try await browser.web.evaluateJavaScript("""
            document.getElementById('theme').textContent=\(scaleCSS);
            document.getElementById('hero').style.color='var(--bs-primary-base)';
            getComputedStyle(document.getElementById('hero')).color
            """) as? String)
        #expect(themeColour == "rgb(18, 52, 86)")
    }
}
