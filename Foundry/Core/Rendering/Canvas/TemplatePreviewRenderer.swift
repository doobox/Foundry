import AppKit
import WebKit

/// Renders a template offscreen and captures a PNG preview for its library
/// bundle: the same HTML the canvas would show, with assets served from the
/// saving project, snapshotted once painting settles. Deterministic regardless
/// of how the template was saved or whether it was visible on screen.
@MainActor
final class TemplatePreviewRenderer {
    static let shared = TemplatePreviewRenderer()

    static let viewportWidth: CGFloat = 800
    static let snapshotWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 120
    private static let maximumHeight: CGFloat = 1400
    private static let paintSettleDelay: TimeInterval = 0.4
    private static let deadline: TimeInterval = 4

    private var activeCaptures: Set<Capture> = []

    func capturePreview(
        definition: ReusablePartDefinition,
        site: Site,
        assetContents: ProjectAssetContents,
        pageBackground: PartPackageColorValue? = nil,
        completion: @escaping @MainActor (Data?) -> Void
    ) {
        let page = Page(
            title: definition.name,
            slug: "template-preview",
            parts: [definition.root],
            backgroundOverride: pageBackground
        )
        // Previews are always light mode: baked template previews cannot track
        // the canvas appearance, so globals match them rather than diverging.
        let html = HTMLPageRenderer(site: site, appearance: .light).render(
            page: page,
            language: site.language,
            framework: site.framework,
            assets: assetContents,
            breakpoint: .extraLarge
        )
        func flattened(_ node: PartNode) -> [PartNode] {
            [node] + node.children.flatMap(flattened)
        }
        let packages = Dictionary(
            flattened(definition.root)
                .compactMap(\.type.definition.package)
                .map { ($0.manifest.identifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let capture = Capture(
            html: html,
            assetContents: assetContents,
            packages: packages,
            viewportWidth: Self.viewportWidth,
            snapshotWidth: Self.snapshotWidth,
            heightRange: Self.minimumHeight...Self.maximumHeight,
            settleDelay: Self.paintSettleDelay,
            deadline: Self.deadline
        )
        activeCaptures.insert(capture)
        capture.start { [weak self] data in
            self?.activeCaptures.remove(capture)
            completion(data)
        }
    }

    @MainActor
    private final class Capture: NSObject, WKNavigationDelegate {
        private let html: String
        private let viewportWidth: CGFloat
        private let snapshotWidth: CGFloat
        private let heightRange: ClosedRange<CGFloat>
        private let settleDelay: TimeInterval
        private let deadline: TimeInterval
        private let webView: WKWebView
        private var completion: (@MainActor (Data?) -> Void)?

        init(
            html: String,
            assetContents: ProjectAssetContents,
            packages: [String: LoadedPartPackage],
            viewportWidth: CGFloat,
            snapshotWidth: CGFloat,
            heightRange: ClosedRange<CGFloat>,
            settleDelay: TimeInterval,
            deadline: TimeInterval
        ) {
            self.html = html
            self.viewportWidth = viewportWidth
            self.snapshotWidth = snapshotWidth
            self.heightRange = heightRange
            self.settleDelay = settleDelay
            self.deadline = deadline
            let configuration = WKWebViewConfiguration()
            let schemeHandler = CanvasAssetSchemeHandler(assets: assetContents, packages: packages)
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: CanvasAssetSchemeHandler.scheme)
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: CanvasAssetSchemeHandler.packageScheme)
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: viewportWidth, height: heightRange.lowerBound * 4),
                configuration: configuration
            )
            super.init()
            webView.navigationDelegate = self
        }

        func start(completion: @escaping @MainActor (Data?) -> Void) {
            self.completion = completion
            webView.loadHTMLString(html, baseURL: nil)
            // Whatever has painted by the deadline is the preview; a template
            // must never hang the save on a slow web font.
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
                self?.snapshot()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] value, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let height = value as? Double {
                        let clamped = min(max(height, self.heightRange.lowerBound), self.heightRange.upperBound)
                        self.webView.frame.size.height = clamped
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.settleDelay) { [weak self] in
                        self?.snapshot()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(nil)
        }

        private func snapshot() {
            guard completion != nil else { return }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            configuration.snapshotWidth = NSNumber(value: Double(snapshotWidth))
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                Task { @MainActor [weak self] in
                    self?.finish(image.flatMap(Self.pngData))
                }
            }
        }

        private func finish(_ data: Data?) {
            guard let completion else { return }
            self.completion = nil
            completion(data)
        }

        private static func pngData(from image: NSImage) -> Data? {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
    }
}
