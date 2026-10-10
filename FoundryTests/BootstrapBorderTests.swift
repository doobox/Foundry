import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapBorderTests {
    @Test func edgesCompactWithoutChangingPresence() {
        var edges = ThemeBorderWidthValue()
        #expect(BootstrapBorderClasses.sides(edges) == "")
        edges.setAll(.init(token: "1"))
        #expect(BootstrapBorderClasses.sides(edges) == "border")
        edges.set(.init(token: "0"), for: .top)
        #expect(BootstrapBorderClasses.sides(edges) == "border-y-0 border-x")
        edges.unlinkAll()
        edges.set(.init(token: "none"), for: .bottom)
        #expect(BootstrapBorderClasses.sides(edges) == "border-top-0 border-x")
    }

    @Test func defaultsAndUnusedStyles() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let raw: PartPackageValue = .object(["top": .string("1"), "bottom": .string("1"), "left": .string("0"), "right": .string("none")])
        let value = try #require(BootstrapBorderClasses.defaultValue(raw))
        #expect(BootstrapBorderClasses.sides(value) == "border-y border-start-0")
        #expect(BootstrapBorderClasses.defaultValue(.string("sm")) == nil)
        var node = PartNode.make(.container)
        #expect(BootstrapPartUtilityCSS.render(node: node, theme: .standard).isEmpty)
        node.setProperty(.init(rawValue: "borders.style"), value: .choice("dotted"))
        #expect(BootstrapPartUtilityCSS.render(node: node, theme: .standard).contains("--bs-border-style:dotted"))
        node.setProperty(.init(rawValue: "borders.style"), value: .choice("inherit"))
        #expect(BootstrapPartUtilityCSS.render(node: node, theme: .standard).isEmpty)
        let restored = try JSONDecoder().decode(ThemeBorderWidthValue.self, from: JSONEncoder().encode(value))
        #expect(restored == value)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func bordersRenderWithThemeTokens(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        theme.bootstrapTokens.custom["borderWidth"] = ["heavy"]
        theme.bootstrapTokens.values["border-width-heavy"] = "7px"
        theme.bootstrapTokens.custom["borderRadius"] = ["soft"]
        theme.bootstrapTokens.values["radius-soft"] = "1.25rem"
        var node = PartNode.make(.container)
        node.anchor = "border-test"
        var edges = ThemeBorderWidthValue()
        edges.setAll(.init(token: "1"))
        node.setProperty(.init(rawValue: "borders.sides"), value: .themeBorderWidth(edges))
        node.setProperty(.init(rawValue: "borders.width"), value: .choice("border-heavy"))
        node.setProperty(.init(rawValue: "borders.radius"), value: .choice("rounded-soft"))
        node.setProperty(.init(rawValue: "borders.style"), value: .choice("dashed"))
        node.setProperty(.init(rawValue: "borders.colourEnabled"), value: .boolean(true))
        node.setProperty(.init(rawValue: "borders.theme"), value: .choice("framework.danger"))
        node.setProperty(.init(rawValue: "borders.subtle"), value: .boolean(true))
        let page = Page(title: "Borders", slug: "index", parts: [node])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, language: "en", theme: theme, assets: [:], breakpoint: .mobile)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Borders", pages: [page], theme: theme))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        #expect(html.contains("border-heavy"))
        #expect(html.contains("border-subtle-danger"))
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let result = try await browser.web.evaluateJavaScript("""
            (() => { const el=document.getElementById('border-test'), s=getComputedStyle(el);
            return [s.borderTopWidth,s.borderTopStyle,s.borderTopLeftRadius,s.borderTopColor]; })()
            """) as? [String]
        #expect(result?.prefix(3) == ["7px", "dashed", "20px"])
        let colours = try await browser.web.evaluateJavaScript("""
            (() => {const el=document.getElementById('border-test');return ['light','dark'].map(mode=>{
            document.documentElement.dataset.bsTheme=mode;return getComputedStyle(el).borderTopColor;});})()
            """) as? [String]
        #expect(colours?.count == 2)
        #expect(colours?.first != colours?.last)
    }
}
