import Foundation
import Testing
@testable import Foundry

@MainActor
struct PartDefinitionTests {
    init() {
        _ = PartPackageCatalog.shared
    }

    @Test
    func pageSerializationUsesPartsWithoutOldKeyFallback() throws {
        let page = Page(title: "Home", slug: "index", parts: [.make(.paragraph)])
        let data = try JSONEncoder().encode(page)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["parts"] != nil)
        #expect(object["components"] == nil)
        #expect(object["blocks"] == nil)
        #expect(try JSONDecoder().decode(Page.self, from: data) == page)
        for oldKey in ["components", "blocks"] {
            var oldObject = object
            oldObject[oldKey] = oldObject.removeValue(forKey: "parts")
            let oldData = try JSONSerialization.data(withJSONObject: oldObject)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Page.self, from: oldData)
            }
        }
    }

    @Test
    func definitionsHaveUniquePropertyKeysAndDefaults() {
        for type in PartType.allCases {
            let definition = type.definition
            let keys = definition.properties.map(\.key)

            #expect(definition.type == type)
            #expect(Set(keys).count == keys.count)
            #expect(PartNode.make(type).properties.count == definition.properties.count)
        }
    }

    @Test
    func registryDeclaresChildCapabilities() {
        #expect(PartType.container.definition.allowsChildren)
        #expect(PartType.flex.definition.allowsChildren)
        #expect(PartType.flexItem.definition.allowsChildren)
        #expect(PartType.grid.definition.allowsChildren)
        #expect(PartType.gridItem.definition.allowsChildren)
        #expect(!PartType.paragraph.definition.allowsChildren)
        #expect(!PartType.button.definition.allowsChildren)
        #expect(!PartType.image.definition.allowsChildren)
    }

    @Test
    func flexLayoutsUseFrameworkControlsAndResponsiveDefaults() throws {
        let container = PartNode.make(.container)
        let flex = PartNode.make(.flex)
        #expect(flex.propertyValue(.init(rawValue: "direction")) == .choice("row"))
        #expect(flex.type.definition.package!.css.contains("display: flex"))
        // Container is a section, not an arranger: its root never becomes a
        // flexbox; only the content wrapper does, and only for tall sections.
        #expect(container.type.definition.package!.css.contains("fd-container__content"))
        #expect(!flex.type.definition.package!.css.contains("data-alignment"))
        #expect(container.type.definition.package!.css.contains("box-shadow"))
        for type in [PartType.container, .flex, .grid] {
            #expect(type.definition.properties.contains { $0.key.rawValue == "frameworkPadding" && $0.isResponsive })
        }
        for type in [PartType.flex, .grid] {
            #expect(type.definition.properties.contains { $0.key.rawValue == "frameworkGap" && $0.isResponsive })
        }
        let grid = PartNode.make(.grid)
        #expect(grid.propertyValue(.init(rawValue: "columnCount")) == .number(1))
        #expect(grid.propertyValue(.init(rawValue: "columnCount"), at: .medium) == .number(2))
        let site = Site(name: "Grid", pages: [Page(title: "Layout", slug: "index", parts: [grid])])
        let output = StaticSiteRenderer().render(site: site)
        #expect(output.files.contains { $0.contents.contains("repeat(2, minmax(0, 1fr))") })
        #expect(output.files.contains { $0.contents.contains("var(--foundry-space-md)") })
        var unlimited = container
        unlimited.setProperty(.maxWidth, value: .number(0))
        let html = HTMLPageRenderer().render(page: Page(title: "Full", slug: "full", parts: [unlimited]), framework: .standard)
        #expect(html.contains("max-width: var(--foundry-container-width)"))
        #expect(!html.contains("max-width: 0px"))
        #expect(html.contains("background-color: transparent"))
    }

    @Test
    func stockRegistryUsesUniqueNamespacedIdentifiers() {
        let identifiers = [
            PartType.container,
            .flex,
            .grid,
            .paragraph,
            .heading,
            .button,
            .image,
            .divider
        ].map(\.rawValue)

        #expect(!identifiers.isEmpty)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.split(separator: ".").count >= 3 })
    }

    @Test
    func unknownPartIdentifiersDecodeWithoutAliases() throws {
        let unqualified = try JSONDecoder().decode(PartType.self, from: Data("\"container\"".utf8))
        let unknown = try JSONDecoder().decode(PartType.self, from: Data("\"com.example.gallery\"".utf8))

        #expect(unqualified.rawValue == "container")
        #expect(unqualified.definition.renderKind == .unavailable)
        #expect(unknown.rawValue == "com.example.gallery")
        #expect(unknown.definition.renderKind == .unavailable)
    }

    @Test
    func typedPropertiesRoundTripThroughJSON() throws {
        var original = PartNode.make(.paragraph)
        // Historical values remain readable even though these controls are gone.
        original.setProperty(.init(rawValue: "typeface"), value: .choice("body"))
        original.setProperty(.init(rawValue: "textSize"), value: .packageFontSize(.init(source: "base", customValue: "1rem")))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PartNode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.propertyValue(.init(rawValue: "typeface")) == .choice("body"))
        #expect(decoded.propertyValue(.init(rawValue: "textSize")) == .packageFontSize(.init(
            source: "base",
            customValue: "1rem"
        )))
        #expect(decoded.propertyValue(.init(rawValue: "textColor")) == .packageColor(.init(
            source: "text",
            customColor: "#000000",
            opacity: 1
        )))
    }

    @Test
    func missingStoredPropertiesUsePackageDefaults() {
        let text = PartNode(
            type: .paragraph,
            properties: [.init(key: .init(rawValue: "content"), value: .string("Hello"))]
        )

        #expect(!text.type.definition.properties.contains { ["typeface", "textSize"].contains($0.key.rawValue) })
        #expect(text.propertyValue(.init(rawValue: "textColor")) == .packageColor(.init(
            source: "text", customColor: "#000000", opacity: 1
        )))
    }

    @Test
    func packagePropertiesAreOrganizedIntoInspectorSections() {
        let buttonProperties = PartType.button.definition.properties

        #expect(buttonProperties.first(where: { $0.key.rawValue == "label" })?.section == .content)
        #expect(buttonProperties.first(where: { $0.key.rawValue == "textColor" })?.section == .typography)
        #expect(!buttonProperties.contains { $0.key.rawValue == "textSize" })
        #expect(buttonProperties.first(where: { $0.key == .backgroundColor })?.section == .appearance)
        #expect(buttonProperties.first(where: { $0.key == .destination })?.section == .link)
        #expect(buttonProperties.first(where: { $0.key == .accessibilityLabel })?.section == .accessibility)
    }

    @Test
    func rendererAppliesPackagePropertiesAndEscapesAccessibilityLabel() {
        var container = PartNode.make(.container)
        var stack = PartNode.make(.flex)
        var text = PartNode.make(.paragraph)
        var button = PartNode.make(.button)
        container.setProperty(.init(rawValue: "frameworkBorder.width"), value: .frameworkBorderWidth(PartPackageFrameworkBorderWidthControl.defaultValue(.object(["value": .number(2), "unit": .string("px")]))!))
        container.setProperty(.init(rawValue: "frameworkBorderColour"), value: .packageColor(.init(source: "custom", customColor: "#ABCDEF", opacity: 1)))
        container.setProperty(.init(rawValue: "frameworkRadius"), value: .frameworkRadius(PartPackageFrameworkRadiusControl.defaultValue(.object(["value": .number(28), "unit": .string("px")]))!))
        // Container roots are always full width; a Flex carries the shared
        // sizing group's max-width control.
        stack.setProperty(.maxWidth, value: .number(920))
        text.setProperty(.init(rawValue: "typeface"), value: .choice("heading"))
        text.setProperty(.init(rawValue: "textSize"), value: .packageFontSize(.init(
            source: "xl",
            customValue: "1rem"
        )))
        button.setProperty(.accessibilityLabel, value: .string("Open \"details\""))
        container.children = [text, button]

        let page = Page(title: "Test", slug: "test", parts: [container, stack])
        let html = HTMLPageRenderer().render(page: page, framework: .standard)

        #expect(html.contains("border-width: 2.0px"))
        #expect(html.contains("border-color: #ABCDEF"))
        #expect(html.contains("border-radius: 28.0px"))
        #expect(html.contains("920px"))
        // Paragraph now uses the dedicated font control, not the removed select extension.
        #expect(PartType.paragraph.definition.package!.css.contains("font-family: {{ control.font.family }}"))
        #expect(PartType.paragraph.definition.package!.css.contains("font-weight: {{ control.font.weight }}"))
        #expect(PartType.paragraph.definition.package!.css.contains("font-style: {{ control.font.style }}"))
        // Font size is opt-in: the framework size only emits when Custom Size is enabled.
        #expect(PartType.paragraph.definition.package!.css.contains("{{ if control.sizeEnabled }}"))
        #expect(PartType.paragraph.definition.package!.css.contains("font-size: {{ control.fontSize }}"))
        #expect(PartType.paragraph.definition.package!.css.contains("line-height: {{ control.fontSize.lineHeight }}"))
        #expect(html.contains("aria-label=\"Open &quot;details&quot;\""))
        #expect(html.contains("--foundry-editor-part: #007BFF"))
        #expect(html.contains("--foundry-editor-global: #30D158"))
    }

    @Test
    func rendererSupportsExpandedStockPartSet() {
        var grid = PartNode.make(.grid)
        grid.children = [PartNode.make(.heading), PartNode.make(.image)]
        let parts: [PartNode] = [
            PartNode(type: .flex, children: [grid]),
            PartNode.make(.divider)
        ]
        let html = HTMLPageRenderer().render(
            page: Page(title: "Parts", slug: "parts", parts: parts),
            framework: .standard
        )

        #expect(html.contains("class=\"foundry-flex"))
        #expect(html.contains("class=\"foundry-grid"))
        #expect(html.contains("<h2 class=\""))
        #expect(html.contains("class=\"foundry-image-part"))
        #expect(html.contains("class=\"foundry-divider"))
    }

    @Test
    func unknownPartRendersPlaceholderWithoutLosingChildren() {
        let unknownType = PartType(rawValue: "com.example.gallery")
        let unknown = PartNode(type: unknownType, children: [PartNode.make(.paragraph)])
        let html = HTMLPageRenderer().render(
            page: Page(title: "Unknown", slug: "unknown", parts: [unknown]),
            framework: .standard
        )

        #expect(html.contains("Missing part: com.example.gallery"))
        #expect(html.contains("class=\"paragraph"))
    }

    @Test
    func missingPartPlaceholderShowsTheTitleAndHelpAddress() {
        var unknown = PartNode(type: PartType(rawValue: "com.example.gallery"))
        unknown.missingPackageSnapshot = MissingPartSnapshot(
            name: "Gallery",
            category: "Media",
            helpURL: URL(string: "https://example.com/gallery/help")
        )
        let html = HTMLPageRenderer().render(
            page: Page(title: "Missing", slug: "missing", parts: [unknown]),
            framework: .standard
        )

        #expect(html.contains("Missing part: Gallery — help: https://example.com/gallery/help"))
    }

    @Test
    func styleEditParticipatesInUndoAndRedo() throws {
        let document = TestSiteFixtures.populatedDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let part = try #require(document.site.pages.first?.parts.first)
        let originalRadius = part.numberProperty(.cornerRadius)

        editor.setProperty(id: part.id, key: .cornerRadius, value: .number(42))
        #expect(document.site.part(withID: part.id)?.numberProperty(.cornerRadius) == 42)

        undoManager.undo()
        #expect(document.site.part(withID: part.id)?.numberProperty(.cornerRadius) == originalRadius)

        undoManager.redo()
        #expect(document.site.part(withID: part.id)?.numberProperty(.cornerRadius) == 42)
    }
}
