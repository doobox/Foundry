import Foundation
import Testing
import WebKit
@testable import Foundry

@Suite("Built-in layout parts", .serialized)
@MainActor
struct BuiltInLayoutPartsTests {
    private let names = ["Section", "Container", "Stack", "Columns", "Grid"]

    private func package(_ name: String) throws -> LoadedPartPackage {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Contents/Resources/\(name).foundrypack")
        return try PartPackageLoader.load(from: root)
    }

    @Test func allLayoutsValidateAndShareInspectorGroups() throws {
        for name in names {
            let loaded = try package(name)
            #expect(loaded.hasDropZone)
            let properties = loaded.manifest.properties
            for (id, group) in [("widthMode", "Sizing"), ("themePadding", "Spacing"),
                                ("themeMargin", "Spacing"), ("backgroundColor", "Background"),
                                ("themeRadius", "Borders"), ("flexGrow", "Layout item")] {
                #expect(properties.first { $0.id == id }?.group == group)
            }
            #expect(properties.first { $0.id == "themePadding" }?.visibleWhen?.id == "spacingEnabled")
            #expect(properties.first { $0.id == "themeMargin" }?.visibleWhen?.id == "spacingEnabled")
            #expect(Set(properties.map(\.id)).count == properties.count)
        }
    }

    private func css(_ name: String, values overrides: [String: PartPackageValue] = [:]) throws -> String {
        let loaded = try package(name)
        var values: [String: PartPackageValue] = [
            "widthMode": .string("full"), "customWidth": .number(320), "maxWidth": .number(0),
            "minimumHeight": .number(0), "heightMode": .string("auto"), "customHeight": .number(400),
            "spacingEnabled": .boolean(true), "themePadding": .string("16px"), "themeMargin": .string("0"),
            "overflow": .string("visible"), "itemEnabled": .boolean(false), "showsBackground": .boolean(false),
            "themeBorder.width": .string("0"), "themeBorder.style": .string("solid"),
            "themeBorderColour": .string("black"), "themeRadius": .string("0"),
            "themeGap": .string("16px"), "themeGap.value": .number(16), "rowGap": .string("16px"),
            "direction": .string("column"), "wrap": .string("nowrap"), "justifyContent": .string("flex-start"),
            "alignItems": .string("stretch"), "verticalAlignment": .string("start"),
            "constrainContent": .boolean(true), "innerMaxWidth": .number(1120),
            "columnCount": .number(2), "proportions": .string("equal"), "gridMode": .string("count"),
            "rowSizing": .string("auto"), "justifyItems": .string("stretch"), "minimumColumnWidth": .number(240)
        ]
        values.merge(overrides) { _, new in new }
        return PartTemplateRenderer.render(loaded.css, context: PartTemplateContext(
            instanceID: UUID(), packageIdentifier: loaded.manifest.identifier,
            properties: values, slots: [:]
        ))
    }

    @Test func disabledSpacingAndSizingProduceExplicitResets() throws {
        for name in names {
            let output = try css(name, values: ["spacingEnabled": .boolean(false)])
            #expect(output.contains("padding: 0;"))
            #expect(output.contains("margin: 0;"))
            #expect(output.contains("height: auto;"))
            #expect(output.contains("grid-column: auto;"))
            #expect(!output.contains("{{"))
            #expect(output.range(of: #":\s*;"#, options: .regularExpression) == nil)
        }
    }

    @Test func sectionSeparatesContentConstraintFromBackground() throws {
        #expect(try css("Section").contains("max-width: 1120px;"))
        #expect(try css("Section", values: ["constrainContent": .boolean(false)]).contains("max-width: none;"))
        #expect(try package("Section").htmlTemplate.contains("foundry-section-content"))
    }

    @Test func columnsResetPairWidthsAtOtherBreakpoints() throws {
        let pair = try css("Columns", values: ["proportions": .string("1-2")])
        #expect(pair.contains("* 1 / 3)"))
        #expect(pair.contains("* 2 / 3)"))
        let single = try css("Columns", values: ["columnCount": .number(1), "proportions": .string("1-2")])
        #expect(!single.contains("* 1 / 3)"))
        #expect(single.components(separatedBy: "flex-basis: calc((100% - (1 - 1)").count == 3)
    }

    @Test func gridAutoFitCannotDemandMoreThanAvailableWidth() throws {
        let output = try css("Grid", values: ["gridMode": .string("auto")])
        #expect(output.contains("repeat(auto-fit, minmax(min(100%, 240px), 1fr))"))
        #expect(try css("Grid").contains("repeat(2, minmax(0, 1fr))"))
        #expect(output.contains("grid-column: 1 / -1"))
    }

    @Test func bundledLayoutsRenderThroughTheCanvasPipeline() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        for name in names {
            let type = PartType(rawValue: "foundry.layout.\(name.lowercased())")
            #expect(type.definition.package?.manifest.version == "1.2.0")
            var node = PartNode.make(type)
            node.children = [.make(.paragraph)]
            let page = Page(title: "Layout", slug: "index", parts: [node])
            for breakpoint in [ResponsiveBreakpoint.mobile, .medium, .large] {
                let html = HTMLPageRenderer().render(page: page, language: "en", theme: .standard, assets: [:], breakpoint: breakpoint)
                #expect(html.contains("foundry-\(name.lowercased())"))
                #expect(!html.contains("{{ control."))
                #expect(html.contains("padding:"))
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func webKitMeasuresGridAndProportionalColumns() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        defer { web.stopLoading() }
        for (name, width) in [("Grid", 180), ("Grid", 800), ("Columns", 800)] {
            let token = UUID().uuidString
            let style = try css(name, values: ["gridMode": .string("auto"), "proportions": .string("1-2"), "spacingEnabled": .boolean(false)])
                .replacingOccurrences(of: ":instance", with: "#layout")
            web.loadHTMLString("""
                <html data-test="\(token)"><head><style>
                body { margin:0; width:\(width)px; } \(style)
                #layout > div { height:30px; background:#777; }
                </style></head><body><div id="layout"><div>A</div><div>B</div></div></body></html>
                """, baseURL: nil)
            var ready = false
            for _ in 0..<200 {
                ready = (try? await web.evaluateJavaScript("document.readyState === 'complete' && document.documentElement.dataset.test === '\(token)'")) as? Bool == true
                if ready { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(ready)
            let sizes = try #require(try await web.evaluateJavaScript("""
                (() => { const e=document.querySelector('#layout'); return [e.clientWidth,e.scrollWidth,
                e.children[0].getBoundingClientRect().width,e.children[1].getBoundingClientRect().width]; })()
                """) as? [Double])
            #expect(sizes[1] <= sizes[0] + 1)
            if name == "Columns" { #expect(abs(sizes[3] - sizes[2] * 2) < 1) }
            if name == "Grid" && width == 180 { #expect(abs(sizes[2] - 180) < 1) }
        }
    }
}
