import Foundation
import Testing
@testable import Foundry

struct TransformsControlGroupTests {
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
        for name in ["Button", "Columns", "Container", "Copyright", "Divider", "FlexItem",
                     "Flexbox", "Grid", "GridItem", "Heading", "Image", "Navigation", "Paragraph", "Video"] {
            let package = try PartPackageLoader.load(from: root.appending(path:
                "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/" + name))
            #expect(package.manifest.controlGroups.contains { $0.type == .transforms })
            #expect(package.css.contains("control.transforms.css"))
            #expect(package.css.contains("control.transforms.hover.css"))
        }
    }

    @Test @MainActor func canvasAndExportResolveTheSameTransformValues() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Container"))
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
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
