import Foundation
import WebKit

/// AppKit swatches and numeric colour channels use browser-resolved sRGB
/// previews. Export retains the exact same CSS expressions, not these previews.
@MainActor
final class BootstrapScalePreviewResolver: NSObject, WKNavigationDelegate {
    private let view = WKWebView(frame: .zero)
    private var continuation: CheckedContinuation<Void, any Error>?

    func resolve(_ scale: BootstrapColourScale) async throws -> [String] {
        try await resolve(expressions: ColourShade.allCases.map(scale.expression))
    }

    func resolve(expressions: [String], css: String = ":root{--bs-white:#fff;--bs-black:#000}", mode: String = "light") async throws -> [String] {
        try Task.checkCancellation()
        view.navigationDelegate = self
        defer { view.stopLoading(); view.navigationDelegate = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                view.loadHTMLString("<html data-bs-theme='\(mode)'><head><style>\(css)</style></head><body></body></html>", baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        let result = try await view.callAsyncJavaScript("""
            const probe = document.createElement('span'); document.body.append(probe);
            const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
            const context = canvas.getContext('2d', {colorSpace:'srgb'});
            return expressions.map(expression => {
                if (!CSS.supports('color', expression)) throw new Error('Unsupported colour');
                probe.style.color = expression;
                context.clearRect(0,0,1,1);
                context.fillStyle = getComputedStyle(probe).color;
                context.fillRect(0,0,1,1);
                return '#' + Array.from(context.getImageData(0,0,1,1).data).slice(0,3)
                    .map(v => v.toString(16).padStart(2,'0')).join('').toUpperCase();
            });
            """, arguments: ["expressions": expressions], in: nil, contentWorld: .defaultClient)
        try Task.checkCancellation()
        guard let shades = result as? [String], shades.count == expressions.count else { throw CocoaError(.coderReadCorrupt) }
        return shades
    }

    private func finish(_ result: Result<Void, any Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CocoaError(.coderReadCorrupt))) }
}
