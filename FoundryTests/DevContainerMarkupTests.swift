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
        for id in ["contentWidth", "contentHeight"] {
            let control = try #require(properties.first { $0.id == id })
            let expected = id == "contentWidth"
                ? ["Auto", "Full", "Screen", "Breakpoint", "Framework Spacing"]
                : ["Auto", "Full", "Screen", "Framework Spacing"]
            #expect(control.control.options?.map(\.title) == expected)
            #expect(control.defaultValue == .string(id == "contentWidth" ? "breakpoint" : "auto"))
            let spacing = try #require(properties.first { $0.id == id + "Spacing" })
            #expect(spacing.control.type == .frameworkSpacing)
            #expect(spacing.visibleWhen == .init(id: id, value: .string("spacing")))
        }
        for id in ["contentAlignment", "contentJustify"] {
            let control = try #require(properties.first { $0.id == id })
            #expect(control.control.options?.map(\.title) == ["Auto", "Start", "End", "Center", "Stretch"])
            #expect(control.defaultValue == .string("center"))
        }
        #expect(properties.contains { $0.id == "customContentWidth" } == false)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: packageURL.path)),
          arguments: ["auto", "full", "screen", "breakpoint", "spacing"])
    func eachContentSizeModeRendersAndResetsPreviousConstraints(_ mode: String) throws {
        let package = try PartPackageLoader.load(from: Self.packageURL)
        try package.preparePayload()
        let css = PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier,
            properties: ["contentWidth": .string(mode), "contentHeight": .string(mode == "breakpoint" ? "auto" : mode),
                         "contentWidthSpacing": .string("24rem"), "contentHeightSpacing": .string("18rem"),
                         "contentAlignment": .string("stretch"), "contentJustify": .string("center"),
                         "contentGap": .string("normal")], slots: [:]
        ))
        #expect(css.contains("width: auto;"))
        #expect(css.contains("height: auto;"))
        #expect(css.contains("max-width: none;"))
        #expect(css.contains("max-height: none;"))
        #expect(css.contains("display: grid;"))
        #expect(css.contains("display: flex;"))
        #expect(css.contains("align-self: stretch;"))
        #expect(css.contains("justify-self: center;"))
        #expect(css.contains("gap: normal;"))
        #expect(css.contains("{{") == false)
        switch mode {
        case "full":
            #expect(css.contains("width: 100%;"))
            #expect(css.contains("height: 100%;"))
        case "screen":
            #expect(css.contains("width: 100vw;"))
            #expect(css.contains("height: 100svh;"))
        case "breakpoint":
            #expect(css.contains("max-width: var(--foundry-container-width);"))
            #expect(css.contains("max-height: var(--foundry-container-width);") == false)
        case "spacing":
            #expect(css.contains("width: 24rem;"))
            #expect(css.contains("height: 18rem;"))
        default:
            #expect(css.contains("100vw") == false)
            #expect(css.contains("100svh") == false)
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
