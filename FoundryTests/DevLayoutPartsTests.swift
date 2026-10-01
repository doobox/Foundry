import Foundation
import Testing
@testable import Foundry

/// Local smoke tests: these packages are deliberately outside the built-in pack.
struct DevLayoutPartsTests {
    private static let root = FileManager.default.homeDirectoryForCurrentUser.appending(path:
        "Library/Application Support/Foundry/Packs/Layout.foundrydevpack/Parts")

    private func package(_ name: String) throws -> LoadedPartPackage {
        let package = try PartPackageLoader.load(from: Self.root.appending(path: name))
        try package.preparePayload()
        return package
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)))
    @MainActor func incrementalCanvasMatchesFreshRenderingAfterChanges() throws {
        let packages = try ["Grid", "GridItem"].map(package)
        for package in packages { PartRegistry.register(package) }
        defer { for package in packages { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) } }
        let cache = CanvasRenderCache()
        var grid = PartNode.make(.init(rawValue: "uk.co.doobox.grid"))
        var child = PartNode.make(.init(rawValue: "uk.co.doobox.griditem"))
        child.slotID = "content"
        grid.children.append(child)
        var site = Site(name: "Incremental", pages: [Page(title: "Home", slug: "index", parts: [grid])])
        func verify(_ site: Site, appearance: SiteAppearance = .light, breakpoint: ResponsiveBreakpoint = .extraLarge, revision: Int = 0) {
            let cached = HTMLPageRenderer(site: site, appearance: appearance, artifactCache: cache, packageRevision: revision)
                .render(page: site.pages[0], language: site.language, framework: site.framework, assets: [:], breakpoint: breakpoint)
            let fresh = HTMLPageRenderer(site: site, appearance: appearance)
                .render(page: site.pages[0], language: site.language, framework: site.framework, assets: [:], breakpoint: breakpoint)
            #expect(cached == fresh)
        }
        verify(site)
        verify(site)
        site.pages[0].parts[0].setProperty(.init(rawValue: "columnCount"), value: .number(4))
        verify(site)
        site.pages[0].parts[0].children[0].setProperty(.init(rawValue: "columnSpan"), value: .number(2))
        verify(site)
        site.pages[0].parts[0].children.reverse()
        verify(site)
        site.pages[0].parts[0].children.removeLast()
        verify(site)
        site.pages[0].title = "Renamed"
        verify(site)
        verify(site, appearance: .dark)
        verify(site, breakpoint: .mobile)
        verify(site, revision: 1)
        let before = cache.statistics.misses
        site.framework = .standard
        site.pages[0].metadata.description = "Context changed"
        verify(site, revision: 1)
        #expect(cache.statistics.misses > before)
    }

    private func css(_ package: LoadedPartPackage, overrides: [String: PartPackageValue] = [:]) -> String {
        var values = Dictionary(uniqueKeysWithValues: package.manifest.resolvedProperties.map { ($0.id, $0.defaultValue) })
        values.merge(overrides) { _, new in new }
        PartPackageControlGroupCSSResolver.resolve(&values, properties: package.manifest.resolvedProperties)
        return PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier, properties: values, slots: [:]))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)))
    @MainActor func childInsertionRenderTimings() throws {
        let packages = try ["Grid", "GridItem"].map(package)
        for package in packages { PartRegistry.register(package) }
        defer { for package in packages { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) } }
        let gridType = PartType(rawValue: "uk.co.doobox.grid")
        let itemType = PartType(rawValue: "uk.co.doobox.griditem")
        var measurements: [String] = []
        for iteration in 0..<5 {
            var grid = PartNode.make(gridType)
            var second = PartNode.make(itemType)
            second.slotID = "content"
            grid.children.append(second)
            let site = Site(name: "Insertion timing", pages: [Page(title: "Home", slug: "index", parts: [grid])])
            let document = FoundryDocument(site: site)
            let editor = ProjectEditor(document: document, undoManager: nil)
            let clock = ContinuousClock()
            let insertionStart = clock.now
            let inserted = editor.insertPart(type: itemType, on: site.pages[0].id, placement: .insideSlot(grid.id, "content"))
            let insertionTime = insertionStart.duration(to: clock.now)
            let insertedID = try #require(inserted)
            let updated = document.site
            let renderer = HTMLPageRenderer(site: updated)
            let pageStart = clock.now
            let html = renderer.render(page: updated.pages[0], framework: updated.framework)
            let pageTime = pageStart.duration(to: clock.now)
            let subtreeStart = clock.now
            let subtree = renderer.renderSubtree(partID: grid.id, page: updated.pages[0], framework: updated.framework,
                assets: document.assetContents, breakpoint: .mobile)
            let subtreeTime = subtreeStart.duration(to: clock.now)
            #expect(html.contains(insertedID.uuidString))
            #expect(subtree?.html.contains(insertedID.uuidString) == true)
            measurements.append("Run \(iteration + 1): insertion=\(insertionTime), page HTML=\(pageTime), parent HTML=\(subtreeTime)")
        }
        Attachment.record(measurements.joined(separator: "\n"), named: "child-insertion-timings.txt")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)))
    @MainActor func layoutPageScalingTimings() throws {
        let packages = try ["Grid", "GridItem"].map(package)
        for package in packages { PartRegistry.register(package) }
        defer { for package in packages { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) } }
        var measurements: [String] = []
        for count in [1, 10, 30] {
            var grid = PartNode.make(.init(rawValue: "uk.co.doobox.grid"))
            grid.children = (0..<count).map { _ in
                var child = PartNode.make(.init(rawValue: "uk.co.doobox.griditem"))
                child.slotID = "content"
                return child
            }
            let site = Site(name: "Scaling", pages: [Page(title: "Home", slug: "index", parts: [grid])])
            let renderer = HTMLPageRenderer(site: site)
            let clock = ContinuousClock()
            let start = clock.now
            let html = renderer.render(page: site.pages[0], framework: site.framework)
            let fullTime = start.duration(to: clock.now)
            let leafStart = clock.now
            let leaf = renderer.renderSubtree(partID: grid.children[0].id, page: site.pages[0], framework: site.framework,
                assets: [:], breakpoint: .extraLarge)
            let leafTime = leafStart.duration(to: clock.now)
            let exportStart = clock.now
            let export = StaticSiteRenderer().render(site: site)
            let exportTime = exportStart.duration(to: clock.now)
            #expect(html.isEmpty == false)
            #expect(leaf != nil)
            #expect(export.files.isEmpty == false)
            measurements.append("\(count) children: canvas=\(fullTime), leaf=\(leafTime), export=\(exportTime)")
        }
        Attachment.record(measurements.joined(separator: "\n"), named: "layout-scaling-timings.txt")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)),
          arguments: ["Container", "Flexbox", "Grid", "FlexItem", "GridItem"])
    func packagesValidateAndHiddenWins(_ name: String) throws {
        let package = try package(name)
        let diagnostics = PartPackageValidator.validate(package.manifest, rootURL: package.rootURL.appending(path: "Resources"))
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty)
        if name == "Flexbox" || name == "Grid" {
            #expect(package.dropZoneNames.isEmpty)
            #expect(package.manifest.slots.map(\.id) == ["content"])
        } else {
            #expect(package.dropZoneNames == ["content"])
        }
        #expect(package.htmlTemplate.components(separatedBy: "{{ part.class }}").count == 2)
        #expect(package.htmlTemplate.components(separatedBy: "{{ part.attributes }}").count == 2)
        let rendered = css(package, overrides: ["layout.hidden": .boolean(true)])
        #expect(rendered.contains("{{") == false)
        let rootBody = try #require(rendered.components(separatedBy: "}").first)
        let hidden = try #require(rootBody.range(of: "display: none;"))
        let structuralDisplay = try #require(rootBody.range(of: "display: "))
        #expect(hidden.lowerBound > structuralDisplay.lowerBound)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)), arguments: ["grid", "flex"])
    func itemsExposeOnlyTheirOwnPlacementControls(_ mode: String) throws {
        let package = try package(mode == "grid" ? "GridItem" : "FlexItem")
        let properties = package.manifest.resolvedProperties
        #expect(package.manifest.showsInPartLibrary == false)
        #expect(package.manifest.allowedParents == [mode == "grid" ? "uk.co.doobox.grid" : "uk.co.doobox.flexbox"])
        #expect(properties.contains { $0.id == "itemType" } == false)
        for id in ["columnSpan", "rowSpan", "columnStart", "rowStart", "gridAlign", "gridJustify"] {
            #expect(properties.contains { $0.id == id } == (mode == "grid"))
        }
        for id in ["flexSize", "flexGrow", "flexShrink", "flexBasis", "flexAlign"] {
            #expect(properties.contains { $0.id == id } == (mode == "flex"))
        }
        let rendered = css(package, overrides: [
            "columnSpan": .number(2), "rowSpan": .number(3),
            "columnStart": .number(0), "rowStart": .number(4), "flexSize": .string("custom"), "flexGrow": .number(2),
            "flexShrink": .number(0), "flexBasis": .string("12rem"), "contentGap": .string("0px")
        ])
        if mode == "grid" {
            #expect(rendered.contains("grid-column: auto / span 2;"))
            #expect(rendered.contains("grid-row: 4 / span 3;"))
            #expect(rendered.contains("flex: 2") == false)
        } else {
            // Custom exposes the raw values, written after the sizing group's reset.
            let growth = try #require(rendered.range(of: "flex: 2 0 12rem;"))
            let sizingReset = try #require(rendered.range(of: "flex-grow: 0;"))
            #expect(growth.lowerBound > sizingReset.lowerBound)
            #expect(rendered.contains("grid-column:") == false)
            #expect(rendered.contains("grid-row:") == false)
        }
        #expect(rendered.contains("width: stretch;") == false)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)), arguments: ["count", "auto"])
    func gridColumnModesRender(_ mode: String) throws {
        let rendered = css(try package("Grid"), overrides: ["gridMode": .string(mode), "columnCount": .number(3), "minimumColumnWidth": .number(240)])
        #expect(rendered.contains(mode == "auto"
            ? "repeat(auto-fit, minmax(min(100%, 240px), 1fr))"
            : "repeat(3, minmax(0, 1fr))"))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)), arguments: ["row", "row dense"])
    func gridPlacementRendersAutoFlow(_ flow: String) throws {
        let rendered = css(try package("Grid"), overrides: ["autoFlow": .string(flow)])
        #expect(rendered.contains("grid-auto-flow: \(flow);"))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)),
          arguments: [("fit", "0 1 auto"), ("fill", "1 1 auto"), ("equal", "1 1 0%")])
    func flexItemSizePresetsRender(_ preset: String, _ flex: String) throws {
        let rendered = css(try package("FlexItem"), overrides: ["flexSize": .string(preset)])
        #expect(rendered.contains("flex: \(flex);"))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.appending(path: "Columns/manifest.json").path)),
          arguments: ["Columns", "Box"])
    func simpleLayoutPartsValidate(_ name: String) throws {
        let package = try package(name)
        let diagnostics = PartPackageValidator.validate(package.manifest, rootURL: package.rootURL.appending(path: "Resources"))
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(package.dropZoneNames == (name == "Columns" ? ["column1", "column2", "column3", "column4"] : ["content"]))
        #expect(css(package).contains("{{") == false)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.appending(path: "Columns/manifest.json").path)),
          arguments: [("33-67", "minmax(0, 1fr) minmax(0, 2fr)", 3), ("thirds", "repeat(3, minmax(0, 1fr))", 4),
                      ("quarters", "repeat(4, minmax(0, 1fr))", 0)])
    func columnsLayoutsSetTracksAndHideUnusedColumns(_ layout: String, _ tracks: String, _ firstHidden: Int) throws {
        let package = try package("Columns")
        let side = css(package, overrides: ["layout": .string(layout), "stacked": .boolean(false)])
        #expect(side.contains("grid-template-columns: \(tracks);"))
        #expect(side.contains("nth-child(n+\(firstHidden))") == (firstHidden > 0))
        let stacked = css(package, overrides: ["layout": .string(layout), "stacked": .boolean(true)])
        #expect(stacked.contains("grid-template-columns: minmax(0, 1fr);"))
        // New Columns stack on phones and sit side by side from tablets up.
        let stackedDefault = try #require(package.manifest.resolvedProperties.first { $0.id == "stacked" })
        #expect(stackedDefault.defaultValue == .boolean(true))
        #expect(stackedDefault.breakpointDefaults["medium"] == .boolean(false))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.appending(path: "Box/manifest.json").path)))
    func boxStacksItsContentAndStartsPadded() throws {
        let package = try package("Box")
        let rendered = css(package)
        #expect(rendered.contains("flex-direction: column;"))
        #expect(rendered.contains("position: relative;"))
        #expect(rendered.contains("align-items: stretch;"))
        #expect(package.manifest.resolvedProperties.first { $0.id == "spacing.spacingEnabled" }?.defaultValue == .boolean(true))
    }

    /// Row count 0 is the slider's "Auto" setting: rows size to their content.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)), arguments: [0.0, 4.0])
    func gridRowCountRendersAutoOrFixedRows(_ rowCount: Double) throws {
        let rendered = css(try package("Grid"), overrides: ["rowCount": .number(rowCount)])
        #expect(rendered.contains("grid-template-rows: repeat(4, minmax(0, 1fr));") == (rowCount == 4))
        #expect(rendered.contains("grid-template-rows") == (rowCount > 0))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path)))
    @MainActor func nestedPartsRenderInCanvasAndExport() throws {
        let packages = try ["Container", "Flexbox", "Grid", "FlexItem", "GridItem"].map(package)
        for package in packages { PartRegistry.register(package) }
        defer { for package in packages { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) } }
        var group = PartNode(type: PartType(rawValue: "uk.co.doobox.griditem"))
        group.setResponsiveProperty(.init(rawValue: "columnSpan"), value: .number(2), at: .medium)
        var grid = PartNode(type: PartType(rawValue: "uk.co.doobox.grid"))
        group.slotID = "content"
        grid.children = [group]
        var flex = PartNode(type: PartType(rawValue: "uk.co.doobox.flexbox"))
        var flexGroup = PartNode(type: PartType(rawValue: "uk.co.doobox.flexitem"))
        flexGroup.slotID = "content"
        flex.children = [flexGroup]
        var container = PartNode(type: PartType(rawValue: "uk.co.doobox.container"))
        container.children = [grid, flex]
        // Child pickers seed the matching hidden item using the existing API.
        let seededGrid = PartNode.make(PartType(rawValue: "uk.co.doobox.grid"))
        let seededFlex = PartNode.make(PartType(rawValue: "uk.co.doobox.flexbox"))
        #expect(seededGrid.children.map { $0.type.rawValue } == Array(repeating: "uk.co.doobox.griditem", count: 3))
        #expect(seededFlex.children.map { $0.type.rawValue } == Array(repeating: "uk.co.doobox.flexitem", count: 3))
        #expect(seededGrid.children.first?.slotID == "content")
        #expect(seededFlex.children.first?.slotID == "content")
        var tree = [container, seededGrid, seededFlex]
        // Reject cross-layout, page-root, and before/after sibling bypasses.
        #expect(tree.accepts(group, at: .inside(flex.id)) == false)
        #expect(tree.accepts(flexGroup, at: .inside(grid.id)) == false)
        #expect(tree.accepts(group, at: .end) == false)
        #expect(tree.accepts(flexGroup, at: .inside(container.id)) == false)
        #expect(tree.accepts(group, at: .before(flexGroup.id)) == false)
        #expect(tree.moveNode(withID: group.id, to: .insideSlot(flex.id, "content")) == false)
        #expect(tree.moveNode(withID: flexGroup.id, to: .insideSlot(grid.id, "content")) == false)
        // Ordinary content can go straight into either layout, or inside an item.
        let ordinary = PartNode(type: .paragraph)
        #expect(tree.accepts(ordinary, at: .insideSlot(grid.id, "content")))
        #expect(tree.accepts(ordinary, at: .insideSlot(flex.id, "content")))
        #expect(tree.accepts(ordinary, at: .inside(group.id)))
        #expect(tree.accepts(ordinary, at: .inside(flexGroup.id)))
        let movedGridItem = tree.moveNode(withID: group.id, to: .insideSlot(seededGrid.id, "content"))
        let movedFlexItem = tree.moveNode(withID: flexGroup.id, to: .insideSlot(seededFlex.id, "content"))
        #expect(movedGridItem)
        #expect(movedFlexItem)
        let site = Site(name: "Dev layouts", pages: [Page(title: "Home", slug: "index", parts: [container])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        let exported = StaticSiteRenderer().render(site: site)
        let output = exported.files.map(\.contents).joined(separator: "\n")
        for rendered in [canvas, output] {
            #expect(rendered.contains("grid-column: auto / span 2;"))
            #expect(rendered.contains("flex: 1 1 auto;"))
            #expect(rendered.contains("gap: 0px;"))
            #expect(rendered.contains("{{") == false)
        }
    }
}
