import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct CanvasSceneTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func spacingOverridesSurviveSceneRenderingAndLiveEdits(localUpdate: Bool) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.container)
        node.anchor = "responsive-spacing"
        let key = PartProperty.Key(rawValue: "spacing.margin")
        var margin = ThemeMarginValue()
        margin.setAll(.init(token: "1"))
        node.setProperty(key, value: .themeMargin(margin))
        margin.setAll(.init(token: "5"))
        node.setResponsiveProperty(key, value: .themeMargin(margin), at: .medium)
        var page = Page(title: "Spacing", slug: "index", parts: [node])
        func render(_ previous: CanvasScene?, impact: ProjectMutationImpact? = nil) throws -> (scene: CanvasScene, result: CanvasRenderResult) {
            try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en", theme: .standard,
                assets: [:], breakpoint: .medium, packageRevision: 0, previous: previous, consecutiveImpact: impact)
        }
        let initial = try render(nil)
        #expect(initial.scene.artifacts[node.id]?.html.contains("md:m-5") == true)
        try verifyFreshMarkup(initial.scene, page: page, breakpoint: .medium)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        defer { web.stopLoading() }
        guard case .page(let html) = initial.result else { Issue.record("Missing initial page"); return }
        web.loadHTMLString(html, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryApplyScene === 'function' && !!document.getElementById('responsive-spacing')",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('responsive-spacing')).marginTop") as? String == "16px")
        var previous = initial.scene
        for (index, token) in ["12", "1"].enumerated() {
            if index == 0 {
                margin.setAll(.init(token: token))
                page.parts[0].setResponsiveProperty(key, value: .themeMargin(margin), at: .medium)
            } else {
                page.parts[0].removeResponsiveOverride(key, at: .medium)
            }
            let changed = try render(previous, impact: localUpdate ? .partProperty(partID: node.id, propertyKey: key) : nil)
            #expect(changed.scene.renderedInstanceCount == 1)
            try verifyFreshMarkup(changed.scene, page: page, breakpoint: .medium)
            guard case .scene(let update) = changed.result else { Issue.record("Expected live scene update"); return }
            #expect(update.html[node.id.uuidString]?.contains("md:m-12") == (index == 0))
            let applied = try await web.callAsyncJavaScript(
                "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                    "roots": update.roots as Any? ?? NSNull(), "revision": index + 1,
                    "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                in: nil, contentWorld: .defaultClient)
            try #require(applied as? Bool == true)
            #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('responsive-spacing')).marginTop") as? String == (index == 0 ? "48px" : "4px"))
            previous = changed.scene
        }
    }

    private func fixture() throws -> LoadedPartPackage {
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data("""
        {"minimumAPIVersion":1,"id":"test.scene.\(UUID().uuidString.lowercased())","title":"Scene",
         "version":"1.0.0","group":"Layout","description":"Test",
         "inspector":[{"type":"number","id":"width","responsive":true,"defaults":{"xs":100}}],
         "templates":{"html":"part.html"}}
        """.utf8))
        return LoadedPartPackage(manifest: manifest, rootURL: URL(fileURLWithPath: "/tmp/scene-fixture"),
            htmlTemplate: "<section {{ part.attributes }}>{{ dropZone(\"content\") }}</section>",
            css: ":instance { width: {{ control.width }}px; }", pageCSS: "", siteCSS: "", placedHTML: [],
            instanceJavaScript: "", pageJavaScript: "", instancePHP: "", pagePHP: "", editorCSS: "",
            updateSourceURL: nil, imageMetadata: [:])
    }

    @Test(arguments: [1, 10, 100])
    func localRenderingDoesNotGrowWithDescendantCount(_ count: Int) throws {
        let package = try fixture()
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let type = PartType(rawValue: package.manifest.identifier)
        var parent = PartNode.make(type)
        parent.children = (0..<count).map { _ in PartNode.make(type) }
        var page = Page(title: "Test", slug: "index", parts: [parent])
        func render(_ previous: CanvasScene?, impact: ProjectMutationImpact? = nil) throws -> (scene: CanvasScene, result: CanvasRenderResult) {
            try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en", theme: .standard,
                assets: [:], breakpoint: .mobile, packageRevision: 0, previous: previous, consecutiveImpact: impact)
        }
        let initial = try render(nil)
        #expect(initial.result == .page(HTMLPageRenderer().render(page: page, language: "en",
            theme: .standard, assets: [:], breakpoint: .mobile)))
        page.parts[0].setProperty(.init(rawValue: "width"), value: .number(200))
        let changed = try render(initial.scene, impact: .partProperty(partID: parent.id, propertyKey: .init(rawValue: "width")))
        #expect(changed.scene.renderedInstanceCount == 1)
        #expect(changed.scene.examinedInstanceCount == 1)
        guard case .scene(let update) = changed.result else { Issue.record("Expected scene update"); return }
        #expect(update.html.isEmpty)
        #expect(update.styles.count == 1)
        page.parts[0].children.append(PartNode.make(type))
        let inserted = try render(changed.scene)
        #expect(inserted.scene.renderedInstanceCount == 2)
        page.parts[0].children.reverse()
        let moved = try render(inserted.scene)
        #expect(moved.scene.renderedInstanceCount == 1)
        try verifyFreshMarkup(moved.scene, page: page, breakpoint: .mobile)
        page.parts[0].children.removeLast()
        let removed = try render(moved.scene)
        #expect(removed.scene.renderedInstanceCount == 1)
        try verifyFreshMarkup(removed.scene, page: page, breakpoint: .mobile)
    }

    @Test func breakpointChangesRenderOnlyAffectedInstancesAndRoundTrip() throws {
        let package = try fixture()
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode.make(.init(rawValue: package.manifest.identifier))
        node.setResponsiveProperty(.init(rawValue: "width"), value: .number(350), at: .medium)
        node.children = [PartNode.make(node.type)]
        let page = Page(title: "Test", slug: "index", parts: [node])
        func render(_ breakpoint: ResponsiveBreakpoint, _ previous: CanvasScene?) throws -> (scene: CanvasScene, result: CanvasRenderResult) {
            try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en", theme: .standard,
                assets: [:], breakpoint: breakpoint, packageRevision: 0, previous: previous)
        }
        let mobile = try render(.mobile, nil)
        let desktop = try render(.large, mobile.scene)
        #expect(desktop.scene.renderedInstanceCount == 1)
        #expect(desktop.scene.artifacts[node.id]?.css.contains("350px") == true)
        try verifyFreshMarkup(desktop.scene, page: page, breakpoint: .large)
        let restored = try render(.mobile, desktop.scene)
        #expect(restored.scene.artifacts == mobile.scene.artifacts)
    }

    private func verifyFreshMarkup(_ scene: CanvasScene, page: Page, breakpoint: ResponsiveBreakpoint,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
        func materialize(_ id: UUID) throws -> String {
            var html = try #require(scene.artifacts[id]?.html, sourceLocation: sourceLocation)
            for child in try #require(scene.inputs[id]?.node.children, sourceLocation: sourceLocation) {
                html = html.replacingOccurrences(of: "<!--foundry-child:\(child.id.uuidString)-->",
                    with: try materialize(child.id))
            }
            return html
        }
        for root in page.parts {
            let fresh = try #require(HTMLPageRenderer().renderSubtree(partID: root.id, page: page,
                theme: .standard, assets: [:], breakpoint: breakpoint), sourceLocation: sourceLocation)
            #expect(try materialize(root.id) == fresh.html, sourceLocation: sourceLocation)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func generatedTransactionsMatchFreshDOMAcrossEditsAndMoves() async throws {
        let package = try fixture()
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let type = PartType(rawValue: package.manifest.identifier)
        var parent = PartNode.make(type)
        parent.children = [PartNode.make(type), PartNode.make(type)]
        var page = Page(title: "DOM test", slug: "index", parts: [parent, PartNode.make(type)])
        var previous: CanvasScene?
        func render(_ breakpoint: ResponsiveBreakpoint) throws -> CanvasRenderResult {
            let rendered = try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en",
                theme: .standard, assets: [:], breakpoint: breakpoint, packageRevision: 0, previous: previous)
            previous = rendered.scene
            return rendered.result
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { web.stopLoading() }
        guard case .page(let initial) = try render(.mobile) else { Issue.record("Missing initial document"); return }
        web.loadHTMLString(initial, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryApplyScene === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        for step in 1...6 {
            switch step {
            case 1:
                page.parts[0].setProperty(.init(rawValue: "width"), value: .number(250))
                page.parts[0].children.append(PartNode.make(type))
            case 2:
                let moved = page.parts[0].children.removeFirst()
                page.parts[1].children.append(moved)
            case 3:
                page.parts[0].children.removeLast()
                page.parts.reverse()
            case 4:
                page.parts[0].setResponsiveProperty(.init(rawValue: "width"), value: .number(375), at: .medium)
            default: break
            }
            let breakpoint: ResponsiveBreakpoint = step == 5 ? .large : .mobile
            guard case .scene(let update) = try render(breakpoint) else { Issue.record("Unexpected full refresh"); return }
            let applied = try await web.callAsyncJavaScript(
                "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                    "roots": update.roots as Any? ?? NSNull(), "revision": step,
                    "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                in: nil, contentWorld: .defaultClient)
            try #require(applied as? Bool == true)
            let fresh = HTMLPageRenderer().render(page: page, language: "en", theme: .standard,
                assets: [:], breakpoint: breakpoint)
            let equivalent = try await web.callAsyncJavaScript("""
                const expected = new DOMParser().parseFromString(fresh, 'text/html');
                const parts = root => Array.from(root.querySelectorAll('[data-foundry-id]')).map(part => {
                  const clone = part.cloneNode(true);
                  clone.removeAttribute('draggable');
                  clone.querySelectorAll('[draggable]').forEach(e => e.removeAttribute('draggable'));
                  return clone.outerHTML;
                });
                const styles = root => Array.from(root.querySelectorAll('style[data-foundry-instance-style]'))
                  .map(s => [s.dataset.foundryInstanceStyle, s.textContent.trim()]);
                return JSON.stringify(parts(document)) === JSON.stringify(parts(expected))
                  && JSON.stringify(styles(document)) === JSON.stringify(styles(expected));
                """, arguments: ["fresh": fresh], in: nil, contentWorld: .defaultClient)
            #expect(equivalent as? Bool == true, "DOM differs at step \(step)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sceneTransactionsRetainChildrenAndApplyResponsiveCSS() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { web.stopLoading() }
        web.loadHTMLString("""
        <html><head></head><body><!--foundry-roots-start--><section data-foundry-id="parent"><div data-foundry-id="child">Child</div></section><section data-foundry-id="other"></section><!--foundry-roots-end--></body></html>
        """, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryApplyScene === 'function'",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let result = try await web.callAsyncJavaScript("""
            const child = document.querySelector('[data-foundry-id="child"]');
            child.retainedTest = 42;
            const first = window.foundryApplyScene({parent:'<article data-foundry-id="parent"><!--foundry-child:child--></article>'},
                {parent:'[data-foundry-id="parent"] {width:350px;}'}, [], null, 1);
            const width = getComputedStyle(document.querySelector('[data-foundry-id="parent"]')).width;
            const retained = child === document.querySelector('[data-foundry-id="child"]');
            const moved = window.foundryApplyScene({parent:'<article data-foundry-id="parent"></article>',
                other:'<section data-foundry-id="other"><!--foundry-child:child--></section>'}, {}, [], null, 2);
            const movedCorrectly = child.parentElement.dataset.foundryId === 'other' && child.retainedTest === 42;
            const rejected = window.foundryApplyScene({other:'<section data-foundry-id="other"><!--foundry-child:missing--></section>'}, {}, [], null, 3);
            const hidden = window.foundryApplyScene({other:'<section data-foundry-id="other"></section>'}, {}, [], null, 4);
            const hiddenCorrectly = !child.isConnected;
            const restored = window.foundryApplyScene({other:'<section data-foundry-id="other"><!--foundry-child:child--></section>'}, {}, [], ['other', 'parent'], 5);
            const retainedAfterRestore = child === document.querySelector('[data-foundry-id="child"]') && child.retainedTest === 42;
            const rootOrder = Array.from(document.body.children).filter(e => e.hasAttribute('data-foundry-id')).map(e => e.dataset.foundryId).join(',');
            const combined = window.foundryApplyScene({other:'<article data-foundry-id="other"><!--foundry-child:child--></article>',
                child:'<div data-foundry-id="child">Changed</div>'}, {}, ['parent'], ['other'], 6);
            return [first, width === '350px', retained, moved, movedCorrectly, !rejected,
                hidden, hiddenCorrectly, restored, retainedAfterRestore, rootOrder === 'other,parent', combined,
                document.querySelector('[data-foundry-id="child"]').textContent === 'Changed',
                !document.querySelector('[data-foundry-id="parent"]')];
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        #expect(result as? [Bool] == Array(repeating: true, count: 14))
    }
}
