import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasJavaScriptTests {
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
        _ = try await webView.callAsyncJavaScript(
            "window.foundrySetSelection(['test-block'], {}, false)",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        try await Task.sleep(for: .milliseconds(100))
        // Emulate asynchronous text reflow after the initial chrome update.
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('[data-foundry-id]').style.height = '120px'",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        var aligned = false
        for _ in 0..<80 {
            aligned = (try? await webView.callAsyncJavaScript("""
                const block = document.querySelector('[data-foundry-id]');
                const outline = document.querySelector('[data-foundry-editor-chrome="host"]').shadowRoot
                  .querySelector('[data-foundry-editor-chrome="selection"]');
                return outline && Math.abs(parseFloat(outline.style.height) - block.getBoundingClientRect().height) < 1;
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
        let page = Page(title: "Font test", slug: "index", blocks: (0..<30).map { _ in BlockNode.make(.paragraph) })
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
            window.probeBlock = document.querySelector('[data-foundry-id]');
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
            return { boxSizing: getComputedStyle(window.probeBlock).boxSizing,
              sameBlock: window.probeBlock === document.querySelector('[data-foundry-id]'),
              replacements: window.probeReplacements, scrollY: window.scrollY };
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("PENDING FONT PROBE: \(measurements)")
        #expect(measurements["boxSizing"] as? String == "border-box")
        #expect(measurements["sameBlock"] as? Bool == true)
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
            const block = document.querySelector('[data-foundry-id="test-block"]');
            let replacements = 0;
            const original = document.body.replaceChildren;
            document.body.replaceChildren = function(...nodes) {
              replacements++;
              return original.apply(this, nodes);
            };
            const updated = window.foundryReplaceDocument(html);
            return { updated, replacements,
              sameBlock: block === document.querySelector('[data-foundry-id="test-block"]') };
            """, arguments: ["html": page(colour: "#ABCDEF")], in: nil, contentWorld: .defaultClient)
        let measurements = try #require(result as? [String: Any])
        print("STYLESHEET-ONLY PROBE: \(measurements)")
        #expect(measurements["updated"] as? Bool == true)
        #expect(measurements["replacements"] as? Int == 0)
        #expect(measurements["sameBlock"] as? Bool == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func structuralUpdatesDoNotLeaveDuplicateOrRemovedBlocks() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        func block(_ id: String, _ contents: String) -> String {
            "<article data-foundry-id=\"\(id)\"><div class=\"slot\">\(contents)</div></article>"
        }
        let empty = "<div class=\"foundry-empty-drop-zone\">Drop block here</div>"
        let child = block("third-party-child", empty)
        let parent = "third-party-parent"
        let initial = block(parent, empty) + child
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
        // Nest, unnest, reorder, add and delete arbitrary block identities.
        let bodies = [block(parent, child), initial, child + block(parent, empty),
                      block(parent, block("another-wrapper", child)),
                      block(parent, empty), ""]
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
            #expect(matches as? Bool == true, "Canvas must match the authoritative block hierarchy")
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
                  && document.querySelector('[data-foundry-id="test-block"]').textContent === 'Example'
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
        <body><div data-foundry-id="test-block">Example</div></body></html>
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
