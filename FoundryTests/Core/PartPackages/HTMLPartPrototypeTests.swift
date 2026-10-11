import Foundation
import Testing
@testable import Foundry

@MainActor
struct HTMLPartPrototypeTests {
    private let controls = #"[{"section":"Prototype","controls":[{"type":"text","id":"headline","label":"Headline","defaults":{"base":"Hello"}},{"type":"toggle","id":"show","defaults":{"base":true}},{"type":"spacing","id":"spacing"}]}]"#
    private let markup = #"<section class="{{ part.class }} {{ control.spacing.classes }}" {{ part.attributes }}>{{ if control.show }}<h2>{{ control.headline }}</h2>{{ endif }}<p>{{ pages.current.title }}</p></section>"#

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func rendersThroughPackagePipeline(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let compiled = HTMLPartPrototype.compile(html: markup, css: ":instance { --prototype-label: '{{ control.headline }}'; }", javaScript: "console.log('{{ control.headline }}');", controls: controls)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var part = PartNode.make(.html)
        part.applyHTMLPrototype(.init(html: markup, css: ":instance { --prototype-label: '{{ control.headline }}'; }", javaScript: "console.log('{{ control.headline }}');", controls: controls))
        part.setProperty(.init(rawValue: "headline"), value: .string("Prototype works"))
        #expect(part.definition.inspectorRows.isEmpty == false)
        let page = Page(title: "Prototype page", slug: "index", parts: [part])
        let site = Site(name: "Prototype", pages: [page])
        let output: String
        if environment == .canvas {
            output = HTMLPageRenderer(site: site).render(page: page, theme: .standard)
            #expect(output.contains("data-foundry-inline-property=\"content\""))
            #expect(output.contains(Data(markup.utf8).base64EncodedString()))
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: site)
            #expect(bundle.errors.isEmpty)
            output = try #require(bundle.file(at: "index.html")?.contents)
            let files = bundle.files.map(\.contents).joined(separator: "\n")
            #expect(files.contains("console.log('Prototype works');"))
            #expect(files.contains("--prototype-label: 'Prototype works'"))
            #expect(output.contains("data-foundry-inline-") == false)
        }
        #expect(output.contains("<h2>Prototype works</h2>"))
        #expect(output.contains("<p>Prototype page</p>"))
        #expect(output.contains("{{ control.") == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func definitionsAreLocalAndRoundTrip() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var first = PartNode.make(.html)
        let second = PartNode.make(.html)
        first.applyHTMLPrototype(.init(html: markup, css: "", javaScript: "", controls: controls))
        first.setProperty(.init(rawValue: "headline"), value: .string("Saved value"))
        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(first))
        #expect(restored == first)
        #expect(restored.property(.init(rawValue: "headline")) == "Saved value")
        #expect(restored.definition.package?.manifest.controlGroups.contains { $0.type == .spacing } == true)
        #expect(second.definition.property(for: .init(rawValue: "headline")) == nil)
        #expect(PartType.html.definition.property(for: .init(rawValue: "headline")) == nil)
        first.applyHTMLPrototype(.init(html: "<p>Plain</p>", css: "", javaScript: "", controls: "[]"))
        #expect(first.definition.property(for: .init(rawValue: "headline")) == nil)
        #expect(first.storedPropertyValue(.init(rawValue: "headline")) == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["{", "{}", #"[{"type":"unknown","id":"x"}]"#, #"[{"type":"text","id":"content","defaults":{"base":"bad"}}]"#])
    func invalidControlsDoNotCompile(declarations: String) async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let result = HTMLPartPrototype.compile(html: "<p>Test</p>", css: "", javaScript: "", controls: declarations)
        #expect(result.definition == nil)
        #expect(result.diagnostics.contains { $0.severity == .error })
    }

    @Test(.timeLimit(.minutes(1)))
    func unsupportedOptionsWarnWithoutBlocking() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let result = HTMLPartPrototype.compile(html: "<p>Test</p>", css: "", javaScript: "", controls: #"[{"type":"themeColors","id":"paint","defaults":{"base":"inherit"},"responsive":true}]"#)
        #expect(result.definition != nil, "\(result.diagnostics)")
        #expect(result.diagnostics.contains { $0.severity == .warning })
        #expect(result.definition?.package?.manifest.resolvedProperties.first?.responsive == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func responsiveDefaultsAndExistingValuesSurviveSourceEdits() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let declaration = #"[{"type":"text","id":"headline","responsive":true,"defaults":{"base":"Small","medium":"Medium"}}]"#
        var part = PartNode.make(.html)
        let source = HTMLPartSource(html: "<p>{{ control.headline }}</p>", css: "", javaScript: "", controls: declaration)
        let compiled = HTMLPartPrototype.compile(html: source.html, css: "", javaScript: "", controls: declaration)
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        part.applyHTMLPrototype(source)
        #expect(part.propertyValue(.init(rawValue: "headline"), at: .medium).stringValue == "Medium")
        part.setProperty(.init(rawValue: "headline"), value: .string("Edited"))
        part.applyHTMLPrototype(source)
        #expect(part.property(.init(rawValue: "headline")) == "Edited")
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceChangesUndoTogether() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let part = PartNode.make(.html)
        let document = FoundryDocument(site: Site(name: "Test", pages: [Page(title: "Home", slug: "index", parts: [part])]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        undo.beginUndoGrouping()
        editor.setHTMLPrototype(id: part.id, source: .init(html: markup, css: "", javaScript: "", controls: controls))
        undo.endUndoGrouping()
        #expect(document.site.part(withID: part.id)?.definition.property(for: .init(rawValue: "headline")) != nil)
        undo.undo()
        #expect(document.site.part(withID: part.id) == part)
        undo.redo()
        #expect(document.site.part(withID: part.id)?.definition.property(for: .init(rawValue: "headline")) != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func loopsPrimitivesAndChildAreasUseInstanceDefinition() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let declarations = #"[{"type":"collection","id":"cards","controls":[{"type":"text","id":"title","defaults":{"base":""}}],"defaults":{"base":[{"title":"One"},{"title":"Two"}]}}]"#
        let html = #"<article class="{{ part.class }}" {{ part.attributes }}>{{ text("intro", default: "Intro") }}{{ loop control.cards as card }}<h3>{{ card.title }}</h3>{{ endloop }}{{ dropZone("children") }}</article>"#
        let compiled = HTMLPartPrototype.compile(html: html, css: "", javaScript: "", controls: declarations)
        let definition = try #require(compiled.definition, "\(compiled.diagnostics)")
        #expect(definition.allowsChildren)
        #expect(definition.property(for: .init(rawValue: "intro")) != nil)
        var node = PartNode.make(.html)
        node.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: declarations))
        var child = PartNode.make(.html)
        child.setProperty(HTMLPartPrototype.contentKey, value: .string("<p>Nested child</p>"))
        node.children = [child]
        let site = Site(name: "Prototype", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let bundle = StaticSiteRenderer().render(site: site)
        #expect(bundle.errors.isEmpty)
        let output = try #require(bundle.file(at: "index.html")?.contents)
        #expect(output.contains("<h3>One</h3><h3>Two</h3>"))
        #expect(output.contains("<p>Nested child</p>"))
        #expect(output.contains("Intro"))
    }

    @Test(.timeLimit(.minutes(1)))
    func changingControlTypeResetsIncompatibleValues() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.html)
        node.applyHTMLPrototype(.init(html: "<p>Example</p>", css: "", javaScript: "", controls: #"[{"type":"text","id":"value","defaults":{"base":"Old"}}]"#))
        node.applyHTMLPrototype(.init(html: "<p>Example</p>", css: "", javaScript: "", controls: #"[{"type":"toggle","id":"value","defaults":{"base":true}}]"#))
        #expect(node.propertyValue(.init(rawValue: "value")) == .boolean(true))
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicateHasIndependentValuesAndDynamicDropTarget() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.html)
        let html = #"<section class="{{ part.class }}" {{ part.attributes }}><h2>{{ control.headline }}</h2>{{ dropZone("children") }}</section>"#
        part.applyHTMLPrototype(.init(html: html, css: "", javaScript: "", controls: controls))
        let page = Page(title: "Home", slug: "index", parts: [part])
        let document = FoundryDocument(site: Site(name: "Prototype", pages: [page]))
        let editor = ProjectEditor(document: document, undoManager: nil)
        let copyID = try #require(editor.duplicatePart(id: part.id, on: page.id))
        editor.setProperty(id: copyID, key: .init(rawValue: "headline"), value: .string("Copy"))
        #expect(document.site.part(withID: part.id)?.property(.init(rawValue: "headline")) == "Hello")
        #expect(document.site.part(withID: copyID)?.property(.init(rawValue: "headline")) == "Copy")
        var tree = document.site.pages[0].parts
        let child = PartNode.make(.paragraph)
        let inserted = tree.insert(child, at: .inside(copyID))
        #expect(inserted)
        #expect(tree.node(withID: copyID)?.children.first?.id == child.id)
        let bundle = StaticSiteRenderer().render(site: document.site)
        let output = try #require(bundle.file(at: "index.html")?.contents)
        #expect(output.contains("<h2>Hello</h2>"))
        #expect(output.contains("<h2>Copy</h2>"))
    }

    @Test(.timeLimit(.minutes(1)))
    func childPickerInitialPartsAreAddedOnlyOnce() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let source = HTMLPartSource(html: #"<section class="{{ part.class }}" {{ part.attributes }}>{{ childArea("children") }}</section>"#, css: "", javaScript: "", controls: #"[{"type":"childPicker","id":"children","pickerItems":["foundry.content.paragraph"],"initial":["foundry.content.paragraph"]}]"#)
        let compiled = HTMLPartPrototype.compile(html: source.html, css: "", javaScript: "", controls: source.controls ?? "[]")
        try #require(compiled.definition != nil, "\(compiled.diagnostics)")
        var node = PartNode.make(.html)
        node.applyHTMLPrototype(source)
        #expect(node.children.count == 1)
        #expect(node.children.first?.type == .paragraph)
        #expect(node.children.first?.slotID == "children")
        node.applyHTMLPrototype(source)
        #expect(node.children.count == 1)
    }
}
