import Foundation
import Testing
@testable import Foundry

struct BuiltInLayoutPartsTests {
    private static let partsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts")

    private func package(_ name: String) throws -> LoadedPartPackage {
        try PartPackageLoader.load(from: Self.partsRoot.appending(path: name))
    }

    @Test
    func layoutPartsShareOneInspectorContract() throws {
        let expectedSharedSections = [
            "Sizing", "Spacing", "Background", "Borders", "Effects", "Filters", "Transforms", "Transitions", "Layout", "Reveal", "Link"
        ]
        let parts = [
            (directory: "Container", section: "Container"),
            (directory: "Flexbox", section: "Flexbox"),
            (directory: "FlexItem", section: "Flex Item"),
            (directory: "Grid", section: "Grid"),
            (directory: "GridItem", section: "Grid Item")
        ]

        for part in parts {
            let manifest = try package(part.directory).manifest
            #expect(manifest.controlSections.map(\.name) == [part.section] + expectedSharedSections)
            #expect(manifest.controlGroups.last?.type == .advanced)
        }
    }

    @Test(arguments: ["Container", "Flexbox", "FlexItem", "Grid", "GridItem"])
    func videoBackgroundsOptInAndKeepAPositionedHost(_ name: String) throws {
        let manifest = try package(name).manifest
        let group = try #require(manifest.controlGroups.first { $0.type == .background })
        #expect(group.backgroundTypes.contains(.video))
        let position = try #require(manifest.resolvedProperties.first { $0.id == "layout.position" })
        #expect(position.control.options?.map(\.value) == ["relative", "absolute", "fixed", "sticky"])
        for selected in ["none", "static", "relative", "absolute", "fixed", "sticky"] {
            var values: [String: PartPackageValue] = ["layout.position": .string(selected)]
            PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
            let expected = ["none", "static"].contains(selected) ? "relative" : selected
            #expect(values["layout.css"]?.stringValue.contains("position: \(expected);") == true)
        }
    }

    @Test
    func layoutPartsUseNeutralResponsiveDefaults() throws {
        let flexItem = try package("FlexItem").manifest
        #expect(flexItem.resolvedProperties.first { $0.id == "flexSize" }?.defaultValue == .string("fit"))

        let grid = try package("Grid").manifest
        #expect(grid.resolvedProperties.first { $0.id == "gridMode" }?.defaultValue == .string("auto"))
        #expect(grid.resolvedProperties.first { $0.id == "alignItems" }?.defaultValue == .string("normal"))
        #expect(grid.resolvedProperties.first { $0.id == "justifyItems" }?.defaultValue == .string("normal"))
    }

    @Test
    func sharedLinkGroupUsesNamespacedFieldsAndReadsLegacyValues() throws {
        let manifest = try package("Container").manifest
        #expect(manifest.resolvedProperties.contains { $0.id == "link.destination" })
        #expect(manifest.resolvedProperties.contains { $0.id == "link.accessibleName" })
        #expect(!manifest.resolvedProperties.contains { $0.id == "destination" })
        #expect(manifest.controlGroups.contains { $0.type == .linkOverlay && $0.id == "link" })

        var node = PartNode.make(.container)
        node.properties.removeAll { $0.key.rawValue.hasPrefix("link.") }
        node.setProperty(.init(rawValue: "destination"), value: .url("https://example.com"))
        node.setProperty(.init(rawValue: "linkLabel"), value: .string("Example"))
        #expect(node.propertyValue(.init(rawValue: "link.destination")).stringValue == "https://example.com")
        #expect(node.propertyValue(.init(rawValue: "link.accessibleName")).stringValue == "Example")

        node.setProperty(.init(rawValue: "link.destination"), value: .link(.init(destination: .none)))
        #expect(!node.properties.contains { $0.key.rawValue == "destination" })
    }

    @Test
    func layoutPartPackagesAndTemplatesValidate() throws {
        for directory in ["Container", "Flexbox", "FlexItem", "Grid", "GridItem"] {
            let loaded = try package(directory)
            let diagnostics = PartPackageValidator.validate(
                loaded.manifest,
                rootURL: loaded.rootURL.appending(path: "Resources")
            )
            #expect(diagnostics.filter { $0.severity == .error }.isEmpty, "\(directory): \(diagnostics)")
        }
    }

    @Test @MainActor
    func linkGroupAutomaticallyDecoratesCanvasAndExportAndClearsCleanly() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        for name in ["Container", "Flexbox", "FlexItem", "Grid", "GridItem", "Image"] {
            let loaded = try package(name)
            var part = PartNode.make(.init(rawValue: loaded.manifest.identifier))
            part.setProperty(.init(rawValue: "link.destination"), value: "https://example.com/card")
            part.setProperty(.init(rawValue: "link.accessibleName"), value: "Read the card")
            func outputs(_ part: PartNode) -> [String] {
                let site = Site(name: "Links", pages: [Page(title: "Home", slug: "index", parts: [part])])
                return [
                    HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework),
                    StaticSiteRenderer().render(site: site, assets: [:]).files.map(\.contents).joined()
                ]
            }
            for output in outputs(part) {
                #expect(output.components(separatedBy: "data-foundry-root-link=\"link\"").count == 2, "\(name): exactly one converted root")
                #expect(!output.contains("foundry-stretched-link"))
                #expect(output.contains("aria-label=\"Read the card\""))
                #expect(output.contains("href=\"https://example.com/card\""))
                #expect(output.contains(":focus-visible"))
                #expect(!output.contains(":instance"))
            }
            part.setProperty(.init(rawValue: "link.destination"), value: "")
            for output in outputs(part) {
                #expect(!output.contains("data-foundry-root-link=\"link\""))
            }
        }
    }
}
