import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapCardTests {
    private let card = PartType(rawValue: "foundry.content.card")

    @Test
    func defaultCardIsNativeBootstrapMarkupInCanvasAndExport() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let node = PartNode.make(card)
        let page = Page(title: "Card", slug: "index", parts: [node])
        let site = Site(name: "Cards", pages: [page])
        let canvas = HTMLPageRenderer().render(page: page, framework: site.framework)
        let bundle = StaticSiteRenderer().render(site: site)
        #expect(bundle.errors.isEmpty)
        let exported = try #require(bundle.file(at: "index.html")?.contents)
        // Only the rendered part tree matters on the canvas; the surrounding page carries editor support.
        let rootsStart = try #require(canvas.range(of: "<!--foundry-roots-start-->")).upperBound
        let rootsEnd = try #require(canvas.range(of: "<!--foundry-roots-end-->")).lowerBound
        let canvasRoots = String(canvas[rootsStart..<rootsEnd])
        for html in [canvasRoots, exported] {
            #expect(html.contains("class=\"card"))
            #expect(html.contains("card-body"))
            #expect(html.contains("card-title"))
            #expect(html.contains("card-text"))
            #expect(html.contains("btn btn-solid theme-primary"))
            #expect(html.contains("card-header") == false, "\(html)")
            #expect(html.contains("card-row") == false, "\(html)")
        }
        #expect(exported.contains("<div class=\"card-body\">"))
        #expect(exported.contains("<h3 class=\"card-title\">"))
        #expect(exported.contains("<p class=\"card-text\">"))
        // The canvas offers an image drop target; the published page omits the empty image entirely.
        #expect(canvasRoots.contains("data-foundry-image-drop-zone"), "\(canvasRoots)")
        #expect(exported.contains("<img") == false)
        #expect(exported.contains("data-foundry-") == false)
        #expect(exported.contains("foundry-empty-drop-zone") == false)
        // The card root must not carry a theme class unless the author turns one on.
        let rootClass = try #require(exported.range(of: "class=\"card[^\"]*\"", options: .regularExpression)).lowerBound
        let root = String(exported[rootClass...].prefix(80))
        #expect(root.contains("theme-") == false)
    }

    @Test
    func appearanceAndLayoutChoicesReachTheExport() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(card)
        node.setProperty(.init(rawValue: "style"), value: .choice("card-subtle"))
        node.setProperty(.init(rawValue: "useTheme"), value: .boolean(true))
        node.setProperty(.init(rawValue: "theme"), value: .choice("theme-success"))
        node.setProperty(.init(rawValue: "imagePlacement"), value: .choice("start"))
        node.setProperty(.init(rawValue: "showHeader"), value: .boolean(true))
        node.setProperty(.init(rawValue: "showButton"), value: .boolean(false))
        node.setProperty(.init(rawValue: "typography.textAlignment"), value: .choice("text-center"))
        let page = Page(title: "Card", slug: "index", parts: [node])
        let site = Site(name: "Cards", pages: [page])
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(exported.contains("card card-subtle theme-success card-row"))
        #expect(exported.contains("text-center"))
        #expect(exported.contains("<div class=\"card-header\">"))
        #expect(exported.contains("btn ") == false)

        var buttoned = PartNode.make(card)
        buttoned.setProperty(.init(rawValue: "buttonTheme"), value: .choice("theme-danger"))
        buttoned.setProperty(.init(rawValue: "buttonVariant"), value: .choice("btn-outline"))
        buttoned.setProperty(.init(rawValue: "imagePlacement"), value: .choice("end"))
        let buttonPage = Page(title: "Card", slug: "index", parts: [buttoned])
        let buttonHTML = try #require(StaticSiteRenderer().render(site: Site(name: "Cards", pages: [buttonPage])).file(at: "index.html")?.contents)
        #expect(buttonHTML.contains("btn btn-outline theme-danger"))
        #expect(buttonHTML.contains("card-row"))
        #expect(buttonHTML.contains("card-subtle") == false)

        var inBody = PartNode.make(card)
        inBody.setProperty(.init(rawValue: "imagePlacement"), value: .choice("body"))
        let inBodyPage = Page(title: "Card", slug: "index", parts: [inBody])
        let inBodyCanvas = HTMLPageRenderer().render(page: inBodyPage, framework: .standard)
        // An in-body image sits inside the padded area, before the title, as Bootstrap's card-img example does.
        let bodyStart = try #require(inBodyCanvas.range(of: "<div class=\"card-body\">")).upperBound
        let imageSpot = try #require(inBodyCanvas[bodyStart...].range(of: "class=\"card-img")).lowerBound
        let titleSpot = try #require(inBodyCanvas[bodyStart...].range(of: "card-title")).lowerBound
        #expect(imageSpot < titleSpot)

        let controls = card.definition.properties.map(\.key.rawValue)
        for expected in ["hero", "imagePlacement", "showHeader", "showButton", "destination", "buttonTheme", "buttonVariant", "style", "useTheme", "theme", "sizing.width", "spacing.margin", "typography.textAlignment"] {
            #expect(controls.contains(expected), "missing \(expected)")
        }
        #expect(controls.contains("typography.fontWeight") == false)
        #expect(controls.contains("sizing.aspectRatio") == false)
    }

    @Test
    func cardAcceptsDroppedChildrenInsideItsBody() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        #expect(card.definition.allowsChildren)
        var node = PartNode.make(card)
        node.children = [PartNode.make(.paragraph)]
        let page = Page(title: "Card", slug: "index", parts: [node])
        let exported = try #require(StaticSiteRenderer().render(site: Site(name: "Cards", pages: [page])).file(at: "index.html")?.contents)
        let body = try #require(exported.range(of: "<div class=\"card-body\">")).upperBound
        let afterBody = exported[body...]
        let paragraph = try #require(afterBody.range(of: "<p class=\"")).lowerBound
        let button = try #require(afterBody.range(of: "<a class=\"btn")).lowerBound
        #expect(paragraph < button)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas-light", "canvas-dark", "export"])
    func cardMatchesBootstrapComponentStyles(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let node = PartNode.make(card)
        var container = PartNode.make(.container)
        container.children = [node]
        let page = Page(title: "Bootstrap card", slug: "index", parts: [container])
        let html: String
        if destination == "export" {
            let bundle = StaticSiteRenderer().render(site: Site(name: "Cards", pages: [page]))
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
            ready = (try? await webView.evaluateJavaScript("document.readyState === 'complete' && !!document.querySelector('.card > .card-body')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let failures = try #require(try await webView.evaluateJavaScript("""
            const actual = document.querySelector('.card');
            const expected = document.createElement('div');
            expected.innerHTML = '<div class="card-body"><h3 class="card-title">Reference</h3><p class="card-text">Text</p><a class="btn btn-solid theme-primary" href="#">Go</a></div>';
            document.body.append(expected);
            const stableStyles = document.createElement('style');
            stableStyles.textContent = '* { transition: none !important; animation: none !important; }';
            document.head.append(stableStyles);
            const errors = [];
            const original = actual.className;
            const cardProperties = ['backgroundColor', 'borderTopColor', 'borderTopWidth', 'borderTopLeftRadius', 'boxShadow', 'display', 'flexDirection', 'color'];
            const bodyProperties = ['paddingTop', 'paddingLeft', 'rowGap', 'display', 'flexDirection', 'color'];
            for (const mode of ['light', 'dark']) {
                document.documentElement.setAttribute('data-bs-theme', mode);
                for (const variant of ['', 'card-subtle', 'card-translucent']) {
                    for (const theme of ['', 'theme-primary', 'theme-success', 'theme-inverse']) {
                        const classes = `card ${variant} ${theme}`.trim();
                        actual.className = original.split(' ').filter(c => c !== 'card' && !c.startsWith('card-') && !c.startsWith('theme-')).join(' ') + ' ' + classes;
                        expected.className = classes;
                        const a = getComputedStyle(actual), b = getComputedStyle(expected);
                        for (const property of cardProperties) {
                            if (a[property] !== b[property]) errors.push(`${mode}/${classes}: ${property}: ${a[property]} != ${b[property]}`);
                        }
                        const ab = getComputedStyle(actual.querySelector('.card-body')), bb = getComputedStyle(expected.querySelector('.card-body'));
                        for (const property of bodyProperties) {
                            if (ab[property] !== bb[property]) errors.push(`${mode}/${classes}/body: ${property}: ${ab[property]} != ${bb[property]}`);
                        }
                    }
                }
            }
            errors;
            """) as? [String])
        if !failures.isEmpty { Issue.record("\(failures.prefix(20).joined(separator: "\n"))") }
    }
}
