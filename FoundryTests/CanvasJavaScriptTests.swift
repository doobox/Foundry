import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasJavaScriptTests {
    @Test(.timeLimit(.minutes(1)))
    func builtInFlexColumnsLayOutAtBaseAndMediumIncludingNestedColumns() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var inner = PartNode.make(.columns)
        inner.setResponsiveProperty(.init(rawValue: "columnCount"), value: .number(3), at: .medium)
        inner.children = (0..<3).map { _ in PartNode.make(.spacer) }
        var outer = PartNode.make(.columns)
        outer.children = [inner, .make(.spacer)]
        let page = Page(title: "Flex test", slug: "index", parts: [outer])
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        defer { webView.stopLoading() }
        for breakpoint in [ResponsiveBreakpoint.mobile, .medium] {
            let html = HTMLPageRenderer().render(page: page, language: "en", theme: .standard, assets: [:], breakpoint: breakpoint)
            webView.loadHTMLString(html.replacingOccurrences(of: "<html ", with: "<html data-layout-test=\"\(breakpoint.rawValue)\" "), baseURL: nil)
            var ready = false
            for _ in 0..<200 {
                ready = (try? await webView.evaluateJavaScript("document.readyState === 'complete' && document.documentElement.dataset.layoutTest === '\(breakpoint.rawValue)' && document.querySelectorAll('.foundry-columns').length === 2")) as? Bool == true
                if ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(ready)
            let measurements = try #require(try await webView.evaluateJavaScript("""
                (() => {
                  const outer = document.querySelector('.foundry-columns');
                  const inner = outer.children[0];
                  return [outer.getBoundingClientRect().width, inner.getBoundingClientRect().width,
                    parseFloat(getComputedStyle(outer).columnGap), inner.children[0].getBoundingClientRect().width,
                    parseFloat(getComputedStyle(inner).columnGap)];
                })()
                """) as? [Double])
            if breakpoint == .mobile {
                #expect(abs(measurements[0] - measurements[1]) < 1)
            } else {
                #expect(abs(measurements[0] - (measurements[1] * 2 + measurements[2])) < 1)
                #expect(abs(measurements[1] - (measurements[3] * 3 + measurements[4] * 2)) < 1)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func selectionChromeTracksLateContentResizing() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer { webView.stopLoading(); window.close() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundrySetSelection === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        _ = try await webView.callAsyncJavaScript("""
            const part = document.querySelector('[data-foundry-id]');
            part.dataset.foundryName = 'Example';
            part.style.cssText = 'box-sizing:content-box;width:100px;height:100px;border:10px solid red;border-radius:20px';
            part.dispatchEvent(new PointerEvent('pointermove', { bubbles: true }));
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        var titleAligned = false
        for _ in 0..<80 {
            titleAligned = (try? await webView.callAsyncJavaScript("""
                const host = document.querySelector('[data-foundry-editor-chrome="host"]');
                const title = host.shadowRoot.querySelector('[data-foundry-editor-chrome="title"]');
                return title.style.display === 'block'
                  && title.style.left === '68px' && title.style.top === '19.5px'
                  && title.style.transform === 'translate(-50%, -50%)'
                  && title.style.maxWidth === '100px'
                  && getComputedStyle(title).borderRadius === '999px';
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if titleAligned { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(titleAligned)
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('[data-foundry-id]').style.cssText = ''",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = try await webView.callAsyncJavaScript(
            "window.foundrySetSelection(['test-part'], {}, false)",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        try await Task.sleep(for: .milliseconds(100))
        // Emulate asynchronous text reflow after the initial chrome update.
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('[data-foundry-id]').style.height = '120px'",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        var aligned = false
        for _ in 0..<80 {
            aligned = (try? await webView.callAsyncJavaScript("""
                const part = document.querySelector('[data-foundry-id]');
                const outline = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot
                  .querySelector('[data-foundry-editor-chrome="selection"]');
                return outline && Math.abs(parseFloat(outline.style.height) - part.getBoundingClientRect().height) < 1;
                """, arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if aligned { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(aligned)
    }

    @Test(.timeLimit(.minutes(1)))
    func pendingFontStylesheetKeepsCanvasLayoutAndBodyIntact() async throws {
        let handler = DelayedCanvasFontStylesheet()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "canvas-font-test")
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { handler.finish(); webView.stopLoading() }
        let page = Page(title: "Font test", slug: "index", parts: (0..<30).map { _ in PartNode.make(.paragraph) })
        var theme = Theme.standard
        let renderer = HTMLPageRenderer()
        webView.loadHTMLString(renderer.render(page: page, theme: theme), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        _ = try await webView.callAsyncJavaScript("""
            window.probePart = document.querySelector('[data-foundry-id]');
            window.probeReplacements = 0;
            const original = document.body.replaceChildren;
            document.body.replaceChildren = function(...nodes) {
              window.probeReplacements++;
              return original.apply(this, nodes);
            };
            window.scrollTo(0, 300);
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        theme.typography.bodyFont.source = .remote(stylesheetURL: URL(string: "canvas-font-test://font/styles.css")!)
        _ = try await webView.callAsyncJavaScript(
            "return window.foundryReplaceDocument(html)",
            arguments: ["html": renderer.render(page: page, theme: theme)], in: nil, contentWorld: .defaultClient)
        for _ in 0..<200 {
            if handler.hasPendingRequest { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(handler.hasPendingRequest)
        let result = try await webView.callAsyncJavaScript("""
            return { boxSizing: getComputedStyle(window.probePart).boxSizing,
              samePart: window.probePart === document.querySelector('[data-foundry-id]'),
              replacements: window.probeReplacements, scrollY: window.scrollY };
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("PENDING FONT PROBE: \(measurements)")
        #expect(measurements["boxSizing"] as? String == "border-box")
        #expect(measurements["samePart"] as? Bool == true)
        #expect(measurements["replacements"] as? Int == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func stylesheetOnlyUpdatePreservesBodyNodes() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let result = try await webView.callAsyncJavaScript("""
            const part = document.querySelector('[data-foundry-id="test-part"]');
            let replacements = 0;
            const original = document.body.replaceChildren;
            document.body.replaceChildren = function(...nodes) {
              replacements++;
              return original.apply(this, nodes);
            };
            const updated = window.foundryReplaceDocument(html);
            return { updated, replacements,
              samePart: part === document.querySelector('[data-foundry-id="test-part"]') };
            """, arguments: ["html": page(colour: "#ABCDEF")], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("STYLESHEET-ONLY PROBE: \(measurements)")
        #expect(measurements["updated"] as? Bool == true)
        #expect(measurements["replacements"] as? Int == 0)
        #expect(measurements["samePart"] as? Bool == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func structuralUpdatesDoNotLeaveDuplicateOrRemovedParts() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        func part(_ id: String, _ contents: String) -> String {
            "<article data-foundry-id=\"\(id)\"><div class=\"slot\">\(contents)</div></article>"
        }
        let empty = "<div class=\"foundry-empty-drop-zone\">Drop part here</div>"
        let child = part("third-party-child", empty)
        let parent = "third-party-parent"
        let initial = part(parent, empty) + child
        webView.loadHTMLString("<html><body>\(initial)</body></html>", baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        // Nest, unnest, reorder, add and delete arbitrary part identities.
        let bodies = [part(parent, child), initial, child + part(parent, empty),
                      part(parent, part("another-wrapper", child)),
                      part(parent, empty), ""]
        for body in bodies {
            let matches = try await webView.callAsyncJavaScript("""
                const html = '<html><body>' + body + '</body></html>';
                const expected = new DOMParser().parseFromString(html, 'text/html');
                const signature = root => [...root.querySelectorAll('[data-foundry-id]')].map(element => [
                  element.dataset.foundryId,
                  element.parentElement.closest('[data-foundry-id]')?.dataset.foundryId ?? null
                ]);
                window.foundryReplaceDocument(html);
                return JSON.stringify(signature(document)) === JSON.stringify(signature(expected))
                  && document.querySelectorAll('.foundry-empty-drop-zone').length === expected.querySelectorAll('.foundry-empty-drop-zone').length;
                """, arguments: ["body": body], in: nil, contentWorld: .defaultClient)
            #expect(matches as? Bool == true, "Canvas must match the authoritative part hierarchy")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func liveThemeUpdatesCompleteWithoutReloadingDocument() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString(page(colour: "#123456"), baseURL: nil)

        var ready = false
        for _ in 0..<200 {
            ready = (try? await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient
            )) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready, "The real canvas interaction script must be installed")

        // A reload would discard this client-world state. Reconcile several successive
        // theme shades, as happens while changing a colour or dragging Soften.
        _ = try await webView.callAsyncJavaScript(
            "window.canvasTestSentinel = {}; window.originalCanvasTestSentinel = window.canvasTestSentinel",
            arguments: [:], in: nil, contentWorld: .defaultClient
        )
        for colour in ["#ABCDEF", "#556677", "#223344"] {
            let result = try await webView.callAsyncJavaScript(
                """
                const updated = window.foundryReplaceDocument(html);
                return updated === true
                  && document.querySelector('#theme').textContent.includes(colour)
                  && document.querySelector('[data-foundry-id="test-part"]').textContent === 'Example'
                  && window.canvasTestSentinel !== undefined
                  && window.canvasTestSentinel === window.originalCanvasTestSentinel;
                """,
                arguments: ["html": page(colour: colour), "colour": colour],
                in: nil, contentWorld: .defaultClient
            )
            #expect(result as? Bool == true)
        }
    }

    private func page(colour: String) -> String {
        """
        <!doctype html><html><head><style id="theme">:root { --foundry-color-accent: \(colour); }</style></head>
        <body><div data-foundry-id="test-part">Example</div></body></html>
        """
    }
}

@MainActor
private final class DelayedCanvasFontStylesheet: NSObject, WKURLSchemeHandler {
    private var tasks: [any WKURLSchemeTask] = []
    var hasPendingRequest: Bool { !tasks.isEmpty }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        tasks.append(urlSchemeTask)
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeAll { $0 === urlSchemeTask }
    }
    func finish() {
        let pending = tasks
        tasks.removeAll()
        for task in pending {
            task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/css", expectedContentLength: 0, textEncodingName: "utf-8"))
            task.didReceive(Data())
            task.didFinish()
        }
    }
}
