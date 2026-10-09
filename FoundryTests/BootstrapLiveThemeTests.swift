import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapLiveThemeTests {
    @Test(.timeLimit(.minutes(1)))
    func customSpacerUpdatesEverySpacingFamilyAndPersistsWithUndo() async throws {
        let baseCSS = FoundryWebLibraryRegistry.canvasCSS(for: [])
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.addCustomSpacing()
        let token = try #require(document.site.framework.spacing.custom.first)
        #expect(editor.renameCustomSpacing(token.id, name: "hero"))
        editor.setCustomSpacing(token.id, value: 2)
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.custom.first?.value == 2)
        let themeCSS = BootstrapThemeCSS.render(framework: document.site.framework)
        #expect(themeCSS.contains("--bs-spacer-hero: 2.0rem"))
        let data = try JSONEncoder().encode(document.site.framework)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["bootstrapBuild"] == nil)
        let restored = try JSONDecoder().decode(Framework.self, from: data)
        #expect(BootstrapThemeCSS.render(framework: restored) == themeCSS)
        undo.undo()
        #expect(document.site.framework.spacing.custom.isEmpty)
        undo.redo()
        #expect(document.site.framework.spacing.custom.first?.value == 2)

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        defer { view.stopLoading() }
        view.loadHTMLString("<html><head><style>\(baseCSS)</style><style id='theme'>\(themeCSS)</style></head><body><div id='padding' class='p-hero m-hero'></div><div id='gap' class='d-flex gap-hero'><i></i><i></i></div><div class='space-y-hero'><i id='space'></i><i></i></div><div id='responsive' class='p-hero md:p-5'></div><div id='reverse' class='p-5 md:p-hero'></div></body></html>", baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('space')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let values = try #require(try await view.evaluateJavaScript("[getComputedStyle(document.getElementById('padding')).paddingTop,getComputedStyle(document.getElementById('padding')).marginTop,getComputedStyle(document.getElementById('gap')).gap,getComputedStyle(document.getElementById('space')).marginBottom]") as? [String])
        #expect(values == ["32px", "32px", "32px", "32px"])
        let responsive = try await view.evaluateJavaScript("[getComputedStyle(document.getElementById('responsive')).paddingTop,getComputedStyle(document.getElementById('reverse')).paddingTop]") as? [String]
        #expect(responsive == ["16px", "32px"])
        // Change the real settings sheet in the existing document: no navigation,
        // no generated markup replacement, and no compiler process.
        undo.beginUndoGrouping()
        editor.setCustomSpacing(token.id, value: 3)
        undo.endUndoGrouping()
        let updated = BootstrapThemeCSS.render(framework: document.site.framework)
        let cssJSON = String(decoding: try JSONEncoder().encode(updated), as: UTF8.self)
        let result = try #require(try await view.evaluateJavaScript("""
            (() => {
            const css = \(cssJSON);
            const element = document.getElementById('padding');
            window.spacingSentinel = element;
            const start = performance.now();
            document.getElementById('theme').textContent = css;
            const values = [getComputedStyle(element).paddingTop,
              getComputedStyle(element).marginTop,
              getComputedStyle(document.getElementById('gap')).gap,
              getComputedStyle(document.getElementById('space')).marginBottom];
            return {values, sameElement: document.getElementById('padding') === window.spacingSentinel, milliseconds: performance.now()-start};
            })()
            """) as? [String: Any])
        #expect(result["values"] as? [String] == ["48px", "48px", "48px", "48px"])
        #expect(result["sameElement"] as? Bool == true)
        undo.beginUndoGrouping()
        editor.setBootstrapSpacing(5, value: 4)
        undo.endUndoGrouping()
        let editedStepCSS = String(decoding: try JSONEncoder().encode(BootstrapThemeCSS.render(framework: document.site.framework)), as: UTF8.self)
        let nativeStep = try await view.evaluateJavaScript("""
            document.getElementById('theme').textContent = \(editedStepCSS);
            [getComputedStyle(document.getElementById('responsive')).paddingTop,
             getComputedStyle(document.getElementById('reverse')).paddingTop]
            """) as? [String]
        #expect(nativeStep == ["64px", "48px"])
        print("Live Bootstrap stylesheet update and computed layout: \(result["milliseconds"] ?? "unknown") ms")
    }

    @Test func appDoesNotShipCompilerOrLayoutVariants() {
        #expect(Bundle.main.url(forResource: "BootstrapCompiler", withExtension: "bundle") == nil)
        #expect(Bundle.main.url(forResource: "BootstrapLayouts", withExtension: "bundle") == nil)
    }

    @Test func invalidSpacersDoNotChangeTheFramework() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        editor.addCustomSpacing()
        guard let token = document.site.framework.spacing.custom.first else { Issue.record("Missing custom size"); return }
        for value in [-1, Double.infinity, Double.nan] {
            editor.setCustomSpacing(token.id, value: value)
            #expect(document.site.framework.spacing.custom.first?.value == 4)
        }
        for name in ["5", "auto", "none", "", "hero space", "hero;}"] {
            #expect(editor.renameCustomSpacing(token.id, name: name) == false)
        }
    }

    @Test func defaultFrameworkStopsAtLarge() throws {
        let framework = Framework.standard
        #expect(BootstrapLayout.mask(for: framework.screens) == 7)
        #expect(framework.screens.screen(.doubleExtraLarge).container.value == 960)
        var enabled = framework
        enabled.screens.update(.extraLarge) { $0.isEnabled = true }
        enabled.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let restored = try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(enabled))
        #expect(BootstrapLayout.mask(for: restored.screens) == 31)
        #expect(restored.screens.screen(.doubleExtraLarge).container.value == 1440)
    }

    @Test(arguments: Array(0..<32))
    func enabledSizesAndContainerWidthsStayConsistent(mask: Int) throws {
        var framework = Framework.standard
        for (index,id) in BootstrapLayout.ids.enumerated() {
            framework.screens.update(id) { $0.isEnabled = mask & (1 << index) != 0 }
        }
        #expect(BootstrapLayout.mask(for: framework.screens) == mask)
        #expect(framework.screens.enabledScreens.count == mask.nonzeroBitCount + 1)
        var inherited = FrameworkContainerWidth(value: 0, unit: .auto)
        for (index,id) in BootstrapLayout.ids.enumerated() {
            let screen = framework.screens.screen(id)
            if screen.isEnabled { inherited = ScreenTokens.standard.screen(id).container }
            #expect(screen.container == inherited)
            #expect(screen.minimumWidth == ScreenTokens.standard.screen(id).minimumWidth)
            #expect(BootstrapLayout.allowsContainerClass(BootstrapLayout.classes[index], screens: framework.screens) == screen.isEnabled)
        }
        #expect(BootstrapThemeCSS.render(framework: framework).contains("--bs-container-2xl:"))
        let decoded = try JSONDecoder().decode(Framework.self, from: JSONEncoder().encode(framework))
        #expect(decoded.screens == framework.screens)
    }

    @Test func switchingUpdatesPreviewAndSupportsUndo() throws {
        let document = FoundryDocument()
        document.site.framework.screens.update(.extraLarge) { $0.isEnabled = true }
        document.site.framework.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let original = document.site.framework.screens
        undo.beginUndoGrouping()
        editor.setFrameworkScreenEnabled(.doubleExtraLarge, value: false)
        editor.setFrameworkScreenEnabled(.extraLarge, value: false)
        undo.endUndoGrouping()
        let screens = document.site.framework.screens
        #expect(screens.screen(.doubleExtraLarge).container.value == 960)
        #expect(CanvasBreakpointPreference.viewportWidth(afterChanging: original, to: screens, currentWidth: 1536) == 1024)
        #expect(BootstrapLayout.containerClass("2xl:container", screens: screens) == "lg:container")
        undo.undo()
        #expect(document.site.framework.screens == original)
        undo.redo()
        #expect(document.site.framework.screens == screens)
    }

    @Test func legacyValuesRemainRecoverableWithoutAppearingInTheEditor() throws {
        var legacy = ScreenTokens.standard
        legacy.update(.small) { $0.minimumWidth = 640; $0.container = .init(value: 90, unit: .percent) }
        var framework = Framework(spacing: .standard, typography: Framework.standard.typography, screens: legacy)
        #expect(framework.screens.screen(.small).minimumWidth == 576)
        framework.screens.update(.extraLarge) { $0.isEnabled = false }
        let data = try JSONEncoder().encode(framework)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let archive = try #require(object["archivedScreens"] as? [String: Any])
        let records = try #require(archive["screens"] as? [[String: Any]])
        let savedSmall = try #require(records.first { $0["id"] as? String == "small" })
        #expect(savedSmall["minimumWidth"] as? Int == 640)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"])
    func allSwitchCombinationsRenderNativeLayouts(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1800, height: 500))
        defer { view.stopLoading() }
        for mask in 0..<32 {
            var framework = Framework.standard
            for (index,id) in BootstrapLayout.ids.enumerated() {
                framework.screens.update(id) { $0.isEnabled = mask & (1 << index) != 0 }
            }
            var container = PartNode.make(.container)
            container.anchor = "layout-test"
            container.customClasses = "2xl:d-flex"
            container.children = [PartNode.make(.button)]
            let page = Page(title: "Layout", slug: "index", parts: [container])
            let html: String
            if destination == "canvas" {
                html = HTMLPageRenderer().render(page: page, framework: framework)
            } else {
                var site = Site(name: "Layout", pages: [page])
                site.framework = framework
                let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
                #expect(bundle.errors.isEmpty)
                let output = try #require(bundle.file(at: "index.html"))
                #expect(output.contents.contains("data-foundry-") == false)
                let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
                html = output.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
            }
            let markedHTML = html.replacingOccurrences(of: "</head>", with: "<meta name=\"layout-test-mask\" content=\"\(mask)\"></head>")
            view.loadHTMLString(markedHTML, baseURL: nil)
            var ready = false
            for _ in 0..<200 {
                ready = (try? await view.evaluateJavaScript("document.readyState === 'complete' && document.querySelector('meta[name=layout-test-mask]')?.content === '\(mask)' && !!document.getElementById('layout-test')")) as? Bool == true
                if ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(ready)
            let actual = try #require(try await view.evaluateJavaScript("(() => {const s=getComputedStyle(document.getElementById('layout-test'));return [s.maxWidth,s.display];})()") as? [String])
            let cap = framework.screens.screen(.doubleExtraLarge).container
            let expected = cap.unit == .auto ? "none" : "\(Int(cap.value))px"
            #expect(actual == [expected,"flex"], "\(destination), switches \(mask)")
        }
    }
}
