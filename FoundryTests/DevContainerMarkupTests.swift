import Foundation
import Testing
@testable import Foundry

struct DevContainerMarkupTests {
    private static var packageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path:
            "Library/Application Support/Foundry/Packs/Layout.foundrydevpack/Parts/Container")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: packageURL.path)))
    func contentLayoutMatchesReferenceOptionsAndDefaults() throws {
        let package = try PartPackageLoader.load(from: Self.packageURL)
        let properties = package.manifest.resolvedProperties
        let width = try #require(properties.first { $0.id == "contentWidth" })
        #expect(width.control.options?.map(\.title) == ["Breakpoint", "Full", "Fit Content", "Custom"])
        #expect(width.defaultValue == .string("breakpoint"))
        let custom = try #require(properties.first { $0.id == "contentWidthSpacing" })
        #expect(custom.control.type == .themeSpacing)
        #expect(custom.visibleWhen == .init(id: "contentWidth", value: .string("custom")))
        // Content height was removed: the section's Sizing height covers it.
        #expect(properties.contains { $0.id == "contentHeight" } == false)
        for id in ["contentAlignment", "contentJustify"] {
            let control = try #require(properties.first { $0.id == id })
            #expect(control.control.options?.map(\.title) == ["Auto", "Start", "End", "Centre", "Stretch"])
            #expect(control.defaultValue == .string("center"))
        }
        #expect(properties.contains { $0.id == "customContentWidth" } == false)
        // A new section starts with breathing room from the Spacing group.
        #expect(properties.first { $0.id == "spacing.spacingEnabled" }?.defaultValue == .boolean(true))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: packageURL.path)),
          arguments: ["auto", "full", "breakpoint", "custom"])
    func eachContentWidthModeRendersAndResetsPreviousConstraints(_ mode: String) throws {
        let package = try PartPackageLoader.load(from: Self.packageURL)
        try package.preparePayload()
        let css = PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier,
            properties: ["contentWidth": .string(mode), "contentWidthSpacing": .string("24rem"),
                         "contentAlignment": .string("stretch"), "contentJustify": .string("center"),
                         "contentGap": .string("normal")], slots: [:]
        ))
        #expect(css.contains("width: auto;"))
        #expect(css.contains("height: auto;"))
        #expect(css.contains("max-width: none;"))
        #expect(css.contains("display: grid;"))
        #expect(css.contains("display: flex;"))
        #expect(css.contains("align-self: stretch;"))
        #expect(css.contains("justify-self: center;"))
        #expect(css.contains("gap: normal;"))
        #expect(css.contains("{{") == false)
        #expect(css.contains("100vw") == false)
        #expect(css.contains("100svh") == false)
        switch mode {
        case "full":
            #expect(css.contains("width: 100%;"))
        case "breakpoint":
            #expect(css.contains("max-width: var(--foundry-container-width);"))
        case "custom":
            #expect(css.contains("width: 24rem;"))
            #expect(css.contains("max-width: 100%;"))
        default:
            #expect(css.contains("width: 100%;") == false)
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: packageURL.path)))
    func devContainerUsesOneRootAndItsDeclaredControls() throws {
        let package = try PartPackageLoader.load(from: Self.packageURL)
        try package.preparePayload()
        let diagnostics = PartPackageValidator.validate(package.manifest, rootURL: package.rootURL.appending(path: "Resources"))
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty)
        let html = package.htmlTemplate
        #expect(html.components(separatedBy: "{{ part.attributes }}").count == 2)
        #expect(html.components(separatedBy: "{{ part.class }}").count == 2)
        #expect(html.contains("Your content goes here") == false)
        #expect(html.contains("class=\"fd-container ") == false)
        #expect(html.contains("{{ control.background.video }}"))
        #expect(package.dropZoneNames == ["content"])
        #expect(package.css.contains("control.flexbox") == false)

        var values = Dictionary(uniqueKeysWithValues: package.manifest.resolvedProperties.map { ($0.id, $0.defaultValue) })
        #expect(values["layout.position"] == .string("relative"))
        values["contentWidth"] = .string("full")
        values["contentGap"] = .string("2rem")
        PartPackageControlGroupCSSResolver.resolve(&values, properties: package.manifest.resolvedProperties)
        let css = PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier, properties: values, slots: [:]
        ))
        #expect(css.contains("position: relative;"))
        #expect(css.contains("isolation: isolate;"))
        #expect(css.contains("max-width: none;"))
        #expect(css.contains("margin-inline: 0;"))
        #expect(css.contains("padding-inline: 0;"))
        #expect(css.contains("max-width: var(--foundry-container-width)") == false)
        #expect(css.contains("gap: 2rem;"))
        #expect(css.contains("{{") == false)
    }
}
