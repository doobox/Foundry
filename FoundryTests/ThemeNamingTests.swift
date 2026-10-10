import Foundation
import Testing
@testable import Foundry

@MainActor
struct ThemeNamingTests {
    @Test
    func renamedModelPreservesSavedProjectKeysAndValues() throws {
        let document = FoundryDocument()
        let data = try FoundryDocument.encoder.encode(document.site)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["framework"] != nil)
        #expect(json["frameworkSourceID"] != nil)
        #expect(json["projectFrameworkValues"] != nil)
        #expect(json["frameworkStates"] != nil)
        let restored = try FoundryDocument.decoder.decode(Site.self, from: data)
        #expect(restored.theme == document.site.theme)
        #expect(restored.themeSourceID == document.site.themeSourceID)
        #expect(restored.projectThemeValues == document.site.projectThemeValues)
    }

    @Test
    func savedSpacingPayloadStillDecodes() throws {
        let value = PartProperty.Value.themePadding(ThemePaddingValue())
        let data = try JSONEncoder().encode(value)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["frameworkPadding"] != nil)
        #expect(try JSONDecoder().decode(PartProperty.Value.self, from: data) == value)
    }

    @Test(arguments: ["Font", "FontSize", "StackingOrder", "Border", "Radius", "Margin", "Spacing", "Padding", "Shadow"])
    func savedControlNamesDecodeButEncodeWithThemeNames(suffix: String) throws {
        let oldName = "framework" + suffix
        let expected = "theme" + suffix
        let data = try JSONEncoder().encode(oldName)
        let kind = try JSONDecoder().decode(PartPackageControl.Kind.self, from: data)
        #expect(kind.rawValue == expected)
        let encodedName = try JSONDecoder().decode(String.self, from: JSONEncoder().encode(kind))
        #expect(encodedName == expected)
    }

    @Test
    func themeEditorTerminologyAndBuiltInLoading() throws {
        #expect(ThemeWindowSection.themes.title == "Themes")
        let builtIn = try #require(ThemeBundleStore.builtInThemes().first)
        #expect(try ThemeBundleStore.load(from: builtIn.bundleURL).theme == builtIn.theme)
    }
}
