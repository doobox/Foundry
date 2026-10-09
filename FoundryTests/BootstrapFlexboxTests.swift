import Foundation
import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapFlexboxTests {
    @Test func partsExposeOnlyTheirRelevantDisplayAndLayoutControls() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        for (type, displays) in [(PartType.container, ["none", "d-block", "d-none"]), (.flex, ["d-flex", "d-none"]), (.grid, ["d-grid", "d-none"])] {
            let package = try #require(type.definition.package)
            try package.preparePayload()
            let properties = package.manifest.resolvedProperties
            #expect(properties.first { $0.id == "display.display" }?.control.options?.map(\.value) == displays)
            #expect(properties.contains { $0.id == "flexbox.direction" } == (type == .flex))
            #expect(properties.contains { $0.id == "grid.columns" } == (type == .grid))
            #expect(package.css.isEmpty)
            #expect(type.definition.allowsChildren)
        }
        let shared = PartPackageControlGroup(type: .display, id: "all")
        #expect(shared.properties.first?.control.options?.count == 14)
    }

    @Test func flexboxControlsDoNotDependOnDisplay() {
        let group = PartPackageControlGroup(type: .flexbox, id: "flow")
        #expect(group.properties.count == 2)
        #expect(group.properties.allSatisfy { $0.visibleWhen == nil })
    }

    private func fixture(grid: Bool = false) -> (Page, Framework) {
        var node = PartNode.make(grid ? .grid : .flex)
        node.anchor = "flex-test"
        node.children = [PartNode.make(.button), PartNode.make(.button)]
        for (key, base, medium) in [
            ("display.display", grid ? "d-grid" : "d-flex", grid ? "d-grid" : "d-flex"),
            ("flexbox.direction", "flex-column", "flex-row"),
            ("flexbox.wrap", "flex-nowrap", "flex-wrap"),
            ("alignment.alignItems", "align-items-start", "align-items-center"),
            ("alignment.justifyContent", "justify-content-start", "justify-content-between")
        ] {
            if grid && key.hasPrefix("flexbox.") { continue }
            let key = PartProperty.Key(rawValue: key)
            node.setProperty(key, value: .choice(base))
            node.setResponsiveProperty(key, value: .choice(medium), at: .medium)
        }
        let key = PartProperty.Key(rawValue: "gap.gap")
        node.setProperty(key, value: .frameworkSpacing(.init(selection: .init(token: "5"))))
        node.setResponsiveProperty(key, value: .frameworkSpacing(.init(selection: .init(token: "hero"))), at: .medium)
        var framework = Framework.standard
        framework.spacing.custom = [.init(name: "hero", value: 2)]
        return (Page(title: "Flex", slug: "index", parts: [node]), framework)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"], [false, true])
    func nativeClassesAndComputedLayoutAgree(destination: String, grid: Bool) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var (page, framework) = fixture(grid: grid)
        page.parts[0].setProperty(.init(rawValue: "display.visibility"), value: .choice("invisible"))
        if grid {
            page.parts[0].setProperty(.init(rawValue: "grid.columns"), value: .choice("grid-cols-1"))
            page.parts[0].setResponsiveProperty(.init(rawValue: "grid.columns"), value: .choice("grid-cols-3"), at: .medium)
            page.parts[0].setProperty(.init(rawValue: "display.display"), value: .choice("d-grid"))
            page.parts[0].setResponsiveProperty(.init(rawValue: "display.display"), value: .choice("d-grid"), at: .medium)
            page.parts[0].setProperty(.init(rawValue: "alignment.justifyItems"), value: .choice("justify-items-start"))
            page.parts[0].setResponsiveProperty(.init(rawValue: "alignment.justifyItems"), value: .choice("justify-items-end"), at: .medium)
            page.parts[0].setProperty(.init(rawValue: "alignment.placeItems"), value: .choice("place-items-center"))
            page.parts[0].setResponsiveProperty(.init(rawValue: "alignment.placeItems"), value: .choice("place-items-stretch"), at: .medium)
        }
        let html: String
        if destination == "canvas" {
            let rendered = try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en", framework: framework,
                assets: [:], breakpoint: .medium, packageRevision: 0, previous: nil)
            #expect(rendered.scene.artifacts[page.parts[0].id]?.html.contains(grid ? "md:grid-cols-3" : "md:flex-row") == true)
            guard case .page(let document) = rendered.result else { Issue.record("Expected document"); return }
            html = document
        } else {
            var site = Site(name: "Flex", pages: [page])
            site.framework = framework
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
            #expect(bundle.errors.isEmpty)
            let document = try #require(bundle.file(at: "index.html"))
            #expect(document.contents.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        #expect(html.contains("md:gap-hero"))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        defer { web.stopLoading() }
        web.loadHTMLString(html, baseURL: nil)
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('flex-test')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        for width in [375, 800] {
            web.setFrameSize(CGSize(width: width, height: 600))
            for _ in 0..<100 {
                if (try? await web.evaluateJavaScript("innerWidth === \(width)")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let styles = try await web.evaluateJavaScript("(() => { const s=getComputedStyle(document.getElementById('flex-test')); return [s.display,s.flexDirection,s.flexWrap,s.alignItems,s.justifyContent,s.gap]; })()") as? [String]
            if grid {
                #expect(styles == (width == 375 ? ["grid", "row", "nowrap", "center", "flex-start", "16px"] : ["grid", "row", "nowrap", "stretch", "space-between", "32px"]))
                let justification = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('flex-test')).justifyItems") as? String
                #expect(justification == (width == 375 ? "center" : "stretch"))
                let columns = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('flex-test')).gridTemplateColumns.split(' ').length") as? Int
                #expect(columns == (width == 375 ? 1 : 3))
            } else {
                #expect(styles == (width == 375 ? ["flex", "column", "nowrap", "flex-start", "flex-start", "16px"] : ["flex", "row", "wrap", "center", "space-between", "32px"]))
            }
            #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('flex-test')).visibility") as? String == "hidden")
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func liveSceneEditsKeepResponsiveGroups(localUpdate: Bool, grid: Bool) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var (page, framework) = fixture(grid: grid)
        let id = page.parts[0].id
        func render(_ previous: CanvasScene?, key: PartProperty.Key? = nil) throws -> (scene: CanvasScene, result: CanvasRenderResult) {
            try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en", framework: framework,
                assets: [:], breakpoint: .medium, packageRevision: 0, previous: previous,
                consecutiveImpact: localUpdate ? key.map { .partProperty(partID: id, propertyKey: $0) } : nil)
        }
        let initial = try render(nil)
        var previous = initial.scene
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        defer { web.stopLoading() }
        guard case .page(let html) = initial.result else { Issue.record("Expected document"); return }
        web.loadHTMLString(html, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await web.callAsyncJavaScript("return typeof window.foundryApplyScene === 'function' && !!document.getElementById('flex-test')",
                arguments: [:], in: nil, contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        func apply(_ result: CanvasRenderResult, revision: Int, property: String, expected: String) async throws {
            guard case .scene(let update) = result else { Issue.record("Expected patch"); return }
            let applied = try await web.callAsyncJavaScript(
                "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                    "roots": update.roots as Any? ?? NSNull(), "revision": revision,
                    "styleMoves": update.styleMoves, "childMoves": update.childMoves], in: nil, contentWorld: .defaultClient)
            try #require(applied as? Bool == true)
            let computed = try await web.callAsyncJavaScript("const s = getComputedStyle(document.getElementById('flex-test')); return property === 'columnCount' ? String(s.gridTemplateColumns.split(' ').length) : s[property]",
                arguments: ["property": property], in: nil, contentWorld: .defaultClient)
            #expect(computed as? String == expected)
        }
        let changes: [(String, PartProperty.Value, String, String, String, String)] = grid ? [
            ("grid.columns", .choice("grid-cols-4"), "md:grid-cols-4", "columnCount", "4", "2"),
            ("grid.autoFlow", .choice("grid-auto-flow-column"), "md:grid-auto-flow-column", "gridAutoFlow", "column", "row"),
            ("alignment.justifyItems", .choice("justify-items-center"), "md:justify-items-center", "justifyItems", "center", "normal"),
            ("display.display", .choice("d-none"), "md:d-none", "display", "none", "grid")
        ] : [
            ("flexbox.direction", PartProperty.Value.choice("flex-row-reverse"), "md:flex-row-reverse", "flexDirection", "row-reverse", "column"),
            ("gap.gap", .frameworkSpacing(.init(selection: .init(token: "12"))), "md:gap-12", "gap", "48px", "16px"),
            ("alignment.alignItems", .choice("align-items-end"), "md:align-items-end", "alignItems", "flex-end", "flex-start"),
            ("display.display", .choice("d-none"), "md:d-none", "display", "none", "flex")
        ]
        for (index, change) in changes.enumerated() {
            let (rawKey, value, expected, cssProperty, changedValue, baseValue) = change
            let key = PartProperty.Key(rawValue: rawKey)
            page.parts[0].setResponsiveProperty(key, value: value, at: .medium)
            let changed = try render(previous, key: key)
            guard case .scene(let update) = changed.result else { Issue.record("Expected patch"); return }
            #expect(update.html[id.uuidString]?.contains(expected) == true)
            #expect(changed.scene.renderedInstanceCount == 1)
            try await apply(changed.result, revision: index * 2 + 1, property: cssProperty, expected: changedValue)
            previous = changed.scene
            page.parts[0].removeResponsiveOverride(key, at: .medium)
            let removed = try render(previous, key: key)
            #expect(removed.scene.artifacts[id]?.html.contains(expected) == false)
            try await apply(removed.result, revision: index * 2 + 2, property: cssProperty, expected: baseValue)
            previous = removed.scene
        }
    }

    @Test func reusableGroupsHaveOnlyNativeOutput() throws {
        for kind in [PartPackageControlGroup.Kind.flexbox, .gap, .display, .alignment, .grid] {
            let group = PartPackageControlGroup(type: kind, id: "example")
            #expect(group.properties.allSatisfy { $0.defaultValue == .string("none") })
            #expect(group.properties.allSatisfy { $0.responsive == ($0.controlGroupSource?.localID != "visibility") })
            var values: [String: PartPackageValue] = [:]
            PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
            #expect(values["example.classes"] == .string(""))
            #expect(values["example.css"] == nil)
            #expect(values["example.childCSS"] == nil)
        }
    }

    @Test func visibilityIsBaseOnlyAndLayoutGroupsAreIndependent() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.container)
        let key = PartProperty.Key(rawValue: "display.visibility")
        node.setProperty(key, value: .choice("invisible"))
        node.setResponsiveProperty(key, value: .choice("visible"), at: .medium)
        #expect(BootstrapControlGroupClasses.resolve(node: node, key: key, framework: .standard) == "invisible")
        let display = PartPackageControlGroup(type: .display, id: "presentation",
            allowedOptions: ["display": ["none", "d-flex", "d-grid"]])
        #expect(display.properties.first?.control.options?.map(\.value) == ["none", "d-flex", "d-grid"])
        let alignment = PartPackageControlGroup(type: .alignment, id: "grid",
            excludeControls: ["alignContent"])
        #expect(Set(alignment.properties.map(\.id)) == ["grid.justifyContent", "grid.justifyItems", "grid.alignItems", "grid.placeItems"])
        #expect(alignment.properties.allSatisfy { $0.visibleWhen == nil })
    }
}
