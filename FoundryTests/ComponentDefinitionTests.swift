import Foundation
import Testing
@testable import Foundry

struct ComponentDefinitionTests {
    @Test
    func definitionsHaveUniquePropertyKeysAndDefaults() {
        for type in ComponentType.allCases {
            let definition = type.definition
            let keys = definition.properties.map(\.key)

            #expect(definition.type == type)
            #expect(Set(keys).count == keys.count)
            #expect(ComponentNode.make(type).properties.count == definition.properties.count)
        }
    }

    @Test
    func registryDeclaresChildCapabilities() {
        #expect(ComponentType.container.definition.allowsChildren)
        #expect(ComponentType.section.definition.allowsChildren)
        #expect(ComponentType.columns.definition.allowsChildren)
        #expect(!ComponentType.paragraph.definition.allowsChildren)
        #expect(!ComponentType.button.definition.allowsChildren)
        #expect(!ComponentType.image.definition.allowsChildren)
    }

    @Test
    func stockRegistryUsesUniqueNamespacedIdentifiers() {
        let identifiers = ComponentType.allCases.map(\.rawValue)

        #expect(!identifiers.isEmpty)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.split(separator: ".").count >= 3 })
    }

    @Test
    func legacyAndUnknownComponentIdentifiersDecodeSafely() throws {
        let legacy = try JSONDecoder().decode(ComponentType.self, from: Data("\"container\"".utf8))
        let unknown = try JSONDecoder().decode(ComponentType.self, from: Data("\"com.example.gallery\"".utf8))

        #expect(legacy == .container)
        #expect(unknown.rawValue == "com.example.gallery")
        #expect(unknown.definition.renderKind == .unavailable)
    }

    @Test
    func typedPropertiesRoundTripThroughJSON() throws {
        let original = ComponentNode.make(.paragraph)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ComponentNode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.propertyValue(.init(rawValue: "typeface")) == .choice("body"))
        #expect(decoded.propertyValue(.init(rawValue: "textSize")) == .choice("base"))
    }

    @Test
    func missingStoredPropertiesUseDefinitionDefaults() {
        let legacyText = ComponentNode(
            type: .paragraph,
            properties: [.init(key: .text, value: .string("Legacy"))]
        )

        #expect(legacyText.property(.init(rawValue: "typeface")) == "body")
        #expect(legacyText.property(.init(rawValue: "textSize")) == "base")
    }

    @Test
    func stylePropertiesAreOrganizedIntoInspectorSections() {
        let buttonProperties = ComponentType.button.definition.properties

        #expect(buttonProperties.first(where: { $0.key == .text })?.section == .content)
        #expect(buttonProperties.first(where: { $0.key == .fontSize })?.section == .typography)
        #expect(buttonProperties.first(where: { $0.key == .backgroundColor })?.section == .appearance)
        #expect(buttonProperties.first(where: { $0.key == .padding })?.section == .layout)
        #expect(buttonProperties.first(where: { $0.key == .destination })?.section == .link)
        #expect(buttonProperties.first(where: { $0.key == .accessibilityLabel })?.section == .accessibility)
    }

    @Test @MainActor
    func rendererAppliesSchemaPropertiesAndEscapesAccessibilityLabel() {
        var container = ComponentNode.make(.container)
        var text = ComponentNode.make(.paragraph)
        var button = ComponentNode.make(.button)
        container.setProperty(.padding, value: .number(24))
        container.setProperty(.borderWidth, value: .number(2))
        container.setProperty(.init(rawValue: "borderColorCustom"), value: .color("#ABCDEF"))
        container.setProperty(.cornerRadius, value: .number(28))
        container.setProperty(.maxWidth, value: .number(920))
        text.setProperty(.init(rawValue: "typeface"), value: .choice("heading"))
        text.setProperty(.init(rawValue: "textSize"), value: .choice("xl"))
        button.setProperty(.accessibilityLabel, value: .string("Open \"details\""))
        container.children = [text, button]

        let page = Page(title: "Test", slug: "test", components: [container])
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("padding: 24px"))
        #expect(html.contains("border: 2px solid #ABCDEF"))
        #expect(html.contains("border-radius: 28px"))
        #expect(html.contains("max-width: 920px"))
        #expect(html.contains("font-family: var(--foundry-font-heading)"))
        #expect(html.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(html.contains("aria-label=\"Open &quot;details&quot;\""))
        #expect(html.contains("[data-foundry-id]:hover:not(:has([data-foundry-id]:hover))"))
    }

    @Test @MainActor
    func rendererSupportsExpandedStockComponentSet() {
        var columns = ComponentNode.make(.columns)
        columns.children = [ComponentNode.make(.heading), ComponentNode.make(.image)]
        let components: [ComponentNode] = [
            ComponentNode(type: .section, children: [columns]),
            ComponentNode.make(.divider),
            ComponentNode.make(.spacer)
        ]
        let html = HTMLPageRenderer().render(
            page: Page(title: "Components", slug: "components", components: components),
            theme: .standard
        )

        #expect(html.contains("class=\"foundry-section\""))
        #expect(html.contains("class=\"foundry-columns\""))
        #expect(html.contains("<h2 class=\"foundry-heading\""))
        #expect(html.contains("class=\"foundry-image\""))
        #expect(html.contains("class=\"foundry-divider\""))
        #expect(html.contains("class=\"foundry-spacer\""))
    }

    @Test @MainActor
    func unknownComponentRendersPlaceholderWithoutLosingChildren() {
        let unknownType = ComponentType(rawValue: "com.example.gallery")
        let unknown = ComponentNode(type: unknownType, children: [ComponentNode.make(.paragraph)])
        let html = HTMLPageRenderer().render(
            page: Page(title: "Unknown", slug: "unknown", components: [unknown]),
            theme: .standard
        )

        #expect(html.contains("Missing component: com.example.gallery"))
        #expect(html.contains("class=\"paragraph"))
    }

    @Test @MainActor
    func styleEditParticipatesInUndoAndRedo() throws {
        let document = FoundryDocument()
        let undoManager = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undoManager)
        let component = try #require(document.site.pages.first?.components.first)
        let originalRadius = component.numberProperty(.cornerRadius)

        editor.setProperty(id: component.id, key: .cornerRadius, value: .number(42))
        #expect(document.site.component(withID: component.id)?.numberProperty(.cornerRadius) == 42)

        undoManager.undo()
        #expect(document.site.component(withID: component.id)?.numberProperty(.cornerRadius) == originalRadius)

        undoManager.redo()
        #expect(document.site.component(withID: component.id)?.numberProperty(.cornerRadius) == 42)
    }
}
