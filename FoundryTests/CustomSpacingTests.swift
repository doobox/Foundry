import Foundation
import Testing
@testable import Foundry

@MainActor
struct CustomSpacingTests {
    @Test func resettingNativeStepsPreservesCustomSizesAndSupportsUndo() {
        let document = FoundryDocument()
        document.site.framework.spacing.values[0] = 2.5
        document.site.framework.spacing.custom = [.init(name: "hero", value: 6)]
        let original = document.site.framework.spacing
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.resetBootstrapSpacing()
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.values == SpacingTokens.multipliers)
        #expect(document.site.framework.spacing.custom == original.custom)
        undo.undo()
        #expect(document.site.framework.spacing == original)
        undo.redo()
        #expect(document.site.framework.spacing.values == SpacingTokens.multipliers)
        #expect(document.site.framework.spacing.custom == original.custom)
        editor.resetBootstrapSpacing()
    }

    @Test func nativeStepsAreEditableSavedAndUndoable() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let original = document.site.framework.spacing
        undo.beginUndoGrouping()
        editor.setBootstrapSpacing(5, value: 4)
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.choices[5].amount == 4)
        #expect(BootstrapThemeCSS.render(framework: document.site.framework).contains("--bs-spacer-5: 4.0rem"))
        undo.undo()
        #expect(document.site.framework.spacing == original)
        undo.redo()
        #expect(document.site.framework.spacing.values[5] == 4)
        let saved = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(saved.framework.spacing.values[5] == 4)
        undo.beginUndoGrouping()
        editor.selectFramework(.standard, sourceID: UUID())
        editor.selectFramework(.standard, sourceID: FrameworkBundleStore.systemFrameworkID)
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.values[5] == 4)
        #expect(FrameworkBundleStore.systemFramework.spacing == original)
        for value in [-1, Double.infinity, Double.nan] {
            editor.setBootstrapSpacing(5, value: value)
            #expect(document.site.framework.spacing.values[5] == 4)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SpacingTokens.self, from: Data(#"{"values":[1,2]}"#.utf8))
        }
    }

    @Test func renameDeleteAndFrameworkSwitchPreserveReferences() throws {
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.addCustomSpacing()
        let token = try #require(document.site.framework.spacing.custom.first)
        var padding = FrameworkPaddingValue()
        padding.setAll(.init(token: token.name))
        var child = PartNode.make(.container)
        let key = PartProperty.Key(rawValue: "spacing.padding")
        child.setProperty(key, value: .frameworkPadding(padding))
        child.setResponsiveProperty(key, value: .frameworkPadding(padding), at: .medium)
        child.setProperty(.init(rawValue: "label"), value: .string(token.name))
        var parent = PartNode.make(.container)
        parent.children = [child]
        document.site.pages = [Page(title: "Test", slug: "index", parts: [parent])]
        #expect(editor.renameCustomSpacing(token.id, name: "hero"))
        undo.endUndoGrouping()
        let renamed = document.site.pages[0].parts[0].children[0]
        #expect(BootstrapSpacingClasses.utilities(renamed.propertyValue(key), spacing: document.site.framework.spacing) == ["p-hero"])
        #expect(renamed.propertyValue(.init(rawValue: "label")) == .string(token.name))
        #expect(renamed.responsiveOverrides?.first?.value == .frameworkPadding({ var p = FrameworkPaddingValue(); p.setAll(.init(token: "hero")); return p }()))
        undo.beginUndoGrouping()
        editor.removeCustomSpacing(token.id, replacingWith: "5")
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.custom.isEmpty)
        #expect(BootstrapSpacingClasses.utilities(document.site.pages[0].parts[0].children[0].propertyValue(key)) == ["p-5"])
        undo.undo()
        #expect(document.site.framework.spacing.custom.first?.name == "hero")
        undo.beginUndoGrouping()
        editor.selectFramework(.standard, sourceID: UUID())
        undo.endUndoGrouping()
        #expect(document.site.framework.spacing.custom.first?.name == "hero")
        let restored = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        #expect(restored.framework.spacing == document.site.framework.spacing)
        #expect(restored.framework.spacing.choices.count == 14)
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
