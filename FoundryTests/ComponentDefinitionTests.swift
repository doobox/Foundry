import Foundation
import Testing
@testable import Foundry

@MainActor
struct ComponentDefinitionTests {
    init() {
        _ = ComponentPackageCatalog.shared
    }

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
        let identifiers = [
            ComponentType.container,
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
    func unknownComponentIdentifiersDecodeWithoutAliases() throws {
        let unqualified = try JSONDecoder().decode(ComponentType.self, from: Data("\"container\"".utf8))
        let unknown = try JSONDecoder().decode(ComponentType.self, from: Data("\"com.example.gallery\"".utf8))

        #expect(unqualified.rawValue == "container")
        #expect(unqualified.definition.renderKind == .unavailable)
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
        #expect(decoded.propertyValue(.init(rawValue: "textSize")) == .packageFontSize(.init(
            source: "base",
            customValue: "1rem"
        )))
        #expect(decoded.propertyValue(.init(rawValue: "textColor")) == .packageColor(.init(
            source: ComponentThemeValueSelection.manualCustom,
            customColor: "#000000",
            opacity: 1
        )))
    }

    @Test
    func missingStoredPropertiesUsePackageDefaults() {
        let text = ComponentNode(
            type: .paragraph,
            properties: [.init(key: .init(rawValue: "content"), value: .string("Hello"))]
        )

        #expect(text.property(.init(rawValue: "typeface")) == "body")
        #expect(text.propertyValue(.init(rawValue: "textSize")) == .packageFontSize(.init(
            source: "base",
            customValue: "1rem"
        )))
    }

    @Test
    func packagePropertiesAreOrganizedIntoInspectorSections() {
        let buttonProperties = ComponentType.button.definition.properties

        #expect(buttonProperties.first(where: { $0.key.rawValue == "label" })?.section == .content)
        #expect(buttonProperties.first(where: { $0.key.rawValue == "textSize" })?.section == .typography)
        #expect(buttonProperties.first(where: { $0.key == .backgroundColor })?.section == .appearance)
        #expect(buttonProperties.first(where: { $0.key == .destination })?.section == .link)
        #expect(buttonProperties.first(where: { $0.key == .accessibilityLabel })?.section == .accessibility)
    }

    @Test
    func rendererAppliesPackagePropertiesAndEscapesAccessibilityLabel() {
        var container = ComponentNode.make(.container)
        var text = ComponentNode.make(.paragraph)
        var button = ComponentNode.make(.button)
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

        let page = Page(title: "Test", slug: "test", components: [container])
        let html = HTMLPageRenderer().render(page: page, theme: .standard)

        #expect(html.contains("border: 2px solid #ABCDEF"))
        #expect(html.contains("border-radius: 28px"))
        #expect(html.contains("max-width: 920px"))
        #expect(html.contains("font-family: var(--foundry-font-heading)"))
        #expect(html.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(html.contains("aria-label=\"Open &quot;details&quot;\""))
        #expect(html.contains("--foundry-editor-component: #0A84FF"))
        #expect(html.contains("--foundry-editor-global: #30D158"))
    }

    @Test
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

        #expect(html.contains("class=\"foundry-section"))
        #expect(html.contains("class=\"foundry-columns"))
        #expect(html.contains("<h2 class=\"foundry-heading"))
        #expect(html.contains("class=\"foundry-image"))
        #expect(html.contains("class=\"foundry-divider"))
        #expect(html.contains("class=\"foundry-spacer"))
    }

    @Test
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

    @Test
    func styleEditParticipatesInUndoAndRedo() throws {
        let document = TestSiteFixtures.populatedDocument()
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
