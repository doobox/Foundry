import Foundation
import Testing
@testable import Foundry

@MainActor
struct BootstrapBaselineTests {
    @Test(arguments: [PartType.container, .flex, .grid])
    func layoutPartsSupportInsertionMovementAndUndo(type: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let document = FoundryDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = ProjectEditor(document: document, undoManager: undo)
        let page = try #require(document.site.pages.first)
        undo.beginUndoGrouping()
        let containerID = try #require(editor.insertPart(type: type, on: page.id, placement: .end))
        let buttonID = try #require(editor.insertPart(type: .button, on: page.id, placement: .inside(containerID)))
        undo.endUndoGrouping()
        #expect(document.site.pages[0].parts.node(withID: containerID)?.children.first?.id == buttonID)
        undo.undo()
        #expect(document.site.pages[0].parts.isEmpty)
        undo.redo()
        #expect(document.site.pages[0].parts.node(withID: containerID)?.children.first?.id == buttonID)
        undo.beginUndoGrouping()
        #expect(editor.movePart(id: buttonID, on: page.id, to: .end))
        undo.endUndoGrouping()
        #expect(document.site.pages[0].parts.last?.id == buttonID)
        undo.undo()
        #expect(document.site.pages[0].parts.node(withID: containerID)?.children.first?.id == buttonID)
    }

    @Test func builtInLibraryContainsOnlyTheNewBaseline() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let packages = PartPackageCatalog.shared.packages.values.filter {
            $0.rootURL.path.contains("BuiltInParts.foundrypack/Parts/")
        }
        #expect(Set(packages.map { $0.manifest.identifier }) == Set([
            "foundry.content.button", "foundry.layout.container", "foundry.content.paragraph",
            "foundry.layout.flex", "foundry.layout.grid", "foundry.content.html",
            "foundry.media.svg", "foundry.media.image", "foundry.content.card", "foundry.layout.background",
            "foundry.layout.element"
        ]))
        let container = try #require(PartType.container.definition.package)
        #expect(container.css.isEmpty)
        #expect(container.instanceJavaScript.isEmpty)
        #expect(PartType.container.definition.allowsChildren)
        #expect(PartType.container.definition.properties.contains { $0.key.rawValue == "spacing.margin" })
        #expect(PartType.paragraph.definition.package != nil)
    }

    @Test(arguments: ["container", "container-fluid", "sm:container", "md:container", "lg:container", "xl:container", "2xl:container"])
    func nestedBootstrapOutputIsCleanInPreviewAndExport(width: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let button = PartNode.make(.button)
        var inner = PartNode.make(.container)
        inner.setProperty(.init(rawValue: "width"), value: .choice(width))
        inner.children = [button]
        var outer = PartNode.make(.container)
        outer.children = [inner]
        let page = Page(title: "Bootstrap", slug: "index", parts: [outer])
        let site = Site(name: "Bootstrap", pages: [page])
        let canvas = HTMLPageRenderer().render(page: page, theme: site.theme)
        #expect(canvas.contains("data-foundry-parent=\"\(inner.id.uuidString)\""))
        #expect(canvas.contains("data-foundry-id=\"\(button.id.uuidString)\""))
        #expect(canvas.contains("Foundry CSS 1") == false)

        var bodies: [String] = []
        for environment in [PartTemplateEnvironment.preview, .published] {
            let bundle = StaticSiteRenderer(environment: environment).render(site: site)
            #expect(bundle.errors.isEmpty)
            let html = try #require(bundle.file(at: "index.html")?.contents)
            let start = try #require(html.range(of: "<body>"))
            let end = try #require(html.range(of: "</body>"))
            let body = String(html[start.upperBound..<end.lowerBound])
            // Published assets receive a cache-busting query; component markup
            // must otherwise be identical to preview.
            bodies.append(body.components(separatedBy: "<script")[0])
            #expect(body.contains("data-foundry-") == false)
            #expect(body.contains("foundry-package-") == false)
            #expect(body.contains("c-\(button.id.uuidString.lowercased())") == false)
            // A default Button inherits any enclosing theme, so it carries no theme class of its own.
            #expect(body.contains("btn btn-solid"))
            #expect(body.contains("theme-") == false)
            #expect(body.contains(BootstrapLayout.containerClass(width, screens: site.theme.screens)))
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            #expect(css.contains("Foundry CSS 1") == false)
            #expect(css.contains("--foundry-font-body:") == false)
            #expect(css.contains(".fd-p-") == false)
            #expect(css.contains(".container-fluid"))
        }
        #expect(bodies[0] == bodies[1])
    }

    @Test func emptyContainerHasCanvasDropTargetButNoPublishedWrapper() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let container = PartNode.make(.container)
        let page = Page(title: "Empty", slug: "index", parts: [container])
        let site = Site(name: "Empty", pages: [page])
        let canvas = HTMLPageRenderer().render(page: page, theme: site.theme)
        #expect(canvas.contains("data-foundry-empty-parent=\"\(container.id.uuidString)\""))
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(html.contains("foundry-empty-drop-zone") == false)
        #expect(html.contains("</div>"))
    }

    @Test func explicitAnchorsClassesAndScopedCSSArePreserved() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var button = PartNode.make(.button)
        button.anchor = "contact"
        button.customClasses = "my-button"
        var page = Page(title: "Custom", slug: "index", parts: [button])
        var site = Site(name: "Custom", pages: [page])
        let clean = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(clean.contains("id=\"contact\""))
        #expect(clean.contains("my-button"))
        #expect(clean.contains("data-foundry-id") == false)
        button.customCSS = "color: red;"
        page.parts = [button]
        site.pages = [page]
        let styled = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(styled.contains("data-foundry-id=\"\(button.id.uuidString)\""))
        #expect(styled.contains("data-foundry-parent") == false)
    }
}
