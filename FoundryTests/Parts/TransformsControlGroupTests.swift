import Foundation
import Testing
import WebKit
@testable import Foundry

struct TransformsControlGroupTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["Button", "Columns", "Section", "Copyright", "Divider", "StackItem", "Stack", "Grid", "GridItem", "Heading", "Image", "Navigation", "Paragraph", "Video"])
    @MainActor func contentMovesButHoverHostRemainsStationary(name: String) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/" + name))
        let html: String
        let id: String
        do {
            let previous = PartType(rawValue: package.manifest.identifier).definition.package
            PartRegistry.register(package)
            defer {
                if let previous { PartRegistry.register(previous) }
                else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
            }
            var part = PartNode(type: .init(rawValue: package.manifest.identifier))
            part.setProperty(.init(rawValue: "transforms.transformsMode"), value: .string("hover"))
            part.setProperty(.init(rawValue: "transforms.transformsHoverTranslateY"), value: .string("-40px"))
            part.setProperty(.init(rawValue: "transitions.transitionsEnabled"), value: .boolean(true))
            let site = Site(name: "Hover", pages: [Page(title: "Home", slug: "index", parts: [part])])
            html = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
            id = part.id.uuidString
        }
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { webView.stopLoading() }
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = ContinuousClock.now + .seconds(10)
        var ready = false
        while ContinuousClock.now < deadline {
            ready = (try? await webView.callAsyncJavaScript("return !!document.querySelector('[data-foundry-id=\"' + id + '\"] > .fd-transform-content');",
                arguments: ["id": id], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            await Task.yield()
        }
        try #require(ready)
        let result = try await webView.callAsyncJavaScript("""
            const root = document.querySelector('[data-foundry-id="' + id + '"]');
            const content = root.querySelector(':scope > .fd-transform-content');
            const timing = getComputedStyle(content).transitionDuration;
            // Simulate hover matching while exercising the real generated CSS.
            const visit = rules => { for (const rule of rules) {
              if (rule.selectorText) rule.selectorText = rule.selectorText.replaceAll(':hover', '.test-hover');
              if (rule.cssRules) visit(rule.cssRules);
            }};
            for (const sheet of document.styleSheets) { try { visit(sheet.cssRules); } catch {} }
            root.style.cssText += ';position:fixed;left:100px;top:100px;width:200px;height:100px;margin:0;transition:none';
            content.style.transition = 'none';
            const before = root.getBoundingClientRect();
            const innerBefore = content.getBoundingClientRect();
            root.classList.add('test-hover');
            const after = root.getBoundingClientRect();
            const innerAfter = content.getBoundingClientRect();
            const hit = document.elementFromPoint(150, 190);
            const stable = before.top === after.top && before.height === after.height
              && Math.abs(innerAfter.top - innerBefore.top + 40) < 0.1
              && getComputedStyle(root).transform === 'none' && root.contains(hit);
            root.classList.remove('test-hover');
            return stable && getComputedStyle(content).transform === 'none' && timing !== '0s';
            """, arguments: ["id": id], in: nil, contentWorld: .defaultClient)
        #expect(result as? Bool == true, "\(name) must move only content, preserve the root hit area, and apply transition timing to content.")
    }

    private func resolved(_ overrides: [String: PartPackageValue]) -> [String: PartPackageValue] {
        let group = PartPackageControlGroup(type: .transforms, id: "visual")
        var values = Dictionary(uniqueKeysWithValues: group.properties.map { ($0.id, $0.defaultValue) })
        for (key, value) in overrides { values["visual." + key] = value }
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        return values
    }

    @Test(arguments: ["none", "static", "hover"])
    func neutralDefaultsDoNotCreateAContainingBlock(mode: String) {
        let values = resolved(["transformsMode": .string(mode)])
        #expect(values["visual.css"] == .string("transform: none; transform-origin: center;"))
        #expect(values["visual.css"] == values["visual.hover.css"])
    }

    @Test func staticMirrorsNormalAndHoverIgnoresInspectorState() {
        let staticValues = resolved(["transformsMode": .string("static"), "transformsScale": .number(125)])
        #expect(staticValues["visual.css"] == staticValues["visual.hover.css"])
        for state in ["normal", "hover"] {
            let values = resolved(["transformsMode": .string("hover"), "transformsState": .string(state),
                "transformsTranslateX": .string("-10vw"), "transformsHoverScale": .number(120),
                "transformsHoverOrigin": .string("top left")])
            #expect(values["visual.css"]?.stringValue.contains("translate(-10vw, 0px)") == true)
            #expect(values["visual.hover.css"]?.stringValue.contains("scale(1.2)") == true)
            #expect(values["visual.hover.css"]?.stringValue.contains("transform-origin: top left") == true)
        }
    }

    @Test(arguments: ["10; color: red", "calc(100% - 5px)", "NaNpx", "10", "url(x)", "0px!important"])
    func rejectsUnsafeOrUnsupportedLengths(value: String) {
        let values = resolved(["transformsMode": .string("static"), "transformsTranslateX": .string(value)])
        #expect(values["visual.css"]?.stringValue.hasPrefix("transform: none;") == true)
    }

    @Test func clampsNumbersAndValidatesOrigin() {
        let values = resolved(["transformsMode": .string("static"), "transformsScale": .number(9999),
            "transformsRotate": .number(-9999), "transformsSkewX": .number(.infinity),
            "transformsOrigin": .string("center; color: red"), "transformsTranslateY": .string("50%")])
        #expect(values["visual.css"] == .string("transform: translate(0px, 50%) rotate(-360deg) skew(0deg, 0deg) scale(10); transform-origin: center;"))
    }

    @Test func builtInPartsDeclareAndRenderBothTransformStates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Button", "Columns", "Section", "Copyright", "Divider", "StackItem",
                     "Stack", "Grid", "GridItem", "Heading", "Image", "Navigation", "Paragraph", "Video"] {
            let package = try PartPackageLoader.load(from: root.appending(path:
                "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/" + name))
            #expect(package.manifest.controlGroups.contains { $0.type == .transforms })
            #expect(package.css.contains("control.transforms.css"))
            #expect(package.css.contains("control.transforms.hover.css"))
            #expect(package.css.contains("{{ control.transforms.hover.selector }} > .fd-transform-content { {{ control.transforms.hover.css }} }"))
            #expect(package.css.contains(":instance { {{ control.transforms.css }} }") == false)
            #expect(package.css.contains(":instance > .fd-transform-content { {{ control.transforms.css }} {{ control.transitions.css }} }"))
        }
    }

    @Test @MainActor func canvasAndExportResolveTheSameTransformValues() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Section"))
        let previous = PartType(rawValue: package.manifest.identifier).definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        var part = PartNode(type: .init(rawValue: package.manifest.identifier))
        part.setProperty(.init(rawValue: "transforms.transformsMode"), value: .string("hover"))
        part.setProperty(.init(rawValue: "transforms.transformsRotate"), value: .number(4))
        part.setProperty(.init(rawValue: "transforms.transformsHoverRotate"), value: .number(9))
        let site = Site(name: "Transform test", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        let export = StaticSiteRenderer().render(site: site, assets: [:])
        #expect(export.errors.isEmpty)
        let css = try #require(export.file(at: "files/page.css")?.contents)
        for output in [canvas, css] {
            #expect(output.contains("rotate(4deg)"))
            #expect(output.contains("rotate(9deg)"))
        }
    }
}
