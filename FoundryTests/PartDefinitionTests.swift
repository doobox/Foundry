import Foundation
import Testing
@testable import Foundry

@MainActor
struct PartDefinitionTests {
    /// Every test here reads definitions that only exist once the pack
    /// catalog has loaded. Kicking the load without awaiting it left the
    /// suite racing it, so `definition.package` was intermittently nil.
    init() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
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
        #expect(PartType.section.definition.allowsChildren)
        #expect(PartType.stack.definition.allowsChildren)
        #expect(PartType.grid.definition.allowsChildren)
        #expect(!PartType.paragraph.definition.allowsChildren)
        #expect(!PartType.button.definition.allowsChildren)
        #expect(!PartType.image.definition.allowsChildren)
    }

    @Test
    func stockRegistryUsesUniqueNamespacedIdentifiers() {
        let identifiers = [
            PartType.section,
            .stack,
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
        let retiredContainer = try JSONDecoder().decode(
            PartType.self,
            from: Data("\"foundry.layout.container\"".utf8)
        )
        let unknown = try JSONDecoder().decode(PartType.self, from: Data("\"com.example.gallery\"".utf8))

        #expect(unqualified.rawValue == "container")
        #expect(unqualified.definition.renderKind == .unavailable)
        #expect(retiredContainer.rawValue == "foundry.layout.container")
        #expect(retiredContainer.definition.renderKind == .unavailable)
        #expect(unknown.rawValue == "com.example.gallery")
        #expect(unknown.definition.renderKind == .unavailable)
    }

    @Test
    func legacyFlexboxIdentifiersAndDefaultNamesMigrateToStack() throws {
        var item = PartNode.make(.stackItem)
        item.name = "Flex Item"
        var stack = PartNode.make(.stack)
        stack.name = "Flexbox"
        stack.children = [item]
        let site = Site(
            name: "Legacy layout",
            pages: [Page(title: "Home", slug: "index", parts: [stack])],
            assetLibrary: [],
            partPackages: [
                .init(identifier: "foundry.layout.stack"),
                .init(identifier: "foundry.layout.stackitem")
            ]
        )
        let currentJSON = try #require(String(data: JSONEncoder().encode(site), encoding: .utf8))
        let legacyJSON = currentJSON
            .replacingOccurrences(of: "foundry.layout.stackitem", with: "foundry.layout.flexitem")
            .replacingOccurrences(of: "foundry.layout.stack", with: "foundry.layout.flexbox")

        let migrated = try JSONDecoder().decode(Site.self, from: Data(legacyJSON.utf8))
        let migratedStack = try #require(migrated.pages.first?.parts.first)
        #expect(migratedStack.type == .stack)
        #expect(migratedStack.name == "Stack")
        #expect(migratedStack.children.first?.type == .stackItem)
        #expect(migratedStack.children.first?.name == "Stack Item")
        #expect(migrated.partPackages.map(\.identifier) == [
            "foundry.layout.stack",
            "foundry.layout.stackitem"
        ])
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
        var container = PartNode.make(.section)
        var stack = PartNode.make(.stack)
        var text = PartNode.make(.paragraph)
        var button = PartNode.make(.button)
        container.setProperty(.init(rawValue: "borders.borderEnabled"), value: .boolean(true))
        container.setProperty(.init(rawValue: "borders.frameworkBorder.width"), value: .frameworkBorderWidth(PartPackageFrameworkBorderWidthControl.defaultValue(.object(["value": .number(2), "unit": .string("px")]))!))
        container.setProperty(.init(rawValue: "borders.frameworkBorderColour"), value: .packageColor(.init(source: "custom", customColor: "#ABCDEF", opacity: 1)))
        container.setProperty(.init(rawValue: "borders.frameworkRadius"), value: .frameworkRadius(PartPackageFrameworkRadiusControl.defaultValue(.object(["value": .number(28), "unit": .string("px")]))!))
        // Section roots are always full width; a Flex carries the shared
        // sizing group's max-width control.
        stack.setProperty(.init(rawValue: "sizing.maxWidth"), value: .frameworkSpacing(.init(
            selection: .init(token: "none", isCustom: true, amount: 920, unit: "px")
        )))
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
        #expect(html.contains("max-width: min(100%, 920.0px)"))
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
            PartNode(type: .stack, children: [grid]),
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
