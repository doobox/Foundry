import SwiftUI
import WebKit
import CryptoKit

struct GoogleFontSpecimenView: NSViewRepresentable {
    let family: String
    let stylesheetURL: URL?
    var fontContent: ProjectAssetContent? = nil
    var weight: Int = 400
    var italic: Bool = false
    var includedFaces: [GoogleFontFace]? = nil

    nonisolated static func specimenFaces(_ faces: [GoogleFontFace]) -> [GoogleFontFace] {
        faces.flatMap { face in
            guard face.isVariable else { return [face] }
            let weights = Set([face.minimum, min(face.maximum, max(face.minimum, 400)), face.maximum])
            return weights.sorted().map { GoogleFontFace(italic: face.italic, minimum: $0, maximum: $0) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = fontContent != nil
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.fontHandler, forURLScheme: "foundry-font-preview")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .windowBackgroundColor
        webView.setAccessibilityLabel("\(family) font preview")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let digest = fontContent.map { ($0.digest ?? Data(SHA256.hash(data: $0.data))).base64EncodedString() } ?? ""
        let key = family + "|" + (stylesheetURL?.absoluteString ?? "") + "|" + digest + "|\(weight)|\(italic)" + (includedFaces?.map(\.id).joined(separator: "|") ?? "")
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        context.coordinator.fontHandler.content = fontContent
        webView.setAccessibilityLabel("\(family) font preview")
        webView.stopLoading()
        webView.loadHTMLString(html, baseURL: URL(string: "foundry-font-preview://specimen/"))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.fontHandler.content = nil
        coordinator.loadedKey = nil
        // Replace the document so WebKit no longer has a live face referencing
        // the selected font, even if it keeps its process around for reuse.
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }

    private var html: String {
        let escapedFamily = family.htmlEscaped
        let cssFamily = fontContent == nil ? escapedFamily : "FoundryUploadedSpecimen"
        let fontFace = fontContent == nil ? "" : "@font-face { font-family: 'FoundryUploadedSpecimen'; src: url('foundry-font-preview://specimen/font'); }"
        let stylesheet = stylesheetURL.map {
            "<link rel=\"stylesheet\" href=\"\($0.absoluteString.htmlEscaped)\">"
        } ?? ""
        let faces = includedFaces.map(Self.specimenFaces) ?? [.init(italic: italic, minimum: weight, maximum: weight)]
        let specimens = faces.map { face in
            """
            <section style="font-weight: \(face.minimum); font-style: \(face.italic ? "italic" : "normal")">
                \(includedFaces == nil ? "" : "<h2>\(face.title)</h2>")
                <div class="sample">Aa Bb Cc</div>
                <p class="sentence">The quick brown fox jumps over the lazy dog.</p>
                <div class="specimen">ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>abcdefghijklmnopqrstuvwxyz<br>1234567890</div>
            </section>
            """
        }.joined()
        return """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            \(stylesheet)
            <style>
                \(fontFace)
                * { box-sizing: border-box; }
                html, body { margin: 0; min-height: 100%; background: transparent; }
                body {
                    color: CanvasText;
                    font-family: '\(cssFamily)', sans-serif;
                    font-weight: \(min(1000, max(1, weight)));
                    font-style: \(italic ? "italic" : "normal");
                    padding: 16px;
                    overflow-wrap: anywhere;
                }
                h1 { font-size: 20px; font-weight: inherit; line-height: 1.2; margin: 0 0 12px; }
                h2 { font: 12px system-ui; opacity: 0.7; margin: 0 0 10px; }
                section { margin-bottom: 28px; }
                .sample { font-size: 28px; line-height: 1.2; margin: 0 0 12px; }
                .sentence { font-size: 15px; line-height: 1.35; margin: 0 0 12px; }
                .specimen {
                    font-size: 12px;
                    line-height: 1.4;
                    opacity: 0.7;
                    overflow-wrap: anywhere;
                }
            </style>
        </head>
        <body>
            <h1>\(escapedFamily)</h1>
            \(specimens)
            \(fontContent == nil ? "" : "<script>document.fonts.load('15px FoundryUploadedSpecimen').catch(() => { document.body.textContent = 'This font file could not be previewed.'; });</script>")
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedKey: String?
        let fontHandler = FontPreviewSchemeHandler()
    }
}

@MainActor
final class FontPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    var content: ProjectAssetContent?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "specimen", url.path == "/font",
              let content else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": content.asset.mediaType,
            "Content-Length": String(content.data.count),
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*"
        ])!
        task.didReceive(response)
        task.didReceive(content.data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Responses are delivered synchronously; no pending work to cancel.
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
