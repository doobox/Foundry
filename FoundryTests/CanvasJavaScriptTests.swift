import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasJavaScriptTests {
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
                  && document.querySelector('[data-foundry-id="test-component"]').textContent === 'Example'
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
        <body><div data-foundry-id="test-component">Example</div></body></html>
        """
    }
}
