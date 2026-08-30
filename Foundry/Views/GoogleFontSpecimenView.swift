import SwiftUI
import WebKit

struct GoogleFontSpecimenView: NSViewRepresentable {
    let family: String
    let stylesheetURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.setAccessibilityLabel("\(family) font preview")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let key = family + "|" + (stylesheetURL?.absoluteString ?? "")
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        webView.setAccessibilityLabel("\(family) font preview")
        webView.stopLoading()
        webView.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        let escapedFamily = family.htmlEscaped
        let stylesheet = stylesheetURL.map {
            "<link rel=\"stylesheet\" href=\"\($0.absoluteString.htmlEscaped)\">"
        } ?? ""
        return """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            \(stylesheet)
            <style>
                * { box-sizing: border-box; }
                html, body { margin: 0; min-height: 100%; background: transparent; }
                body {
                    color: CanvasText;
                    font-family: '\(escapedFamily)', sans-serif;
                    padding: 28px;
                }
                h1 { font-size: 32px; margin: 0 0 34px; }
                .label { font: 13px system-ui; margin-bottom: 8px; }
                .specimen {
                    border: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
                    border-radius: 8px;
                    font-size: 36px;
                    line-height: 1.22;
                    padding: 12px;
                    overflow-wrap: anywhere;
                }
            </style>
        </head>
        <body>
            <h1>\(escapedFamily)</h1>
            <div class="label">Normal</div>
            <div class="specimen">ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>abcdefghijklmnopqrstuvwxyz<br>1234567890</div>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedKey: String?
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
