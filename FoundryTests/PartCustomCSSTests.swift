import Foundation
import Testing
@testable import Foundry

struct PartCustomCSSTests {
    @Test
    func customCSSIsNestedInsideTheInstanceSelector() {
        let id = UUID()
        let selector = "[data-foundry-id=\"\(id.uuidString)\"]"
        let css = PartTemplateRenderer.scopedCustomCSS("color: red;\n:instance:hover { color: blue; }\nh2 { margin: 0; }", instanceID: id)
        // The doubled selector outranks the part's own rules.
        #expect(css.hasPrefix("\(selector)\(selector) {"))
        #expect(css.contains("&:hover { color: blue; }"))
        // A rule without :instance stays inside the part rather than leaking.
        #expect(css.contains("h2 { margin: 0; }"))
        #expect(css.hasSuffix("}"))
        #expect(css.contains(":instance") == false)
    }

    @Test
    func leadingPseudoSelectorsAttachToTheirParent() {
        let css = PartTemplateRenderer.scopedCustomCSS(
            ":hover { color: red; }\n::before, a:focus, :focus-visible { content: 'a:b { }'; }\nh2 { :hover { color: blue; } }\n@media (min-width: 40em) { :hover { color: green; } }\n/* :hover { } */",
            instanceID: UUID())
        #expect(css.contains("&:hover { color: red; }"))
        #expect(css.contains("&::before, a:focus, &:focus-visible {"))
        // Strings, nested rules and at-rules behave correctly.
        #expect(css.contains("content: 'a:b { }';"))
        #expect(css.contains("h2 { &:hover { color: blue; } }"))
        #expect(css.contains("@media (min-width: 40em) { &:hover { color: green; } }"))
        #expect(css.contains("/* :hover { } */"))
        #expect(css.contains("color: red;"))
    }

    @Test
    func unbalancedBracesCannotEscapeThePartOrSwallowOthers() {
        let id = UUID()
        let selector = "[data-foundry-id=\"\(id.uuidString)\"]"
        // A stray closing brace would otherwise end the wrapper and restyle the page.
        let escaping = PartTemplateRenderer.scopedCustomCSS("color: red; } body { display: none; }", instanceID: id)
        #expect(escaping.filter { $0 == "{" }.count == escaping.filter { $0 == "}" }.count)
        #expect(escaping.hasPrefix("\(selector)\(selector) {"))
        #expect(escaping.contains("} body") == false)
        // An unclosed rule is closed before the wrapper ends.
        let unclosed = PartTemplateRenderer.scopedCustomCSS("h2 { color: red;", instanceID: id)
        #expect(unclosed.filter { $0 == "{" }.count == unclosed.filter { $0 == "}" }.count)
        // Braces inside strings and comments are not counted.
        let quoted = PartTemplateRenderer.scopedCustomCSS("content: '}'; /* { */", instanceID: id)
        #expect(quoted.contains("content: '}';"))
        #expect(quoted.hasSuffix("/* { */\n}"))
    }

    @Test
    func emptyCustomCSSProducesNothingAndStyleTagsCannotEscape() {
        #expect(PartTemplateRenderer.scopedCustomCSS(nil, instanceID: UUID()).isEmpty)
        #expect(PartTemplateRenderer.scopedCustomCSS("  \n ", instanceID: UUID()).isEmpty)
        let css = PartTemplateRenderer.scopedCustomCSS("content: '</STYLE><script>'", instanceID: UUID())
        #expect(css.lowercased().contains("</style") == false)
    }

    @Test @MainActor
    func customCSSReachesCanvasAndExportAndSurvivesSavingAndDuplicating() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.paragraph)
        part.customCSS = ":instance { letter-spacing: 0.3em; }"
        let site = Site(name: "Custom CSS", pages: [Page(title: "Home", slug: "index", parts: [part])])

        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        #expect(canvas.contains("& { letter-spacing: 0.3em; }"))
        let exported = StaticSiteRenderer().render(site: site).files.map(\.contents).joined(separator: "\n")
        #expect(exported.contains("& { letter-spacing: 0.3em; }"))

        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(part))
        #expect(restored.customCSS == part.customCSS)
        #expect(part.duplicated().customCSS == part.customCSS)
    }
}
