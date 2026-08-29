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
        #expect(!ComponentType.text.definition.allowsChildren)
        #expect(!ComponentType.button.definition.allowsChildren)
        #expect(!ComponentType.image.definition.allowsChildren)
    }

    @Test
    func stockRegistryUsesUniqueNamespacedIdentifiers() {
        let identifiers = ComponentType.allCases.map(\.rawValue)

        #expect(identifiers.count == 9)
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
        let original = ComponentNode.make(.text)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ComponentNode.self, from: data)

        #expect(decoded == original)
        #expect(decoded.propertyValue(.fontSize) == .number(38))
        #expect(decoded.propertyValue(.textColor) == .color("#171719"))
    }

    @Test
    func missingStoredPropertiesUseDefinitionDefaults() {
        let legacyText = ComponentNode(
            type: .text,
            properties: [.init(key: .text, value: .string("Legacy"))]
        )

        #expect(legacyText.numberProperty(.fontSize) == 38)
        #expect(legacyText.property(.alignment) == "leading")
        #expect(legacyText.numberProperty(.marginBottom) == 32)
        #expect(legacyText.property(.horizontalAlignment) == "leading")
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
        var text = ComponentNode.make(.text)
        var button = ComponentNode.make(.button)
        container.setProperty(.padding, value: .number(24))
        container.setProperty(.borderWidth, value: .number(2))
        container.setProperty(.borderColor, value: .color("#ABCDEF"))
        container.setProperty(.cornerRadius, value: .number(28))
        container.setProperty(.maxWidth, value: .number(920))
        text.setProperty(.alignment, value: .choice("center"))
        text.setProperty(.textColor, value: .color("#123456"))
        text.setProperty(.horizontalAlignment, value: .choice("trailing"))
        button.setProperty(.accessibilityLabel, value: .string("Open \"details\""))
        container.children = [text, button]

        let page = Page(title: "Test", slug: "test", components: [container])
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("padding: 24px"))
        #expect(html.contains("border: 2px solid #ABCDEF"))
        #expect(html.contains("border-radius: 28px"))
        #expect(html.contains("max-width: 920px"))
        #expect(html.contains("text-align: center"))
        #expect(html.contains("color: #123456"))
        #expect(html.contains("margin-left: auto; margin-right: 0"))
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

        #expect(html.contains("class=\"section\""))
        #expect(html.contains("class=\"columns\""))
        #expect(html.contains("<h2 class=\"heading\""))
        #expect(html.contains("class=\"image\""))
        #expect(html.contains("class=\"divider\""))
        #expect(html.contains("class=\"spacer\""))
    }

    @Test @MainActor
    func unknownComponentRendersPlaceholderWithoutLosingChildren() {
        let unknownType = ComponentType(rawValue: "com.example.gallery")
        let unknown = ComponentNode(type: unknownType, children: [ComponentNode.make(.text)])
        let html = HTMLPageRenderer().render(
            page: Page(title: "Unknown", slug: "unknown", components: [unknown]),
            theme: .standard
        )

        #expect(html.contains("Missing component: com.example.gallery"))
        #expect(html.contains("class=\"text\""))
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
