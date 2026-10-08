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
            "Sizing", "Spacing", "Background", "Borders", "Shadow", "Filters", "Transforms", "Transitions", "Layout", "Reveal", "Link"
        ]
        let parts = [
            (directory: "Section", section: "Section"),
            (directory: "Flexbox", section: "Stack"),
            (directory: "FlexItem", section: "Stack Item"),
            (directory: "Grid", section: "Grid"),
            (directory: "GridItem", section: "Grid Item"),
            (directory: "Box", section: "Box")
        ]

        for part in parts {
            let manifest = try package(part.directory).manifest
            #expect(manifest.controlSections.map(\.name) == [part.section] + expectedSharedSections)
            #expect(manifest.controlGroups.last?.type == .advanced)
        }
    }

    @Test(arguments: ["Section", "Flexbox", "FlexItem", "Grid", "GridItem", "Box"])
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

        let box = try package("Box")
        #expect(box.manifest.resolvedProperties.contains { $0.id == "contentAlignment" } == false)
        #expect(box.css.contains("align-items: flex-start;"))

        let grid = try package("Grid").manifest
        #expect(grid.resolvedProperties.first { $0.id == "gridMode" }?.defaultValue == .string("auto"))
        #expect(grid.resolvedProperties.first { $0.id == "alignItems" }?.defaultValue == .string("normal"))
        #expect(grid.resolvedProperties.first { $0.id == "justifyItems" }?.defaultValue == .string("normal"))

        for directory in ["Section", "Flexbox", "Grid", "Columns", "Box"] {
            let manifest = try package(directory).manifest
            let gapIDs = ["contentGap", "flexbox.rowGap", "rowGap", "gap"]
            #expect(manifest.resolvedProperties.contains {
                gapIDs.contains($0.id) && $0.defaultValue == .string("md")
            }, "\(directory) should own a medium default gap")
        }
    }

    @Test(arguments: ["flex-start", "center", "flex-end"])
    func gridItemContentAlignmentDoesNotChangeRootSizing(_ alignment: String) throws {
        let loaded = try package("GridItem")
        let properties = loaded.manifest.resolvedProperties
        #expect(properties.first { $0.id == "gridAlign" }?.defaultValue == .string("stretch"))
        #expect(properties.first { $0.id == "gridJustify" }?.defaultValue == .string("stretch"))
        let content = try #require(properties.first { $0.id == "contentAlignment" })
        #expect(content.defaultValue == .string("flex-start"))
        #expect(content.responsive)
        #expect(content.control.options?.map(\.title) == ["Top", "Centre", "Bottom"])
        var values = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0.defaultValue) })
        values["contentAlignment"] = .string(alignment)
        values["sizing.heightMode"] = .string("custom")
        values["sizing.customHeight"] = .number(320)
        PartPackageControlGroupCSSResolver.resolve(&values, properties: properties)
        let rendered = PartTemplateRenderer.render(loaded.css, context: .init(
            instanceID: UUID(), packageIdentifier: loaded.manifest.identifier, properties: values, slots: [:]))
        let rootRule = try #require(rendered.components(separatedBy: "}").first)
        #expect(rootRule.contains("height: 320px;"))
        #expect(rootRule.contains("align-self: stretch;"))
        #expect(rootRule.contains("justify-content:") == false)
        #expect(rendered.contains("justify-content: \(alignment);"))
        #expect(rendered.contains("flex: 1 1 auto;"))
        #expect(rendered.contains("{{") == false)
    }

    @Test
    func sharedLinkGroupUsesOnlyExactNamespacedFields() throws {
        let manifest = try package("Section").manifest
        #expect(manifest.resolvedProperties.contains { $0.id == "link.destination" })
        #expect(manifest.resolvedProperties.contains { $0.id == "link.accessibleName" })
        #expect(!manifest.resolvedProperties.contains { $0.id == "destination" })
        #expect(manifest.controlGroups.contains { $0.type == .linkOverlay && $0.id == "link" })

        var node = PartNode.make(.section)
        node.properties.removeAll { $0.key.rawValue.hasPrefix("link.") }
        node.setProperty(.init(rawValue: "destination"), value: .url("https://example.com"))
        node.setProperty(.init(rawValue: "linkLabel"), value: .string("Example"))
        #expect(node.storedPropertyValue(.init(rawValue: "link.destination")) == nil)
        #expect(node.storedPropertyValue(.init(rawValue: "link.accessibleName")) == nil)
        #expect(node.propertyValue(.init(rawValue: "link.destination")).stringValue.isEmpty)
        #expect(node.propertyValue(.init(rawValue: "link.accessibleName")).stringValue.isEmpty)

        node.setProperty(.init(rawValue: "link.destination"), value: .url("https://example.com/current"))
        node.setProperty(.init(rawValue: "link.accessibleName"), value: .string("Current"))
        #expect(node.propertyValue(.init(rawValue: "link.destination")).stringValue == "https://example.com/current")
        #expect(node.propertyValue(.init(rawValue: "link.accessibleName")).stringValue == "Current")
        #expect(node.storedPropertyValue(.init(rawValue: "destination")) == .url("https://example.com"))
        #expect(node.storedPropertyValue(.init(rawValue: "linkLabel")) == .string("Example"))
        node.setProperty(.init(rawValue: "link.destination"), value: .link(.init(destination: .none)))
        node.setProperty(.init(rawValue: "link.accessibleName"), value: .string(""))
        #expect(node.propertyValue(.init(rawValue: "link.destination")).stringValue.isEmpty)
        #expect(node.propertyValue(.init(rawValue: "link.accessibleName")).stringValue.isEmpty)
    }

    @Test
    func layoutPartPackagesAndTemplatesValidate() throws {
        for directory in ["Section", "Flexbox", "FlexItem", "Grid", "GridItem", "Box"] {
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
        for name in ["Section", "Flexbox", "FlexItem", "Grid", "GridItem", "Box", "Image"] {
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
