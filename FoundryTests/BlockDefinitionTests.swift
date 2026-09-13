import Foundation
import Testing
@testable import Foundry

@MainActor
struct BlockDefinitionTests {
    init() {
        _ = BlockPackageCatalog.shared
    }

    @Test
    func pageSerializationUsesBlocksWithoutOldKeyFallback() throws {
        let page = Page(title: "Home", slug: "index", blocks: [.make(.paragraph)])
        let data = try JSONEncoder().encode(page)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["blocks"] != nil)
        #expect(object["components"] == nil)
        #expect(try JSONDecoder().decode(Page.self, from: data) == page)
        object["components"] = object.removeValue(forKey: "blocks")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Page.self, from: oldData)
        }
    }

    @Test
    func definitionsHaveUniquePropertyKeysAndDefaults() {
        for type in BlockType.allCases {
            let definition = type.definition
            let keys = definition.properties.map(\.key)

            #expect(definition.type == type)
            #expect(Set(keys).count == keys.count)
            #expect(BlockNode.make(type).properties.count == definition.properties.count)
        }
    }

    @Test
    func registryDeclaresChildCapabilities() {
        #expect(BlockType.container.definition.allowsChildren)
        #expect(BlockType.section.definition.allowsChildren)
        #expect(BlockType.columns.definition.allowsChildren)
        #expect(!BlockType.paragraph.definition.allowsChildren)
        #expect(!BlockType.button.definition.allowsChildren)
        #expect(!BlockType.image.definition.allowsChildren)
    }

    @Test
    func stockRegistryUsesUniqueNamespacedIdentifiers() {
        let identifiers = [
            BlockType.container,
            .section,
            .columns,
            .paragraph,
            .heading,
            .button,
            .image,
            .divider,
            .spacer
        ].map(\.rawValue)

        #expect(!identifiers.isEmpty)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.split(separator: ".").count >= 3 })
    }

    @Test
    func unknownBlockIdentifiersDecodeWithoutAliases() throws {
        let unqualified = try JSONDecoder().decode(BlockType.self, from: Data("\"container\"".utf8))
        let unknown = try JSONDecoder().decode(BlockType.self, from: Data("\"com.example.gallery\"".utf8))

        #expect(unqualified.rawValue == "container")
        #expect(unqualified.definition.renderKind == .unavailable)
        #expect(unknown.rawValue == "com.example.gallery")
        #expect(unknown.definition.renderKind == .unavailable)
    }

    @Test
    func typedPropertiesRoundTripThroughJSON() throws {
        var original = BlockNode.make(.paragraph)
        // Historical values remain readable even though these controls are gone.
        original.setProperty(.init(rawValue: "typeface"), value: .choice("body"))
        original.setProperty(.init(rawValue: "textSize"), value: .packageFontSize(.init(source: "base", customValue: "1rem")))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockNode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.propertyValue(.init(rawValue: "typeface")) == .choice("body"))
        #expect(decoded.propertyValue(.init(rawValue: "textSize")) == .packageFontSize(.init(
            source: "base",
            customValue: "1rem"
        )))
        #expect(decoded.propertyValue(.init(rawValue: "textColor")) == .packageColor(.init(
            source: BlockThemeValueSelection.manualCustom,
            customColor: "#000000",
            opacity: 1
        )))
    }

    @Test
    func missingStoredPropertiesUsePackageDefaults() {
        let text = BlockNode(
            type: .paragraph,
            properties: [.init(key: .init(rawValue: "content"), value: .string("Hello"))]
        )

        #expect(!text.type.definition.properties.contains { ["typeface", "textSize"].contains($0.key.rawValue) })
        #expect(text.propertyValue(.init(rawValue: "textColor")) == .packageColor(.init(
            source: BlockThemeValueSelection.manualCustom, customColor: "#000000", opacity: 1
        )))
    }

    @Test
    func packagePropertiesAreOrganizedIntoInspectorSections() {
        let buttonProperties = BlockType.button.definition.properties

        #expect(buttonProperties.first(where: { $0.key.rawValue == "label" })?.section == .content)
        #expect(buttonProperties.first(where: { $0.key.rawValue == "textColor" })?.section == .typography)
        #expect(!buttonProperties.contains { $0.key.rawValue == "textSize" })
        #expect(buttonProperties.first(where: { $0.key == .backgroundColor })?.section == .appearance)
        #expect(buttonProperties.first(where: { $0.key == .destination })?.section == .link)
        #expect(buttonProperties.first(where: { $0.key == .accessibilityLabel })?.section == .accessibility)
    }

    @Test
    func rendererAppliesPackagePropertiesAndEscapesAccessibilityLabel() {
        var container = BlockNode.make(.container)
        var text = BlockNode.make(.paragraph)
        var button = BlockNode.make(.button)
        container.setProperty(.borderWidth, value: .number(2))
        container.setProperty(.borderColor, value: .color("#ABCDEF"))
        container.setProperty(.cornerRadius, value: .number(28))
        container.setProperty(.maxWidth, value: .number(920))
        text.setProperty(.init(rawValue: "typeface"), value: .choice("heading"))
        text.setProperty(.init(rawValue: "textSize"), value: .packageFontSize(.init(
            source: "xl",
            customValue: "1rem"
        )))
        button.setProperty(.accessibilityLabel, value: .string("Open \"details\""))
        container.children = [text, button]

        let page = Page(title: "Test", slug: "test", blocks: [container])
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("border: 2px solid #ABCDEF"))
        #expect(html.contains("border-radius: 28px"))
        #expect(html.contains("max-width: 920px"))
        // Paragraph now uses the dedicated font control, not the removed select extension.
        #expect(BlockType.paragraph.definition.package!.css.contains("font-family: {{ control.font.family }}"))
        #expect(BlockType.paragraph.definition.package!.css.contains("font-weight: {{ control.font.weight }}"))
        #expect(BlockType.paragraph.definition.package!.css.contains("font-style: {{ control.font.style }}"))
        // The removed font-size control still emits no styling.
        #expect(!BlockType.paragraph.definition.package!.css.contains("font-size:"))
        #expect(html.contains("aria-label=\"Open &quot;details&quot;\""))
        #expect(html.contains("--foundry-editor-block: #0A84FF"))
        #expect(html.contains("--foundry-editor-global: #30D158"))
    }

    @Test
    func rendererSupportsExpandedStockBlockSet() {
        var columns = BlockNode.make(.columns)
        columns.children = [BlockNode.make(.heading), BlockNode.make(.image)]
        let blocks: [BlockNode] = [
            BlockNode(type: .section, children: [columns]),
            BlockNode.make(.divider),
            BlockNode.make(.spacer)
        ]
        let html = HTMLPageRenderer().render(
            page: Page(title: "Blocks", slug: "blocks", blocks: blocks),
            theme: .standard
        )

        #expect(html.contains("class=\"foundry-section"))
        #expect(html.contains("class=\"foundry-columns"))
        #expect(html.contains("<h2 class=\"foundry-heading"))
        #expect(html.contains("class=\"foundry-image"))
        #expect(html.contains("class=\"foundry-divider"))
        #expect(html.contains("class=\"foundry-spacer"))
    }

    @Test
    func unknownBlockRendersPlaceholderWithoutLosingChildren() {
        let unknownType = BlockType(rawValue: "com.example.gallery")
        let unknown = BlockNode(type: unknownType, children: [BlockNode.make(.paragraph)])
        let html = HTMLPageRenderer().render(
            page: Page(title: "Unknown", slug: "unknown", blocks: [unknown]),
            theme: .standard
        )

        #expect(html.contains("Missing block: com.example.gallery"))
        #expect(html.contains("class=\"paragraph"))
    }

    @Test
    func styleEditParticipatesInUndoAndRedo() throws {
        let document = TestSiteFixtures.populatedDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let block = try #require(document.site.pages.first?.blocks.first)
        let originalRadius = block.numberProperty(.cornerRadius)

        editor.setProperty(id: block.id, key: .cornerRadius, value: .number(42))
        #expect(document.site.block(withID: block.id)?.numberProperty(.cornerRadius) == 42)

        undoManager.undo()
        #expect(document.site.block(withID: block.id)?.numberProperty(.cornerRadius) == originalRadius)

        undoManager.redo()
        #expect(document.site.block(withID: block.id)?.numberProperty(.cornerRadius) == 42)
    }
}
