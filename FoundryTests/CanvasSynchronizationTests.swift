import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasSynchronizationTests {
    @Test func partPatchesRequireAnAcknowledgedConsecutiveBaseline() {
        let pageID = UUID()
        let previous = CanvasRenderRequestID(pageID: pageID, mutationRevision: 10,
            assetRevision: 0, partPackageRevision: 1, breakpoint: .mobile,
            forcesReconciliation: false, appearance: .light)
        var next = CanvasRenderRequestID(pageID: pageID, mutationRevision: 11,
            assetRevision: 0, partPackageRevision: 1, breakpoint: .mobile,
            forcesReconciliation: false, appearance: .light)
        #expect(next.canPatch(after: previous, submittedRevision: 4, acknowledgedRevision: 4))
        #expect(next.shouldRender(after: previous, submittedRevision: 4, acknowledgedRevision: 3) == false)
        #expect(next.shouldRender(after: previous, submittedRevision: 4, acknowledgedRevision: 4))
        #expect(previous.shouldRender(after: previous, submittedRevision: 4, acknowledgedRevision: 4) == false)
        #expect(previous.shouldRender(after: previous, submittedRevision: nil, acknowledgedRevision: 4))
        #expect(!next.canPatch(after: previous, submittedRevision: 4, acknowledgedRevision: 3))
        #expect(!next.canPatch(after: nil, submittedRevision: nil, acknowledgedRevision: 0))
        next = CanvasRenderRequestID(pageID: pageID, mutationRevision: 12,
            assetRevision: 0, partPackageRevision: 1, breakpoint: .mobile,
            forcesReconciliation: false, appearance: .light)
        #expect(!next.canPatch(after: previous, submittedRevision: 4, acknowledgedRevision: 4))
        next.reconciliationRequest = 1
        #expect(!next.canPatch(after: previous, submittedRevision: 4, acknowledgedRevision: 4))
    }

    @Test func revisionGateRejectsStaleWorkBeforeApplyingIt() {
        var gate = CanvasUpdateRevisionGate()
        let requested = gate.request(10)
        let applied = gate.apply(10)
        let newerRequested = gate.request(12)
        #expect(requested && applied && newerRequested)
        #expect(!gate.isCurrent(11))
        let staleApplied = gate.apply(11)
        #expect(!staleApplied)
        #expect(gate.isCurrent(12))
    }

    @Test func nestedStructureInsertionRendersOnlyItsOwnerSubtree() throws {
        let owner = PartNode(type: .section)
        let page = Page(title: "Home", slug: "index", parts: [owner])
        let renderer = CanvasRenderSpy(subtree: .init(
            partID: owner.id,
            html: "<div data-foundry-id=\"\(owner.id)\"></div>",
            instanceStyles: [:]
        ))
        let snapshot = CanvasRenderSnapshot(
            renderer: renderer,
            page: page,
            language: "en",
            framework: .standard,
            assets: [:],
            breakpoint: .large,
            impact: .partStructure(ownerID: owner.id),
            forcesReconciliation: false
        )

        #expect(snapshot.render() == .part(try #require(renderer.subtree)))
    }

    @Test func rootStructureInsertionStillRendersTheWholePage() {
        let page = Page(title: "Home", slug: "index")
        let renderer = CanvasRenderSpy(subtree: nil)
        let snapshot = CanvasRenderSnapshot(
            renderer: renderer,
            page: page,
            language: "en",
            framework: .standard,
            assets: [:],
            breakpoint: .large,
            impact: .partStructure(ownerID: nil),
            forcesReconciliation: false
        )

        #expect(snapshot.render() == .page(CanvasRenderSpy.pageHTML))
    }

    @Test func partUpdateWithoutLoadedBaselineRequestsFullSnapshot() async {
        var requests = 0
        let coordinator = WebCanvasView.Coordinator(assets: [:], packages: [:],
            canClearImage: { _, _, _ in false }, handleMessage: { _ in },
            handleContextMenuAction: { _, _, _, _ in }, requestFullReconciliation: { requests += 1 })
        let web = WKWebView(frame: .zero)
        for revision in 1...3 {
            coordinator.apply(.part(.init(partID: UUID(), html: "<div></div>", instanceStyles: [:]), revision: UInt64(revision)), in: web)
        }
        for _ in 0..<100 {
            if requests == 3 { break }
            await Task.yield()
        }
        #expect(requests == 3)
    }

    @Test(.timeLimit(.minutes(1))) func canvasRejectsStaleUpdatesAndDrawsChromeInsideBorders() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(
            source: WebCanvasView.Coordinator.interactionScript, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 220), configuration: configuration)
        defer { web.stopLoading() }
        web.loadHTMLString("""
            <html><head><style>
            body { margin: 20px; }
            figure { box-sizing: content-box; width: 100px; height: 100px; margin: 0;
              border: 10px solid red; border-radius: 20px; }
            img { display:block; width:100%; height:100%; background:black; }
            </style></head><body>
            <figure data-foundry-id="image"><img alt="Test"></figure>
            <div data-foundry-id="a">Initial</div>
            </body></html>
            """, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryReplaceDocument === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let result = try #require(try await web.callAsyncJavaScript("""
            window.foundrySetSelection(['image'], {}, false);
            const host = document.querySelector('[data-foundry-editor-chrome="host"]');
            const outline = host.shadowRoot.querySelector('[data-foundry-editor-chrome="selection"]');
            const style = getComputedStyle(outline);
            const chromeStyles = [style.display, style.left, style.top, style.width, style.height,
              style.borderWidth, style.borderRadius, style.borderColor];

            const doc = text => '<html><body><div data-foundry-id="a">' + text + '</div></body></html>';
            const part = '<div data-foundry-id="a">Part update</div>';
            if (!window.foundryReplacePart('a', part, '', 10)) return null;
            if (window.foundryReplaceDocument(doc('Stale'), 9)) return null;
            if (document.querySelector('[data-foundry-id="a"]').textContent !== 'Part update') return null;
            if (!window.foundryReplaceDocument(doc('Current'), 12)) return null;
            if (window.foundryReplacePart('a', part, '', 11)) return null;
            if (document.querySelector('[data-foundry-id="a"]').textContent !== 'Current') return null;
            return chromeStyles;
            """, arguments: [:], in: nil, contentWorld: .defaultClient) as? [String])
        #expect(result[0] == "block")
        #expect(Array(result[1...5]) == ["30px", "30px", "100px", "100px", "3px"])
        #expect(result[6] == "0px")
        #expect(result[7].contains("rgb(0, 123, 255)"))
    }
}

private struct CanvasRenderSpy: PageRendering {
    static let pageHTML = "<html><body>full page</body></html>"
    let subtree: RenderedPartSubtree?

    func render(
        page: Page,
        language: String,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> String {
        Self.pageHTML
    }

    func renderSubtree(
        partID: UUID,
        page: Page,
        framework: Framework,
        assets: ProjectAssetContents,
        breakpoint: ResponsiveBreakpoint
    ) -> RenderedPartSubtree? {
        subtree
    }
}
