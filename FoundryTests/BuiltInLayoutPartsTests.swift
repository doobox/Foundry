import Foundation
import Testing
import WebKit
@testable import Foundry

@Suite("Built-in layout parts", .serialized)
@MainActor
struct BuiltInLayoutPartsTests {
    private let names = ["Container", "Flex", "Grid"]

    private func package(_ name: String) throws -> LoadedPartPackage {
        // The bundled container is a .foundrypack in releases but may be
        // renamed to .foundrydevpack while working on the built-in parts.
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources")
        let container = ["foundrypack", "foundrydevpack"]
            .map { resources.appending(path: "BuiltInParts.\($0)", directoryHint: .isDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let root = try #require(container).appending(path: "Parts/\(name)")
        return try PartPackageLoader.load(from: root)
    }

    @Test func allLayoutsValidateAndShareInspectorGroups() throws {
        for name in names {
            let loaded = try package(name)
            // Container keeps a plain drop zone; Flex and Grid declare their
            // child area as a childPicker slot so the inspector offers an
            // Add Item button for the matching item part.
            #expect(loaded.hasDropZone || !loaded.manifest.slots.isEmpty)
            let properties = loaded.manifest.resolvedProperties
            // Layouts share every value-producing group; the advanced group
            // (author-set ID/classes/attributes) is a per-part product choice
            // and no built-in opts in. The layout group (position, z-index,
            // offsets, display) is opt-in per part and none of the built-in
            // layouts wire its values yet. Container swaps the sizing group
            // for its own section semantics: an always-full-width root with a
            // Contained/Full content width and the group's height controls.
            let expectedKinds = Set(PartPackageControlGroup.Kind.allCases)
                .subtracting(name == "Container" ? [.advanced, .flexbox, .layout, .sizing] : [.advanced, .flexbox, .layout])
            #expect(Set(loaded.manifest.controlGroups.map(\.type)) == expectedKinds)
            #expect(Set(loaded.manifest.controlGroups.map(\.type)).count == loaded.manifest.controlGroups.count)
            let widthControl = name == "Container" ? "contentWidth" : "widthMode"
            for (id, group) in [(widthControl, "Sizing"), ("frameworkPadding", "Spacing"),
                                ("frameworkMargin", "Spacing"), ("backgroundColor", "Background"),
                                ("frameworkRadius", "Borders")] {
                #expect(properties.first { $0.id == id }?.group == group)
            }
            #expect(properties.first { $0.id == "heightMode" }?.group == "Sizing")
            #expect(properties.first { $0.id == "frameworkPadding" }?.visibleWhen?.id == "spacingEnabled")
            #expect(properties.first { $0.id == "frameworkMargin" }?.visibleWhen?.id == "spacingEnabled")
            #expect(Set(properties.map(\.id)).count == properties.count)
        }
    }

    @Test func flexAndGridOfferTheirItemPartsThroughAddItemSlots() throws {
        for (name, itemIdentifier) in [("Flex", "foundry.layout.flex-item"), ("Grid", "foundry.layout.grid-item")] {
            let slot = try #require(try package(name).manifest.slots.first)
            #expect(slot.id == "content")
            #expect(slot.pickerItems == [itemIdentifier])
            // The picker offers only the item part, but the area stays open
            // so any part can still be dropped in directly.
            #expect(slot.accepts == ["*"])
            #expect(slot.acceptsPart(.paragraph))
            #expect(slot.offersInPicker(PartType(rawValue: itemIdentifier)))
            #expect(!slot.offersInPicker(.paragraph))
        }
    }

    @Test func itemPartsAreHiddenHelpersPinnedToTheirParents() throws {
        for (folder, identifier) in [("FlexItem", "foundry.layout.flex-item"), ("GridItem", "foundry.layout.grid-item")] {
            let loaded = try package(folder)
            #expect(loaded.manifest.identifier == identifier)
            #expect(loaded.manifest.version == "1.0.0")
            // Items arrive through the parent's Add Item button or the part
            // library, and refuse parents they are meaningless in.
            #expect(loaded.hasDropZone)
            #expect(!loaded.manifest.permits(parent: .paragraph))
        }
        let flexItem = try package("FlexItem").manifest
        #expect(flexItem.permits(parent: .flex))
        #expect(flexItem.permits(parent: .flexItem))
        #expect(flexItem.permits(parent: .gridItem))
        #expect(flexItem.permits(parent: .container))
        #expect(!flexItem.permits(parent: .grid))
        let gridItem = try package("GridItem").manifest
        #expect(gridItem.permits(parent: .grid))
        #expect(!gridItem.permits(parent: .flex))
        #expect(!gridItem.permits(parent: .container))
    }

    @Test func itemPartsEmitAlwaysOnInParentCSS() throws {
        // No enable toggle: being an item is the part's whole job, so the
        // in-parent properties render unconditionally.
        let flexItem = try css("FlexItem", values: [
            "flexGrow": .number(2), "flexShrink": .number(0), "alignSelf": .string("center")
        ])
        #expect(flexItem.contains("flex-grow: 2"))
        #expect(flexItem.contains("flex-shrink: 0"))
        #expect(flexItem.contains("align-self: center;"))
        #expect(flexItem.contains("display: flex;"))
        #expect(!flexItem.contains("grid-column"))
        #expect(!flexItem.contains("{{"))

        let gridItem = try css("GridItem", values: [
            "columnSpan": .number(3), "rowSpan": .number(2)
        ])
        #expect(gridItem.contains("grid-column: span 3;"))
        #expect(gridItem.contains("grid-row: span 2;"))
        #expect(gridItem.contains("display: flex;"))
        #expect(!gridItem.contains("flex-grow"))
        #expect(!gridItem.contains("{{"))
    }

    @Test func navigationPartRendersMenuDropdownsAndCurrentState() async throws {
        // Loading throws if the pack fails validation; rendering resolves the
        // part through the shared catalog, which loads asynchronously.
        let loaded = try package("Navigation")
        await PartPackageCatalog.shared.waitUntilLoaded()

        let navigation = PartNode(type: PartType(rawValue: loaded.manifest.identifier))
        let about = Page(title: "About", slug: "about", order: 1)
        // Folders join menus by default as non-link groups; opting Archive
        // out keeps it organizational, its pages surfacing in place.
        let legal = PageFolder(name: "Legal", slug: "legal", order: 3)
        let archive = PageFolder(name: "Archive", slug: "archive", order: 4, includeInNavigation: false)
        var site = Site(
            name: "Nav",
            pages: [
                Page(title: "Home", slug: "index", parts: [navigation]),
                about,
                Page(title: "Team", slug: "team", parentPageID: about.id),
                Page(title: "Secret", slug: "secret", order: 2, includeInNavigation: false),
                Page(title: "Privacy", slug: "privacy", folderID: legal.id),
                Page(title: "Old News", slug: "old-news", folderID: archive.id)
            ]
        )
        site.pageFolders = [legal, archive]

        let html = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(html.contains("fd-navigation"))
        // The current page is marked, siblings link out, children nest in a
        // dropdown, and pages excluded from navigation never appear.
        #expect(html.contains("aria-current=\"page\""))
        #expect(html.contains(">About</a>"))
        #expect(html.contains("fd-navigation__dropdown"))
        #expect(html.contains(">Team</a>"))
        #expect(!html.contains(">Secret</a>"))
        #expect(html.contains("Site Name"))
        #expect(html.contains("data-navigation-toggle"))
        #expect(html.contains("@media (max-width: 767px)"))
        // A navigation folder renders as a non-link group label with its
        // pages in the dropdown; a plain folder's pages surface in place.
        #expect(html.contains(">Legal</span>"))
        #expect(!html.contains("href=\"\">Legal"))
        #expect(html.contains(">Privacy</a>"))
        #expect(html.contains(">Old News</a>"))
        #expect(!html.contains(">Archive<"))

        // Source: one folder's contents only — any folder is addressable by
        // slug, whether or not it joins the site navigation itself.
        var folderNavigation = navigation
        folderNavigation.setProperty(.init(rawValue: "source"), value: .choice("folder"))
        folderNavigation.setProperty(.init(rawValue: "sourceFolder"), value: .choice(archive.id.uuidString))
        site.pages[0].parts = [folderNavigation]
        let folderHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(folderHTML.contains(">Old News</a>"))
        #expect(!folderHTML.contains(">About</a>"))
        #expect(!folderHTML.contains(">Privacy</a>"))

        // Source: top level only — no dropdowns, no group labels.
        var topLevelNavigation = navigation
        topLevelNavigation.setProperty(.init(rawValue: "source"), value: .choice("topLevel"))
        site.pages[0].parts = [topLevelNavigation]
        let topLevelHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(topLevelHTML.contains(">About</a>"))
        #expect(!topLevelHTML.contains(">Team</a>"))
        #expect(!topLevelHTML.contains(">Legal<"))
    }

    private func css(_ name: String, values overrides: [String: PartPackageValue] = [:]) throws -> String {
        let loaded = try package(name)
        var values: [String: PartPackageValue] = [
            "widthMode": .string("full"), "customWidth": .number(320),
            "minWidth": .string("0"), "maxWidth": .string("none"), "maxWidth.value": .number(0),
            "minHeight": .string("0"), "maxHeight": .string("none"),
            "heightMode": .string("auto"), "customHeight": .number(400),
            "spacingEnabled": .boolean(true), "frameworkPadding": .string("16px"), "frameworkMargin": .string("0"),
            "overflow": .string("visible"), "itemEnabled": .boolean(false), "showsBackground": .boolean(false),
            "frameworkBorder.width": .string("0"), "frameworkBorder.style": .string("solid"),
            "frameworkBorderColour": .string("black"), "frameworkRadius": .string("0"),
            "frameworkGap": .string("16px"), "frameworkGap.value": .number(16), "rowGap": .string("16px"),
            "direction": .string("column"), "wrap": .string("nowrap"), "justifyContent": .string("flex-start"),
            "alignItems": .string("stretch"), "alignContent": .string("normal"), "verticalAlignment": .string("start"),
            "constrainContent": .boolean(true), "innerMaxWidth": .number(1120),
            "columnCount": .number(2), "proportions": .string("equal"), "gridMode": .string("count"),
            "rowSizing": .string("auto"), "justifyItems": .string("stretch"), "minimumColumnWidth": .number(240),
            "contentWidth": .string("contained"), "customContentWidth": .number(800),
            "contentAlignment": .string("flex-start"), "contentJustify": .string("stretch"), "contentGap": .string("0px")
        ]
        values.merge(overrides) { _, new in new }
        return PartTemplateRenderer.render(loaded.css, context: PartTemplateContext(
            instanceID: UUID(), packageIdentifier: loaded.manifest.identifier,
            properties: values, slots: [:]
        ))
    }

    @Test func fillRemainingSpaceGrowsIntoTheBodyColumn() throws {
        // The body is a min-height flex column, so filling leftover viewport
        // space is a flex-grow on the part root — and it must outrank the
        // layout-item group's flex-grow reset.
        for name in names {
            let output = try css(name, values: ["heightMode": .string("fill")])
            #expect(output.contains("flex: 1 1 auto;"))
            #expect(!output.contains("height: 100svh"))
        }
    }

    @Test func disabledSpacingAndSizingProduceExplicitResets() throws {
        for name in names {
            let output = try css(name, values: ["spacingEnabled": .boolean(false)])
            #expect(output.contains("padding: 0;"))
            #expect(output.contains("margin: 0;"))
            #expect(output.contains("height: auto;"))
            #expect(!output.contains("{{"))
            #expect(output.range(of: #":\s*;"#, options: .regularExpression) == nil)
        }
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
            let loaded = try package("Container")
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
        let loaded = try package("Container")
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
            let type = PartType(rawValue: "foundry.layout.\(name.lowercased())")
            #expect(type.definition.package?.manifest.version == (name == "Container" ? "2.3.0" : "2.2.0"))
            var node = PartNode.make(type)
            node.children = [.make(.paragraph)]
            let page = Page(title: "Layout", slug: "index", parts: [node])
            for breakpoint in [ResponsiveBreakpoint.mobile, .medium, .large] {
                let html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: [:], breakpoint: breakpoint)
                #expect(html.contains("foundry-\(name.lowercased())"))
                #expect(!html.contains("{{ control."))
                #expect(html.contains("padding:"))
            }
        }
    }

    @Test func itemPartsRenderInsideTheirParentsThroughTheCanvasPipeline() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var gridItem = PartNode.make(.gridItem)
        gridItem.setProperty(.init(rawValue: "columnSpan"), value: .number(2))
        gridItem.children = [.make(.heading)]
        var grid = PartNode.make(.grid)
        grid.children = [gridItem, .make(.gridItem)]

        var flexItem = PartNode.make(.flexItem)
        flexItem.setProperty(.init(rawValue: "flexGrow"), value: .number(3))
        flexItem.children = [.make(.paragraph)]
        var flex = PartNode.make(.flex)
        flex.children = [flexItem]

        let page = Page(title: "Items", slug: "index", parts: [grid, flex])
        let html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: [:], breakpoint: .large)
        #expect(html.contains("foundry-grid-item"))
        #expect(html.contains("grid-column: span 2;"))
        #expect(html.contains("foundry-flex-item"))
        #expect(html.contains("flex-grow: 3"))
        #expect(!html.contains("{{ control."))
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
