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
        let controls = #"[{"type":"colourControls","id":"paint","include":["backgroundColor","foregroundColor","borderColor","linkColor"],"defaults":{"background":"theme-primary"}}]"#
        let html = #"<nav class="{{ part.class }} {{ control.paint.background }}" style="--chosen:{{ control.paint.background.color }}" {{ part.attributes }}>Colour</nav>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        for selection in ["theme-primary", "token:bg-1", "token:blue-500", "token:custom-637573746f6d2e6d696e65-bg-4", "inherit"] {
            part.setProperty(.init(rawValue: "paint.background"), value: .choice(selection))
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
        let controls = #"[{"type":"toggle","id":"enabled","defaults":{"xs":false}},{"type":"colourControls","id":"paint","include":["backgroundColor"],"defaults":{"background":"theme-primary"},"visibleWhen":{"id":"enabled","value":true},"outputWhenHidden":false},{"type":"collection","id":"items","controls":[{"type":"colourControls","id":"ink","include":["foregroundColor"],"defaults":{"foreground":"token:fg-body"}}],"defaults":{"xs":[{}]}}]"#
        let html = #"<div class="{{ part.class }}" {{ part.attributes }} data-hidden="{{ control.paint.background }}|{{ control.paint.background.color }}">{{ loop control.items as item }}<span class="{{ item.ink.foreground }}" style="--ink:{{ item.ink.foreground.color }}">Item</span>{{ endloop }}</div>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        let page = Page(title: "Colours", slug: "index", parts: [part])
        let site = Site(name: "Test", pages: [page])
        let output = StaticSiteRenderer().render(site: site).files.map(\.contents).joined()
        #expect(output.contains(#"data-hidden="|""#))
        #expect(output.contains("fg-body"))
        #expect(output.contains("--ink:var(--bs-fg-body)"))
    }

    @Test(.timeLimit(.minutes(1)))
    func colourControlsRendersIndependentThemeAndForegroundOutputs() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let controls = #"[{"type":"colourControls","id":"paint","include":["themeColors","foregroundColor"],"defaults":{"theme":"theme-primary","foreground":"token:fg-body"}}]"#
        let html = #"<p class="{{ part.class }} {{ control.paint.theme }} {{ control.paint.foreground }}" style="--ink:{{ control.paint.foreground.color }}" {{ part.attributes }}>Text</p>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        let page = Page(title: "Colours", slug: "index", parts: [part])
        let output = HTMLPageRenderer(site: Site(name: "Test", pages: [page])).render(page: page, theme: .standard)
        #expect(output.contains("theme-primary fg-body"))
        #expect(output.contains("--ink:var(--bs-fg-body)"))
    }

    @Test(.timeLimit(.minutes(1)))
    func includedPickersKeepTheirOwnVariantAndOpacityRows() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let controls = #"[{"type":"colourControls","id":"paint","include":["foregroundColor","backgroundColor","borderColor","linkColor"],"defaults":{"foreground":"theme-primary","foreground_variant":"emphasis","foreground_opacity":50,"background":"theme-primary","background_variant":"subtle","background_opacity":40,"border":"theme-primary","border_variant":"subtle","border_opacity":30,"link":"theme-primary","link_opacity":20}}]"#
        let html = #"<div class="{{ control.paint.foreground }} {{ control.paint.background }} {{ control.paint.border }}" style="--fg:{{ control.paint.foreground.color }};--bg:{{ control.paint.background.color }}"><a class="{{ control.paint.link }}">Link</a></div>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        let keys = Set(compiled.definition?.properties.map { $0.key.rawValue } ?? [])
        for key in ["foreground_variant", "foreground_opacity", "background_variant", "background_opacity", "border_variant", "border_opacity", "link_opacity"] {
            #expect(keys.contains("paint." + key))
        }
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        let page = Page(title: "Colours", slug: "index", parts: [part])
        let output = HTMLPageRenderer(site: Site(name: "Test", pages: [page])).render(page: page, theme: .standard)
        #expect(output.contains("fg-emphasis-primary fg-50"))
        #expect(output.contains("bg-subtle-primary bg-40"))
        #expect(output.contains("border-subtle-primary border-30"))
        #expect(output.contains("fd-link--primary-fg--o20"))
        #expect(output.contains("--fg:color-mix(in oklch, var(--bs-primary-fg-emphasis) 50%, transparent)"))
        #expect(output.contains("--bg:color-mix(in oklch, var(--bs-primary-bg-subtle) 40%, transparent)"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"[{"type":"colourControls","id":"paint","include":["themeColors"],"defaults":{"theme":"token:bg-1"}}]"#,
        #"[{"type":"colourControls","id":"paint","include":["foregroundColor"],"defaults":{"foreground":"token:bg-1"}}]"#
    ])
    func wrongColourFamilyDefaultsAreRejected(controls: String) async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let compiled = HTMLPartPrototype.compile(html: "<p>Colour</p>", css: "", javaScript: "", controls: controls)
        #expect(compiled.definition == nil)
    }
}
