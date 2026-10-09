import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapButtonTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["canvas-light", "canvas-dark", "export"])
    func buttonMatchesBootstrapComponentStyles(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let button = PartNode.make(.button)
        var container = PartNode.make(.container)
        container.children = [button]
        let page = Page(title: "Bootstrap button", slug: "index", parts: [container])
        let html: String
        if destination == "export" {
            let bundle = StaticSiteRenderer().render(site: Site(name: "Buttons", pages: [page]))
            let document = try #require(bundle.file(at: "index.html"))
            let styles = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.contents.replacingOccurrences(of: "</head>", with: "<style>\(styles)</style></head>")
        } else {
            html = HTMLPageRenderer(appearance: destination == "canvas-dark" ? .dark : .light)
                .render(page: page, framework: .standard)
        }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        defer { webView.stopLoading() }
        webView.loadHTMLString(html, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.evaluateJavaScript("document.readyState === 'complete' && !!document.querySelector('a.btn')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let failures = try #require(try await webView.evaluateJavaScript("""
            const actual = document.querySelector('a.btn');
            const expected = document.createElement('a');
            expected.href = '#';
            expected.textContent = 'Reference';
            document.body.append(expected);
            // Compare settled states without sampling either button mid-transition.
            const stableStyles = document.createElement('style');
            stableStyles.textContent = '.btn { transition: none !important; animation: none !important; }';
            document.head.append(stableStyles);
            const errors = [];
            const actualContainer = actual.parentElement;
            const referenceContainer = document.createElement('div');
            document.body.append(referenceContainer);
            const originalContainerClasses = actualContainer.className;
            for (const containerClass of ['container', 'container-fluid']) {
                actualContainer.className = containerClass;
                referenceContainer.className = containerClass;
                const a = getComputedStyle(actualContainer), b = getComputedStyle(referenceContainer);
                for (const property of ['width', 'maxWidth', 'paddingLeft', 'paddingRight', 'marginLeft', 'marginRight']) {
                    if (a[property] !== b[property]) errors.push(`${containerClass}: ${property}: ${a[property]} != ${b[property]}`);
                }
            }
            actualContainer.className = originalContainerClasses;
            referenceContainer.remove();
            if (!actual.classList.contains('btn-solid') || !actual.classList.contains('theme-primary')) {
                errors.push('Default button lacks Bootstrap 6 variant/theme');
            }
            const original = actual.className;
            const properties = ['color', 'backgroundColor', 'borderTopColor', 'borderTopWidth',
                'borderTopLeftRadius', 'paddingTop', 'paddingRight', 'fontSize', 'minHeight', 'boxShadow', 'display'];
            for (const mode of ['light', 'dark']) {
                document.documentElement.setAttribute('data-bs-theme', mode);
                for (const theme of ['primary', 'accent', 'success', 'danger', 'warning', 'info', 'inverse', 'secondary']) {
                    for (const variant of ['solid', 'subtle', 'outline']) {
                        for (const size of ['', 'btn-sm', 'btn-lg']) {
                            const classes = `btn btn-${variant} theme-${theme} ${size}`;
                            actual.className = original.split(' ').filter(c => !c.startsWith('btn') && !c.startsWith('theme-')).join(' ') + ' ' + classes;
                            expected.className = classes;
                            for (const state of ['', 'active', 'disabled']) {
                                if (state) { actual.classList.add(state); expected.classList.add(state); }
                                const a = getComputedStyle(actual), b = getComputedStyle(expected);
                                for (const property of properties) {
                                    if (a[property] !== b[property]) errors.push(`${mode}/${classes}/${state}: ${property}: ${a[property]} != ${b[property]}`);
                                }
                                if (state) { actual.classList.remove(state); expected.classList.remove(state); }
                            }
                        }
                    }
                }
            }
            errors;
            """) as? [String])
        if !failures.isEmpty { Issue.record("\(failures.prefix(20).joined(separator: "\n"))") }
    }

    @Test
    func selectedThemeVariantAndSizeReachCanvasAndExport() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var button = PartNode.make(.button)
        button.setProperty(.init(rawValue: "theme"), value: .choice("theme-danger"))
        button.setProperty(.init(rawValue: "variant"), value: .choice("btn-outline"))
        button.setProperty(.init(rawValue: "size"), value: .choice("btn-lg"))
        let page = Page(title: "Bootstrap button", slug: "index", parts: [button])
        let site = Site(name: "Buttons", pages: [page])
        let canvas = HTMLPageRenderer().render(page: page, framework: site.framework)
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html"))
        for html in [canvas, exported.contents] {
            #expect(html.contains("btn btn-outline theme-danger btn-lg"))
            #expect(!html.contains("btn-primary"))
        }
        let controls = PartType.button.definition.properties.map(\.key.rawValue)
        #expect(Set(controls) == Set(["label", "destination", "theme", "variant", "size", "accessibilityLabel"]))
    }
}
