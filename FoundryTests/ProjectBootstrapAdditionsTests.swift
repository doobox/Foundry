import Foundation
import Testing
@testable import Foundry

@MainActor
struct ProjectBootstrapAdditionsTests {
    @Test(arguments: BootstrapEditorSection.allCases.filter(\.allowsCustom))
    func additionsFollowProjectAndDeletionsStayDeleted(section: BootstrapEditorSection) throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let firstID = document.site.themeSourceID
        let secondID = UUID()
        let token = try #require(section.customTokens(named: "project-extra").first)
        editor.addBootstrapToken("project-extra", section: section)
        editor.setBootstrapToken(token, value: "7")
        editor.setBootstrapToken(.init("link-color"), value: "#112233")
        editor.selectTheme(.standard, sourceID: secondID)
        #expect(document.site.theme.bootstrapTokens.custom[section.rawValue] == ["project-extra"])
        #expect(document.site.theme.bootstrapTokens.values[token.id] == "7")
        #expect(document.site.theme.bootstrapTokens.values["link-color"] == nil)
        #expect(document.site.projectThemeValues.bootstrapAdditions.values[token.id] == "7")
        editor.setBootstrapToken(token, value: "9")
        document.site = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        editor.selectTheme(.standard, sourceID: firstID)
        #expect(document.site.theme.bootstrapTokens.values[token.id] == "9")
        #expect(document.site.theme.bootstrapTokens.values["link-color"] == "#112233")
        editor.resetTheme(.standard, sourceID: firstID)
        #expect(document.site.theme.bootstrapTokens.values[token.id] == "9")
        #expect(document.site.theme.bootstrapTokens.values["link-color"] == nil)
        editor.removeBootstrapToken("project-extra", section: section)
        editor.selectTheme(.standard, sourceID: secondID)
        #expect(document.site.theme.bootstrapTokens.custom[section.rawValue]?.contains("project-extra") != true)
        #expect(document.site.theme.bootstrapTokens.values[token.id] == nil)
    }

    @Test func incomingAdditionsMergeWithoutReplacingProjectValues() {
        var original = Theme.standard
        original.bootstrapTokens.custom["borderWidth"] = ["brand"]
        original.bootstrapTokens.values["border-width-brand"] = "3px"
        var incoming = Theme.standard
        incoming.bootstrapTokens.custom["borderWidth"] = ["brand", "extra"]
        incoming.bootstrapTokens.values["border-width-brand"] = "8px"
        incoming.bootstrapTokens.values["border-width-extra"] = "6px"
        incoming.bootstrapTokens.values["border-width"] = "2px"
        var project = ProjectThemeValues()
        project.absorb(original)
        project.include(incoming)
        let result = project.applied(to: incoming)
        #expect(result.bootstrapTokens.custom["borderWidth"] == ["brand", "extra"])
        #expect(result.bootstrapTokens.values["border-width-brand"] == "3px")
        #expect(result.bootstrapTokens.values["border-width-extra"] == "6px")
        #expect(result.bootstrapTokens.values["border-width"] == "2px")
    }

    @Test func oldProjectValuesDecodeWithoutNewField() throws {
        let decoded = try JSONDecoder().decode(ProjectThemeValues.self, from: Data("{}".utf8))
        #expect(decoded.bootstrapAdditions == BootstrapEditorTokens())
    }
}
