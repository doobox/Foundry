import Foundation
import WebKit
@testable import Foundry

/// Real WebKit loads against the loopback server; no external website/network.
@MainActor
final class PreviewBrowserProbe: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768))
    private var pending: CheckedContinuation<Void, any Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) async throws -> Duration {
        let start = ContinuousClock.now
        try await withCheckedThrowingContinuation { continuation in
            begin(continuation)
            webView.load(URLRequest(url: url))
        }
        return start.duration(to: .now)
    }

    func navigate(server: PreviewServer, sessionID: UUID, target: String) async throws -> Duration {
        let start = ContinuousClock.now
        let navigation = Task { await server.navigatePreview(sessionID: sessionID, to: target) }
        try await withCheckedThrowingContinuation { continuation in
            begin(continuation)
        }
        let loadDuration = start.duration(to: .now)
        guard await navigation.value else { throw URLError(.cannotConnectToHost) }
        return loadDuration
    }

    private func begin(_ continuation: CheckedContinuation<Void, any Error>) {
        pending = continuation
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.webView.stopLoading()
            self?.finish(.failure(URLError(.timedOut)))
        }
    }

    private func finish(_ result: Result<Void, any Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
}
