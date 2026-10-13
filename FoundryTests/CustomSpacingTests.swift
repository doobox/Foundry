import Foundation
import Testing
@testable import Foundry

@MainActor
struct CustomSpacingTests {
    @Test func fixedSpacingNeedsNoSeparateExtension() {
        #expect(BootstrapSpacingCSS.render(.standard).isEmpty)
        #expect(FoundryWebLibraryRegistry.exportFiles(for: []).contains { $0.path.hasSuffix("bootstrap-extensions.css") } == false)
    }

    @Test func savedExtendedSpacingBecomesAProjectValueOnlyWhenUsed() throws {
        var node = PartNode.make(.container)
        var padding = ThemePaddingValue()
        padding.setAll(.init(token: "13"))
        node.setProperty(.init(rawValue: "spacing.padding"), value: .themePadding(padding))
        var margin = ThemeMarginValue()
        margin.setAll(.init(token: "24"))
        node.setResponsiveProperty(.init(rawValue: "spacing.margin"), value: .themeMargin(margin), at: .medium)
        let original = Site(name: "Saved spacing", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(original))
        #expect(Set(restored.theme.spacing.custom.map(\.name)) == ["13", "24"])
        #expect(restored.theme.spacing.custom.first { $0.name == "13" }?.value == 3.5)
        #expect(restored.theme.spacing.custom.first { $0.name == "24" }?.value == 16)
        #expect(restored.projectThemeValues.spacing == restored.theme.spacing.custom)
        let twice = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(restored))
        #expect(twice.theme.spacing.custom == restored.theme.spacing.custom)
        let fresh = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(Site.starter()))
        #expect(fresh.theme.spacing.custom.isEmpty)
    }

    @Test func bootstrapStepsAreFixedAndSavedStepValuesAreIgnored() throws {
        // Bootstrap bakes its spacing steps into the utilities, so Foundry offers them as shipped.
        #expect(SpacingTokens.standard.choices.map(\.amount) == SpacingTokens.multipliers)
        #expect(SpacingTokens.multipliers.count == 13)
        #expect(SpacingTokens.multipliers.last == 3)
        #expect(SpacingTokens.validName("13") == false)
        #expect(SpacingTokens.validName("24") == false)
        let legacyNumeric = try JSONDecoder().decode(SpacingTokens.self, from: Data(#"{"custom":[{"id":"A25E7B2B-C7C2-4CB6-A2BE-985F246CE58A","name":"13","value":9}]}"#.utf8))
        #expect(legacyNumeric.choices.filter { $0.id == "13" }.map(\.amount) == [9])
        let legacy = try JSONDecoder().decode(SpacingTokens.self, from: Data(#"{"values":[9,9,9,9,9,9,9,9,9,9,9,9,9],"custom":[]}"#.utf8))
        #expect(legacy == .standard)
        #expect(BootstrapThemeCSS.render(theme: .standard).contains("--bs-spacer-5") == false)
    }

    @Test func renameDeleteAndThemeSwitchPreserveReferences() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.addCustomSpacing()
        let token = try #require(document.site.theme.spacing.custom.first)
        var padding = ThemePaddingValue()
        padding.setAll(.init(token: token.name))
        var child = PartNode.make(.container)
        let key = PartProperty.Key(rawValue: "spacing.padding")
        child.setProperty(key, value: .themePadding(padding))
        child.setResponsiveProperty(key, value: .themePadding(padding), at: .medium)
        child.setProperty(.init(rawValue: "label"), value: .string(token.name))
        var parent = PartNode.make(.container)
        parent.children = [child]
        document.site.pages = [Page(title: "Test", slug: "index", parts: [parent])]
        #expect(editor.renameCustomSpacing(token.id, name: "hero"))
        undo.endUndoGrouping()
        let renamed = document.site.pages[0].parts[0].children[0]
        #expect(BootstrapSpacingClasses.utilities(renamed.propertyValue(key), spacing: document.site.theme.spacing) == ["p-hero"])
        #expect(renamed.propertyValue(.init(rawValue: "label")) == .string(token.name))
        #expect(renamed.responsiveOverrides?.first?.value == .themePadding({ var p = ThemePaddingValue(); p.setAll(.init(token: "hero")); return p }()))
        undo.beginUndoGrouping()
        editor.removeCustomSpacing(token.id, replacingWith: "5")
        undo.endUndoGrouping()
        #expect(document.site.theme.spacing.custom.isEmpty)
        #expect(BootstrapSpacingClasses.utilities(document.site.pages[0].parts[0].children[0].propertyValue(key)) == ["p-5"])
        undo.undo()
        #expect(document.site.theme.spacing.custom.first?.name == "hero")
        undo.beginUndoGrouping()
        editor.selectTheme(.standard, sourceID: UUID())
        undo.endUndoGrouping()
        #expect(document.site.theme.spacing.custom.first?.name == "hero")
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(restored.theme.spacing == document.site.theme.spacing)
        #expect(restored.theme.spacing.choices.count == 14)
    }

    @Test func customNamesAndValuesAreValidatedWhenLoading() throws {
        for name in ["hero", "section-large", "13", "a_b"] {
            let tokens = SpacingTokens(custom: [.init(name: name, value: 24)])
            #expect(try JSONDecoder().decode(SpacingTokens.self, from: JSONEncoder().encode(tokens)) == tokens)
        }
        for name in ["5", "auto", "none", "has space", "bad;}"] {
            let data = try JSONEncoder().encode(SpacingTokens(custom: [.init(name: name, value: 4)]))
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(SpacingTokens.self, from: data) }
        }
        let duplicates = SpacingTokens(custom: [.init(name: "hero", value: 4), .init(name: "hero", value: 8)])
        let data = try JSONEncoder().encode(duplicates)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SpacingTokens.self, from: data) }
        let defaults = try JSONDecoder().decode(SpacingTokens.self, from: Data(#"{"spacerRem":2}"#.utf8))
        #expect(defaults == .standard)
    }
}
