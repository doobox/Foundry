import WebKit

@MainActor
final class BootstrapTokenBrowser: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private var continuation: CheckedContinuation<Void, any Error>?
    func load(_ html: String) async throws {
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation {
            continuation = $0
            web.loadHTMLString(html, baseURL: nil)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CocoaError(.coderReadCorrupt))) }
    private func finish(_ result: Result<Void, any Error>) { let pending = continuation; continuation = nil; pending?.resume(with: result) }
}
