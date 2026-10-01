import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasHoverGuardTests {
    @Test(.timeLimit(.minutes(1)))
    func canvasExitDisablesStaleHoverAndReentryRestoresIt() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let webView = CanvasWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString("""
            <html><head><style>
            .card { background: red }
            @media (min-width: 0px) { .card:hover { background: blue } }
            [data-text=":hover"] { color: green }
            </style></head><body><div class="card" data-foundry-id="card">Card</div></body></html>
            """, baseURL: nil)
        let deadline = ContinuousClock.now + .seconds(10)
        var ready = false
        while ContinuousClock.now < deadline {
            ready = (try? await webView.callAsyncJavaScript(
                "return typeof window.foundryClearHoverChrome === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            await Task.yield()
        }
        try #require(ready)
        let installed = try await webView.callAsyncJavaScript(#"""
            const rules = document.styleSheets[0].cssRules;
            const rule = rules[1].cssRules[0];
            const protectedSelector = rule.selectorText;
            // Force a persistent match to model WebKit retaining :hover after exit.
            // This tests actual computed CSS, not just the editor's outline state.
            rule.selectorText = protectedSelector.replace(':hover', '.stale-hover');
            document.querySelector('.card').classList.add('stale-hover');
            return protectedSelector.includes('data-foundry-pointer-outside')
              && !rules[2].selectorText.includes('data-foundry-pointer-outside')
              && getComputedStyle(document.querySelector('.card')).backgroundColor === 'rgb(0, 0, 255)';
            """#, arguments: [:], in: nil, contentWorld: .defaultClient)
        try #require(installed as? Bool == true)
        await webView.clearHoverChrome().value
        let cleared = try await webView.callAsyncJavaScript("""
            return getComputedStyle(document.querySelector('.card')).backgroundColor === 'rgb(255, 0, 0)';
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(cleared as? Bool == true)
        let restored = try await webView.callAsyncJavaScript("""
            document.querySelector('.card').dispatchEvent(new PointerEvent('pointermove', { bubbles: true }));
            return getComputedStyle(document.querySelector('.card')).backgroundColor === 'rgb(0, 0, 255)';
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(restored as? Bool == true)
        let patched = try await webView.callAsyncJavaScript("""
            const style = document.createElement('style');
            style.textContent = '.card:hover::before { content: "hover" }';
            document.head.appendChild(style);
            await Promise.resolve();
            return style.sheet.cssRules[0].selectorText.includes('data-foundry-pointer-outside');
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(patched as? Bool == true)
        await webView.clearHoverChrome().value
        let reconciled = try await webView.callAsyncJavaScript("""
            const updated = window.foundryReplaceDocument('<html><head><style>.card:hover { color: red }</style></head><body><div class="card" data-foundry-id="card">Updated</div></body></html>');
            await Promise.resolve();
            return updated && document.documentElement.hasAttribute('data-foundry-pointer-outside')
              && [...document.styleSheets].some(sheet => [...sheet.cssRules].some(rule => rule.selectorText?.includes('data-foundry-pointer-outside')));
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(reconciled as? Bool == true)
    }
}
