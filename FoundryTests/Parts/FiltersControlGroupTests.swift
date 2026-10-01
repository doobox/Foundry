import Foundation
import Testing
@testable import Foundry

struct FiltersControlGroupTests {
    private func resolved(_ overrides: [String: PartPackageValue], namespace: String = "visual") -> [String: PartPackageValue] {
        let group = PartPackageControlGroup(type: .filters, id: namespace)
        var values = Dictionary(uniqueKeysWithValues: group.properties.map { ($0.id, $0.defaultValue) })
        for (key, value) in overrides { values[namespace + "." + key] = value }
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        return values
    }

    @Test(arguments: ["none", "static", "hover"])
    func neutralDefaultsDoNotCreateAFilterContainingBlock(mode: String) {
        let values = resolved(["filtersMode": .string(mode)])
        let reset = PartPackageValue.string("filter: none; backdrop-filter: none; -webkit-backdrop-filter: none;")
        #expect(values["visual.css"] == reset)
        #expect(values["visual.hover.css"] == reset)
    }

    @Test func staticMirrorsNormalValuesOnHover() {
        let values = resolved(["filtersMode": .string("static"), "filtersBlur": .number(6),
                               "filtersHoverBlur": .number(20), "filtersBackdropBlur": .number(12)])
        #expect(values["visual.css"] == values["visual.hover.css"])
        #expect(values["visual.css"]?.stringValue.contains("blur(6px)") == true)
        #expect(values["visual.css"]?.stringValue.contains("backdrop-filter: blur(12px)") == true)
    }

    @Test func hoveredValuesAreIndependentOfInspectorState() {
        for state in ["normal", "hover"] {
            let values = resolved(["filtersMode": .string("hover"), "filtersState": .string(state),
                                   "filtersBrightness": .number(80), "filtersHoverBrightness": .number(120)])
            #expect(values["visual.css"]?.stringValue.contains("brightness(80%)") == true)
            #expect(values["visual.hover.css"]?.stringValue.contains("brightness(120%)") == true)
        }
    }

    @Test func valuesAreClampedAndDisabledClearsBothStates() {
        let values = resolved(["filtersMode": .string("hover"), "filtersBlur": .number(-10),
                               "filtersHoverBlur": .number(900), "filtersHoverSaturate": .number(.infinity)])
        #expect(values["visual.css"]?.stringValue.hasPrefix("filter: none;") == true)
        #expect(values["visual.hover.css"]?.stringValue.contains("blur(100px)") == true)
        #expect(values["visual.hover.css"]?.stringValue.contains("saturate(100%)") == true)
        let disabled = resolved(["filtersMode": .string("none"), "filtersBlur": .number(40)])
        #expect(disabled["visual.css"]?.stringValue.hasPrefix("filter: none;") == true)
    }

    @Test func frameworkShadowsBecomeValidDropShadows() {
        let value = PartPackageShadowValue(source: PartFrameworkValueSelection.manualCustom, customLayers: [
            .init(x: 2, y: 4, blur: 12, spread: 9, color: "#112233", opacity: 0.5),
            .init(x: 0, y: 1, blur: 4, opacity: 0.5, isInset: true)
        ])
        let shadow = PartPackageShadowResolver.filter(value, framework: .standard)
        #expect(shadow == "drop-shadow(2px 4px 6px rgb(17 34 51 / 0.5))")
        let values = resolved(["filtersMode": .string("static"), "filtersShadow": .string(shadow)])
        #expect(values["visual.css"]?.stringValue.contains(shadow) == true)
        #expect(PartPackageShadowResolver.filter(.init(source: "none", customLayers: []), framework: .standard) == "none")
    }

    @Test func builtInPartsDeclareAndRenderBothFilterStates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Button", "Columns", "Container", "Copyright", "Divider", "FlexItem",
                     "Flexbox", "Grid", "GridItem", "Heading", "Image", "Navigation", "Paragraph", "Video"] {
            let package = try PartPackageLoader.load(from: root.appending(path:
                "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/" + name))
            #expect(package.manifest.controlGroups.contains { $0.type == .filters })
            #expect(package.css.contains("control.filters.css"))
            #expect(package.css.contains("control.filters.hover.css"))
        }
    }

    @Test @MainActor func canvasAndExportResolveTheSameFilterAndShadowValues() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Container"))
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var part = PartNode(type: .init(rawValue: package.manifest.identifier))
        part.setProperty(.init(rawValue: "filters.filtersMode"), value: .string("hover"))
        part.setProperty(.init(rawValue: "filters.filtersBlur"), value: .number(4))
        part.setProperty(.init(rawValue: "filters.filtersHoverBlur"), value: .number(9))
        part.setProperty(.init(rawValue: "filters.filtersShadow"), value: .packageShadow(.init(
            source: PartFrameworkValueSelection.manualCustom,
            customLayers: [.init(x: 2, y: 4, blur: 12, opacity: 0.5)]
        )))
        let site = Site(name: "Filter test", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        let export = StaticSiteRenderer().render(site: site, assets: [:])
        #expect(export.errors.isEmpty)
        let css = try #require(export.file(at: "files/page.css")?.contents)
        for output in [canvas, css] {
            #expect(output.contains("filter: blur(4px)"))
            #expect(output.contains("filter: blur(9px)"))
            #expect(output.contains("drop-shadow(2px 4px 6px rgb(0 0 0 / 0.5))"))
        }
    }
}
