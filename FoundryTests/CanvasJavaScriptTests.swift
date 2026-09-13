import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasJavaScriptTests {
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
