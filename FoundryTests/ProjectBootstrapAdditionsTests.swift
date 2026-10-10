import Foundation
import Testing
@testable import Foundry

@MainActor
struct ProjectBootstrapAdditionsTests {
    @Test(arguments: BootstrapEditorSection.allCases.filter(\.allowsCustom))
    func additionsFollowProjectAndDeletionsStayDeleted(section: BootstrapEditorSection) throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let firstID = document.site.frameworkSourceID
        let secondID = UUID()
        let token = try #require(section.customTokens(named: "project-extra").first)
        editor.addBootstrapToken("project-extra", section: section)
        editor.setBootstrapToken(token, value: "7")
        editor.setBootstrapToken(.init("link-color"), value: "#112233")
        editor.selectFramework(.standard, sourceID: secondID)
        #expect(document.site.framework.bootstrapTokens.custom[section.rawValue] == ["project-extra"])
        #expect(document.site.framework.bootstrapTokens.values[token.id] == "7")
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == nil)
        #expect(document.site.projectFrameworkValues.bootstrapAdditions.values[token.id] == "7")
        editor.setBootstrapToken(token, value: "9")
        document.site = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(document.site))
        editor.selectFramework(.standard, sourceID: firstID)
        #expect(document.site.framework.bootstrapTokens.values[token.id] == "9")
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == "#112233")
        editor.resetFramework(.standard, sourceID: firstID)
        #expect(document.site.framework.bootstrapTokens.values[token.id] == "9")
        #expect(document.site.framework.bootstrapTokens.values["link-color"] == nil)
        editor.removeBootstrapToken("project-extra", section: section)
        editor.selectFramework(.standard, sourceID: secondID)
        #expect(document.site.framework.bootstrapTokens.custom[section.rawValue]?.contains("project-extra") != true)
        #expect(document.site.framework.bootstrapTokens.values[token.id] == nil)
    }

    @Test func incomingAdditionsMergeWithoutReplacingProjectValues() {
        var original = Framework.standard
        original.bootstrapTokens.custom["borderWidth"] = ["brand"]
        original.bootstrapTokens.values["border-width-brand"] = "3px"
        var incoming = Framework.standard
        incoming.bootstrapTokens.custom["borderWidth"] = ["brand", "extra"]
        incoming.bootstrapTokens.values["border-width-brand"] = "8px"
        incoming.bootstrapTokens.values["border-width-extra"] = "6px"
        incoming.bootstrapTokens.values["border-width"] = "2px"
        var project = ProjectFrameworkValues()
        project.absorb(original)
        project.include(incoming)
        let result = project.applied(to: incoming)
        #expect(result.bootstrapTokens.custom["borderWidth"] == ["brand", "extra"])
        #expect(result.bootstrapTokens.values["border-width-brand"] == "3px")
        #expect(result.bootstrapTokens.values["border-width-extra"] == "6px")
        #expect(result.bootstrapTokens.values["border-width"] == "2px")
    }

    @Test func oldProjectValuesDecodeWithoutNewField() throws {
        let decoded = try JSONDecoder().decode(ProjectFrameworkValues.self, from: Data("{}".utf8))
        #expect(decoded.bootstrapAdditions == BootstrapEditorTokens())
    }
}
