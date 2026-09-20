import Foundation
import Testing
import WebKit
@testable import Foundry

@Suite("Built-in layout parts", .serialized)
@MainActor
struct BuiltInLayoutPartsTests {
    private let names = ["Section", "Container", "Stack", "Grid"]

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
            let properties = loaded.manifest.resolvedProperties
            #expect(Set(loaded.manifest.controlGroups.map(\.type)) == Set(PartPackageControlGroup.Kind.allCases))
            #expect(Set(loaded.manifest.controlGroups.map(\.type)).count == loaded.manifest.controlGroups.count)
            for (id, group) in [("widthMode", "Sizing"), ("frameworkPadding", "Spacing"),
                                ("frameworkMargin", "Spacing"), ("backgroundColor", "Background"),
                                ("frameworkRadius", "Borders"), ("flexGrow", "Layout item")] {
                #expect(properties.first { $0.id == id }?.group == group)
            }
            #expect(properties.first { $0.id == "frameworkPadding" }?.visibleWhen?.id == "spacingEnabled")
            #expect(properties.first { $0.id == "frameworkMargin" }?.visibleWhen?.id == "spacingEnabled")
            #expect(Set(properties.map(\.id)).count == properties.count)
        }
    }

    private func css(_ name: String, values overrides: [String: PartPackageValue] = [:]) throws -> String {
        let loaded = try package(name)
        var values: [String: PartPackageValue] = [
            "widthMode": .string("full"), "customWidth": .number(320), "maxWidth": .number(0),
            "minimumHeight": .number(0), "heightMode": .string("auto"), "customHeight": .number(400),
            "spacingEnabled": .boolean(true), "frameworkPadding": .string("16px"), "frameworkMargin": .string("0"),
            "overflow": .string("visible"), "itemEnabled": .boolean(false), "showsBackground": .boolean(false),
            "frameworkBorder.width": .string("0"), "frameworkBorder.style": .string("solid"),
            "frameworkBorderColour": .string("black"), "frameworkRadius": .string("0"),
            "frameworkGap": .string("16px"), "frameworkGap.value": .number(16), "rowGap": .string("16px"),
            "direction": .string("column"), "wrap": .string("nowrap"), "justifyContent": .string("flex-start"),
            "alignItems": .string("stretch"), "alignContent": .string("normal"), "verticalAlignment": .string("start"),
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

    @Test func backgroundGroupRendersEveryGradientType() throws {
        let common: [String: PartPackageValue] = [
            "backgroundMode": .string("static"),
            "backgroundStyle": .string("gradient"),
            "backgroundGradientDirection": .string("to right"),
            "backgroundGradientFrom": .string("#112233"),
            "backgroundGradientFromPosition": .number(0),
            "backgroundGradientTo": .string("#AABBCC"),
            "backgroundGradientToPosition": .number(100)
        ]

        for type in ["linear", "radial", "conic"] {
            var values = common
            values["backgroundGradientType"] = .string(type)
            let loaded = try package("Section")
            let output = PartTemplateRenderer.render(
                loaded.manifest.controlGroupCSS,
                context: PartTemplateContext(
                    instanceID: UUID(),
                    packageIdentifier: loaded.manifest.identifier,
                    properties: values,
                    slots: [:]
                )
            )
            #expect(output.contains("background-image: \(type)-gradient("))
            #expect(!output.contains("{{"))
        }
    }

    @Test func backgroundGroupRetainsStaticBackgroundWhileEditingAndRenderingHover() throws {
        let loaded = try package("Section")
        let values: [String: PartPackageValue] = [
            "backgroundMode": .string("hover"),
            "backgroundStyle": .string("color"),
            "backgroundColor": .string("#112233"),
            "backgroundHoverStyle": .string("gradient"),
            "backgroundHoverGradientType": .string("radial"),
            "backgroundHoverGradientFrom": .string("#445566"),
            "backgroundHoverGradientFromPosition": .number(0),
            "backgroundHoverGradientTo": .string("#AABBCC"),
            "backgroundHoverGradientToPosition": .number(100)
        ]
        let output = PartTemplateRenderer.render(
            loaded.manifest.controlGroupCSS,
            context: .init(instanceID: UUID(), packageIdentifier: loaded.manifest.identifier, properties: values, slots: [:])
        )

        #expect(output.contains("background-color: #112233;"))
        #expect(output.contains(#"[data-foundry-control-group-background=""#))
        #expect(output.contains("\"]:hover"))
        #expect(output.contains("background-image: radial-gradient(#445566 0%, #AABBCC 100%);"))
        #expect(loaded.manifest.resolvedProperties.first { $0.id == "backgroundMode" }?.control.presentation == .segmented)
        #expect(loaded.manifest.resolvedProperties.first { $0.id == "backgroundStyle" }?.control.options?.first?.systemImage == "paintbrush.fill")
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
            let identifier = name == "Stack" ? "flex" : name.lowercased()
            let type = PartType(rawValue: "foundry.layout.\(identifier)")
            #expect(type.definition.package?.manifest.version == "2.0.0")
            var node = PartNode.make(type)
            node.children = [.make(.paragraph)]
            let page = Page(title: "Layout", slug: "index", parts: [node])
            for breakpoint in [ResponsiveBreakpoint.mobile, .medium, .large] {
                let html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: [:], breakpoint: breakpoint)
                #expect(html.contains("foundry-\(identifier)"))
                #expect(!html.contains("{{ control."))
                #expect(html.contains("padding:"))
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func webKitMeasuresResponsiveGrid() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        defer { web.stopLoading() }
        for (name, width) in [("Grid", 180), ("Grid", 800)] {
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
            if name == "Grid" && width == 180 { #expect(abs(sizes[2] - 180) < 1) }
        }
    }
}
