import Foundation
import Testing
import WebKit
@testable import Foundry

/// Pasting must cost the same whether the page holds ten instances or a
/// thousand. These pin the work a single paste is allowed to do — the
/// instances it examines, the shells it republishes and the DOM it disturbs —
/// because every one of those was previously proportional to the page.
@MainActor
struct CanvasPasteLatencyTests {
    private func fixture() throws -> LoadedPartPackage {
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data("""
        {"minimumAPIVersion":1,"id":"test.paste.\(UUID().uuidString.lowercased())","title":"Paste",
         "version":"1.0.0","group":"Layout","description":"Test",
         "inspector":[{"type":"number","id":"width","responsive":true,"defaults":{"base":100}}],
         "templates":{"html":"part.html"}}
        """.utf8))
        return LoadedPartPackage(manifest: manifest, rootURL: URL(fileURLWithPath: "/tmp/paste-fixture"),
            htmlTemplate: "<section {{ part.attributes }}>{{ dropZone(\"content\") }}</section>",
            css: ":instance { width: {{ control.width }}px; }", pageCSS: "", siteCSS: "", placedHTML: [],
            instanceJavaScript: "", pageJavaScript: "", instancePHP: "", pagePHP: "", editorCSS: "",
            updateSourceURL: nil, imageMetadata: [:])
    }

    private func milliseconds(_ body: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try body()
        return Double((ContinuousClock.now - start).components.attoseconds) / 1e15
    }

    @Test(.timeLimit(.minutes(3)), arguments: [25, 100, 400])
    func pasteCostDoesNotGrowWithPageSize(_ count: Int) async throws {
        let package = try fixture()
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let type = PartType(rawValue: package.manifest.identifier)
        var parent = PartNode.make(type)
        parent.children = (0..<count).map { _ in PartNode.make(type) }
        var page = Page(title: "Paste", slug: "index", parts: [parent])
        let cache = CanvasRenderCache()
        func render(_ previous: CanvasScene?,
                    impact: ProjectMutationImpact? = nil) throws -> (scene: CanvasScene, result: CanvasRenderResult) {
            try CanvasScene.render(renderer: HTMLPageRenderer(artifactCache: cache), page: page,
                language: "en", theme: .standard, assets: [:], breakpoint: .mobile,
                packageRevision: 0, previous: previous, consecutiveImpact: impact)
        }

        let initial = try render(nil)
        guard case .page(let document) = initial.result else { Issue.record("Missing document"); return }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        defer { web.stopLoading() }
        web.loadHTMLString(document, baseURL: nil)
        var ready = false
        for _ in 0..<400 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryApplyScene === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)

        // Consecutive pastes into the populated parent, as fast as the editor
        // can issue them. The first is cold; the rest are the steady state a
        // person feels when holding down paste.
        var scene = initial.scene
        var report: [String] = []
        for step in 1...4 {
            page.parts[0].children.append(PartNode.make(type))
            let impact = ProjectMutationImpact.partStructure(ownerID: page.parts[0].id)
            var pasted: (scene: CanvasScene, result: CanvasRenderResult)?
            let nativeMilliseconds = try milliseconds { pasted = try render(scene, impact: impact) }
            scene = try #require(pasted).scene
            guard case .scene(let update) = try #require(pasted).result else {
                Issue.record("Paste \(step) fell back to a full document render at N=\(count)")
                return
            }

            // The new part and its parent — never a pass over the page.
            #expect(scene.examinedInstanceCount <= 2,
                "Paste \(step) examined \(scene.examinedInstanceCount) instances at N=\(count)")
            #expect(scene.renderedInstanceCount <= 2,
                "Paste \(step) rendered \(scene.renderedInstanceCount) shells at N=\(count)")
            // The parent keeps its element, so only the new part's markup ships.
            #expect(update.html.count == 1,
                "Paste \(step) republished \(update.html.count) shells at N=\(count)")
            #expect(update.childMoves.values.reduce(0) { $0 + $1.count } == 1,
                "Paste \(step) moved more than the new child at N=\(count)")
            #expect(update.styleMoves.count <= 1,
                "Paste \(step) re-seated \(update.styleMoves.count) stylesheets at N=\(count)")

            let applyMilliseconds = try await web.callAsyncJavaScript("""
                const start = performance.now();
                const applied = window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves);
                if (!applied) return null;
                document.body.getBoundingClientRect();
                return performance.now() - start;
                """, arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                    "roots": update.roots as Any? ?? NSNull(), "revision": step,
                    "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                in: nil, contentWorld: .defaultClient) as? Double
            let applied = try #require(applyMilliseconds, "Paste \(step) was rejected at N=\(count)")
            report.append("#\(step) native=\(String(format: "%.2f", nativeMilliseconds))ms "
                + "apply=\(String(format: "%.2f", applied))ms")
        }
        Attachment.record(report.joined(separator: "\n"), named: "paste-latency-\(count).txt")
    }
}
