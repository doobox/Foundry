import Testing
@testable import Foundry

struct HTMLTagWhitespaceCleanupTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.preview, .published])
    func cleansGeneratedPages(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.html)
        let html = #"<div class="{{ part.class }}" {{ part.attributes }}><button class="btn  btn-solid " type="button" > Keep text </button><p class="">Empty class</p></div>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: "[]")
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: "[]"))
        let page = Page(title: "Cleanup", slug: "index", parts: [part])
        let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Cleanup", pages: [page]))
        #expect(bundle.errors.isEmpty)
        let output = try #require(bundle.file(at: "index.html")?.contents)
        #expect(output.contains(#"<button class="btn btn-solid" type="button"> Keep text </button><p>Empty class</p>"#))
    }

    @Test func cleansOnlyOpeningTagWhitespace() {
        let source = "<button class=\" btn  btn-solid\t theme-accent \" type=\"button\"  >\n  Theme Control\n</button>"
        #expect(HTMLTagWhitespaceCleanup.clean(source) == "<button class=\"btn btn-solid theme-accent\" type=\"button\">\n  Theme Control\n</button>")
        #expect(HTMLTagWhitespaceCleanup.clean("<div class='' id='x' >text</div>") == "<div id='x'>text</div>")
        #expect(HTMLTagWhitespaceCleanup.clean("<img CLASS=' \n\t ' />") == "<img/>")
        #expect(HTMLTagWhitespaceCleanup.clean("<input disabled class='a  b' >") == "<input disabled class='a b'>")
    }

    @Test func preservesAttributeValuesAndUnquotedSlash() {
        #expect(HTMLTagWhitespaceCleanup.clean("<img src=foo />") == "<img src=foo />")
        #expect(HTMLTagWhitespaceCleanup.clean("<img src=foo/>") == "<img src=foo/>")
        #expect(HTMLTagWhitespaceCleanup.clean("<div class='a  b' title='  > <div class=\"  x  \" >  ' >") == "<div class='a  b' title='  > <div class=\"  x  \" >  '>")
        #expect(HTMLTagWhitespaceCleanup.clean("<div data-class='  a  b  ' class='x&#32;y' >") == "<div data-class='  a  b  ' class='x&#32;y'>")
    }

    @Test(arguments: ["script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "noscript"])
    func preservesRawContent(element: String) {
        let body = "\n  <div class=' a  b ' > < /not-a-tag \n"
        let source = "<\(element) >\(body)</\(element)><p class=' x '>ok</p>"
        #expect(HTMLTagWhitespaceCleanup.clean(source) == "<\(element)>\(body)</\(element)><p class='x'>ok</p>")
    }

    @Test(arguments: [
        "<!-- <p class=' x ' > -->", "<![CDATA[<p class=' x ' >]]>",
        "<div class='unfinished >", "<div class='x'broken='y' >",
        "<?php echo '<div class=\" x \" >'; ?>", "<% output %><div class=' x ' >",
        "<plaintext><div class=' x ' >", "text  <  text", "<script>never closes <p class=' x ' >"
    ])
    func leavesProtectedOrMalformedContentAlone(source: String) {
        #expect(HTMLTagWhitespaceCleanup.clean(source) == source)
    }

    @Test func isIdempotentForLargePages() {
        let source = String(repeating: "<div class='  a  b ' data-title='  keep  ' > text </div>\n", count: 20_000)
        let result = HTMLTagWhitespaceCleanup.clean(source)
        #expect(result == String(repeating: "<div class='a b' data-title='  keep  '> text </div>\n", count: 20_000))
        #expect(HTMLTagWhitespaceCleanup.clean(result) == result)
    }
}
