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
        let token = try #require(document.site.theme.spacing.custom.first)
        #expect(editor.renameCustomSpacing(token.id, name: "hero"))
        editor.setCustomSpacing(token.id, value: 2)
        undo.endUndoGrouping()
        #expect(document.site.theme.spacing.custom.first?.value == 2)
        let themeCSS = BootstrapThemeCSS.render(theme: document.site.theme)
        #expect(themeCSS.contains("--bs-spacer-hero: 2.0rem"))
        let data = try JSONEncoder().encode(document.site.theme)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["bootstrapBuild"] == nil)
        let restored = try JSONDecoder().decode(Theme.self, from: data)
        #expect(BootstrapThemeCSS.render(theme: restored) == themeCSS)
        undo.undo()
        #expect(document.site.theme.spacing.custom.isEmpty)
        undo.redo()
        #expect(document.site.theme.spacing.custom.first?.value == 2)

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
        let updated = BootstrapThemeCSS.render(theme: document.site.theme)
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
        print("Live Bootstrap stylesheet update and computed layout: \(result["milliseconds"] ?? "unknown") ms")
    }

    @Test func appDoesNotShipCompilerOrLayoutVariants() {
        #expect(Bundle.main.url(forResource: "BootstrapCompiler", withExtension: "bundle") == nil)
        #expect(Bundle.main.url(forResource: "BootstrapLayouts", withExtension: "bundle") == nil)
    }

    @Test func invalidSpacersDoNotChangeTheTheme() {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        editor.addCustomSpacing()
        guard let token = document.site.theme.spacing.custom.first else { Issue.record("Missing custom size"); return }
        for value in [-1, Double.infinity, Double.nan] {
            editor.setCustomSpacing(token.id, value: value)
            #expect(document.site.theme.spacing.custom.first?.value == 4)
        }
        for name in ["5", "auto", "none", "", "hero space", "hero;}"] {
            #expect(editor.renameCustomSpacing(token.id, name: name) == false)
        }
    }

    @Test func defaultThemeStopsAtLarge() throws {
        let theme = Theme.standard
        #expect(BootstrapLayout.mask(for: theme.screens) == 7)
        #expect(theme.screens.screen(.doubleExtraLarge).container.value == 960)
        var enabled = theme
        enabled.screens.update(.extraLarge) { $0.isEnabled = true }
        enabled.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let restored = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(enabled))
        #expect(BootstrapLayout.mask(for: restored.screens) == 31)
        #expect(restored.screens.screen(.doubleExtraLarge).container.value == 1440)
    }

    @Test(arguments: Array(0..<32))
    func enabledSizesAndContainerWidthsStayConsistent(mask: Int) throws {
        var theme = Theme.standard
        for (index,id) in BootstrapLayout.ids.enumerated() {
            theme.screens.update(id) { $0.isEnabled = mask & (1 << index) != 0 }
        }
        #expect(BootstrapLayout.mask(for: theme.screens) == mask)
        #expect(theme.screens.enabledScreens.count == mask.nonzeroBitCount + 1)
        var inherited = ThemeContainerWidth(value: 0, unit: .auto)
        for (index,id) in BootstrapLayout.ids.enumerated() {
            let screen = theme.screens.screen(id)
            if screen.isEnabled { inherited = ScreenTokens.standard.screen(id).container }
            #expect(screen.container == inherited)
            #expect(screen.minimumWidth == ScreenTokens.standard.screen(id).minimumWidth)
            #expect(BootstrapLayout.allowsContainerClass(BootstrapLayout.classes[index], screens: theme.screens) == screen.isEnabled)
        }
        // Bootstrap's containers are capped only where a disabled breakpoint would otherwise widen them.
        #expect(BootstrapUtilityExtensionsCSS.containerCSS(theme.screens).isEmpty == (mask == 31))
        let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
        #expect(decoded.screens == theme.screens)
    }

    @Test func switchingUpdatesPreviewAndSupportsUndo() throws {
        let document = FoundryDocument()
        document.site.theme.screens.update(.extraLarge) { $0.isEnabled = true }
        document.site.theme.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let original = document.site.theme.screens
        undo.beginUndoGrouping()
        editor.setThemeScreenEnabled(.doubleExtraLarge, value: false)
        editor.setThemeScreenEnabled(.extraLarge, value: false)
        undo.endUndoGrouping()
        let screens = document.site.theme.screens
        #expect(screens.screen(.doubleExtraLarge).container.value == 960)
        #expect(CanvasBreakpointPreference.viewportWidth(afterChanging: original, to: screens, currentWidth: 1536) == 1024)
        #expect(BootstrapLayout.containerClass("2xl:container", screens: screens) == "lg:container")
        undo.undo()
        #expect(document.site.theme.screens == original)
        undo.redo()
        #expect(document.site.theme.screens == screens)
    }

    @Test func legacyValuesRemainRecoverableWithoutAppearingInTheEditor() throws {
        var legacy = ScreenTokens.standard
        legacy.update(.small) { $0.minimumWidth = 640; $0.container = .init(value: 90, unit: .percent) }
        var theme = Theme(spacing: .standard, typography: Theme.standard.typography, screens: legacy)
        #expect(theme.screens.screen(.small).minimumWidth == 576)
        theme.screens.update(.extraLarge) { $0.isEnabled = false }
        let data = try JSONEncoder().encode(theme)
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
            var theme = Theme.standard
            for (index,id) in BootstrapLayout.ids.enumerated() {
                theme.screens.update(id) { $0.isEnabled = mask & (1 << index) != 0 }
            }
            var container = PartNode.make(.container)
            container.anchor = "layout-test"
            container.customClasses = "2xl:d-flex"
            container.children = [PartNode.make(.button)]
            let page = Page(title: "Layout", slug: "index", parts: [container])
            let html: String
            if destination == "canvas" {
                html = HTMLPageRenderer().render(page: page, theme: theme)
            } else {
                var site = Site(name: "Layout", pages: [page])
                site.theme = theme
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
            let cap = theme.screens.screen(.doubleExtraLarge).container
            let expected = cap.unit == .auto ? "none" : "\(Int(cap.value))px"
            #expect(actual == [expected,"flex"], "\(destination), switches \(mask)")
        }
    }
}
