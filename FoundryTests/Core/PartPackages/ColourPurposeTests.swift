import Foundation
import Testing
@testable import Foundry

@MainActor
struct ColourPurposeTests {
    @Test(arguments: [PartColourPurpose.background, .foreground, .border, .link])
    func inheritIsEmpty(purpose: PartColourPurpose) {
        let value = purpose.resolve("inherit", theme: .standard)
        #expect(value.className.isEmpty)
        #expect(value.color.isEmpty)
        #expect(value.css.isEmpty)
    }

    @Test
    func classesAndVariablesHaveTheSamePurpose() {
        let background = PartColourPurpose.background.resolve("theme-primary", theme: .standard)
        #expect(background.className == "bg-primary")
        #expect(background.color == "var(--bs-primary-bg)")
        #expect(background.css.isEmpty)
        let foreground = PartColourPurpose.foreground.resolve("theme-primary", theme: .standard)
        #expect(foreground.className == "fg-primary")
        #expect(foreground.color == "var(--bs-primary-fg)")
        let surface = PartColourPurpose.background.resolve("token:bg-1", theme: .standard)
        #expect(surface.className == "bg-1")
        #expect(surface.color == "var(--bs-bg-1)")
        let custom = PartColourPurpose.background.resolve("token:custom-637573746f6d2e6d696e65-bg-4", theme: .standard)
        #expect(custom.className == "fd-bg--custom-637573746f6d2e6d696e65-bg-4")
        #expect(custom.color == "var(--bs-custom-637573746f6d2e6d696e65-bg-4)")
        #expect(custom.css.contains("background-color:var(--bs-bg)"))
    }

    @Test
    func linkPairAndPaletteShade() {
        let link = PartColourPurpose.link.resolve("token:link-color", theme: .standard)
        #expect(link.color == "var(--bs-link-color)")
        #expect(link.css.contains("var(--bs-link-hover-color)"))
        #expect(link.css.contains(":focus-visible"))
        let shade = PartColourPurpose.background.resolve("token:blue-500", theme: .standard)
        #expect(shade.className.hasPrefix("fd-bg--"))
        #expect(shade.css.contains("var(--bs-blue-500)"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func htmlPartRendersClassesAndColor(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let controls = #"[{"type":"backgroundColor","id":"paint","colourSections":["surfaces","themes","palettes"],"defaults":{"xs":"theme-primary"}},{"type":"foregroundColor","id":"ink"},{"type":"borderColor","id":"edge"},{"type":"linkColor","id":"links"}]"#
        let html = #"<nav class="{{ part.class }} {{ control.paint }}" style="--chosen:{{ control.paint.color }}" {{ part.attributes }}>Colour</nav>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        for selection in ["theme-primary", "token:bg-1", "token:blue-500", "token:custom-637573746f6d2e6d696e65-bg-4", "inherit"] {
            part.setProperty(.init(rawValue: "paint"), value: .choice(selection))
            let page = Page(title: "Colour", slug: "index", parts: [part])
            let site = Site(name: "Test", pages: [page])
            let output: String
            if environment == .canvas {
                output = HTMLPageRenderer(site: site).render(page: page, theme: .standard)
            } else {
                let bundle = StaticSiteRenderer(environment: environment).render(site: site)
                #expect(bundle.errors.isEmpty)
                output = bundle.files.map(\.contents).joined()
            }
            let expected = PartColourPurpose.background.resolve(selection, theme: .standard)
            #expect(output.contains("--chosen:" + expected.color))
            if !expected.className.isEmpty { #expect(output.contains(expected.className)) }
            if !expected.css.isEmpty { #expect(output.contains(expected.css)) }
            #expect(output.contains("{{ control.paint") == false)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func hiddenOutputAndCollectionFields() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let controls = #"[{"type":"toggle","id":"enabled","defaults":{"xs":false}},{"type":"backgroundColor","id":"paint","defaults":{"xs":"theme-primary"},"visibleWhen":{"id":"enabled","value":true},"outputWhenHidden":false},{"type":"collection","id":"items","controls":[{"type":"foregroundColor","id":"ink","colourSections":["palettes"],"defaults":{"xs":"token:blue-500"}}],"defaults":{"xs":[{}]}}]"#
        let html = #"<div class="{{ part.class }}" {{ part.attributes }} data-hidden="{{ control.paint }}|{{ control.paint.color }}">{{ loop control.items as item }}<span class="{{ item.ink }}" style="--ink:{{ item.ink.color }}">Item</span>{{ endloop }}</div>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        let page = Page(title: "Colours", slug: "index", parts: [part])
        let site = Site(name: "Test", pages: [page])
        let output = StaticSiteRenderer().render(site: site).files.map(\.contents).joined()
        #expect(output.contains(#"data-hidden="|""#))
        #expect(output.contains("fd-fg--blue-500"))
        #expect(output.contains("--ink:var(--bs-blue-500)"))
        #expect(output.contains("--bs-fg:var(--bs-blue-500)"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"[{"type":"themeColors","id":"paint","colourSections":["surfaces"]}]"#,
        #"[{"type":"backgroundColor","id":"paint","colourSections":["surfaces"],"defaults":{"xs":"theme-primary"}}]"#
    ])
    func wrongColourFamilyDefaultsAreRejected(controls: String) async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let compiled = HTMLPartPrototype.compile(html: "<p>Colour</p>", css: "", javaScript: "", controls: controls)
        #expect(compiled.definition == nil)
    }
}
