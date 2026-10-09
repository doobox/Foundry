import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapParagraphTests {
    @Test func paragraphHasOnlyNativeControlsAndNoAuthoredCSS() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let definition = PartType.paragraph.definition
        let package = try #require(definition.package)
        try package.preparePayload()
        #expect(package.css.isEmpty)
        #expect(package.instanceJavaScript.isEmpty)
        #expect(definition.allowsChildren == false)
        #expect(package.manifest.resolvedProperties.map(\.id) == [
            "typography.textSize", "typography.textAlignment", "typography.textWrap",
            "spacing.margin", "spacing.padding"
        ])
        let group = PartPackageControlGroup(type: .typography, id: "type")
        #expect(group.properties.count == 11)
        #expect(group.properties.filter(\.responsive).map(\.id) == ["type.textAlignment"])
        var values: [String: PartPackageValue] = ["type.textAlignment": .string("text-start md:text-center")]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        #expect(values["type.classes"] == .string("text-start md:text-center"))
        #expect(values["type.css"] == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"], [375, 800])
    func paragraphMatchesHandwrittenBootstrap(destination: String, width: Int) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var paragraph = PartNode.make(.paragraph)
        paragraph.anchor = "paragraph-test"
        paragraph.setProperty(.init(rawValue: "content"), value: .string("Text <safe> & editable"))
        paragraph.setProperty(.init(rawValue: "typography.textSize"), value: .choice("text-sm"))
        paragraph.setProperty(.init(rawValue: "typography.textAlignment"), value: .choice("text-start"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.textAlignment"), value: .choice("text-center"), at: .medium)
        paragraph.setProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-pretty"))
        let page = Page(title: "Paragraph", slug: "index", parts: [paragraph])
        let initial = try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en",
            framework: .standard, assets: [:], breakpoint: .medium, packageRevision: 0, previous: nil)
        let html: String
        if destination == "canvas" {
            guard case .page(let document) = initial.result else { Issue.record("Expected canvas document"); return }
            html = document
            #expect(html.contains("data-foundry-inline-property=\"content\""))
        } else {
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published)
                .render(site: Site(name: "Paragraph", pages: [page]))
            #expect(bundle.errors.isEmpty)
            let document = try #require(bundle.file(at: "index.html")?.contents)
            #expect(document.contains("data-foundry-") == false)
            #expect(document.contains("foundry-package-") == false)
            #expect(document.contains("Text &lt;safe&gt; &amp; editable"))
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 600), configuration: configuration)
        let navigation = ParagraphNavigation()
        defer { web.stopLoading() }
        try await navigation.load(html, in: web)
        let errors = try await web.evaluateJavaScript("""
            (() => {
                const actual=document.getElementById('paragraph-test'), errors=[];
                if(actual.tagName!=='P') errors.push('Not a paragraph');
                if(actual.textContent!=='Text <safe> & editable') errors.push('Text editing value lost');
                const reference=document.createElement('p');
                reference.className='text-sm text-start md:text-center text-pretty';
                reference.textContent=actual.textContent;
                actual.after(reference);
                for(const mode of ['light','dark']) {
                    document.documentElement.dataset.bsTheme=mode;
                    for(const direction of ['ltr','rtl']) {
                        document.documentElement.dir=direction;
                        const a=getComputedStyle(actual), b=getComputedStyle(reference);
                        for(const key of ['display','fontSize','lineHeight','fontFamily','color','textAlign','textWrap','marginTop','marginBottom']) {
                            if(a[key]!==b[key]) errors.push(mode+'/'+direction+'/'+key+': '+a[key]+' != '+b[key]);
                        }
                    }
                }
                reference.remove();
                document.documentElement.dir='ltr';
                return errors;
            })()
            """) as? [String]
        #expect(errors == [])
        let alignment = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).textAlign") as? String
        #expect(alignment == (width == 800 ? "center" : "start"))

        if destination == "canvas" && width == 800 {
            var edited = page
            let key = PartProperty.Key(rawValue: "typography.textAlignment")
            var previous = initial.scene
            for (revision, value) in ["text-end", "none"].enumerated() {
                if value == "none" {
                    edited.parts[0].removeResponsiveOverride(key, at: .medium)
                } else {
                    edited.parts[0].setResponsiveProperty(key, value: .choice(value), at: .medium)
                }
                let result = try CanvasScene.render(renderer: HTMLPageRenderer(), page: edited, language: "en",
                    framework: .standard, assets: [:], breakpoint: .medium, packageRevision: 0, previous: previous,
                    consecutiveImpact: .partProperty(partID: paragraph.id, propertyKey: key))
                guard case .scene(let update) = result.result else { Issue.record("Expected live patch"); return }
                let applied = try await web.callAsyncJavaScript(
                    "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                    arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                        "roots": update.roots as Any? ?? NSNull(), "revision": revision + 1,
                        "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                    in: nil, contentWorld: .defaultClient)
                try #require(applied as? Bool == true)
                #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).textAlign") as? String == (value == "none" ? "start" : "end"))
                previous = result.scene
            }
        }
    }
}

@MainActor
private final class ParagraphNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String, in web: WKWebView) async throws {
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
