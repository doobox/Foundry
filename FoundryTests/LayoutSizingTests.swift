import Testing
import WebKit
@testable import Foundry

@MainActor
struct LayoutSizingTests {
    @Test(arguments: [PartType.button, .container, .flex, .grid, .paragraph, .html, .image, .svg])
    func inspectorOrderIsConsistent(part: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let manifest = try #require(part.definition.package?.manifest)
        let order = ["Content": 0, "Image": 0, "SVG": 0, "Icon": 1, "Action": 2,
                     "Appearance": 3, "Container": 4, "Flex": 4, "Grid": 4,
                     "Sizing": 5, "Object fit": 6, "Alignment": 7, "Gap": 8,
                     "Spacing": 9, "Typography": 10, "Content typography": 11,
                     "Foreground": 12, "Background": 13, "Borders": 14,
                     "Shadows": 15, "Links": 16, "Display": 17, "Accessibility": 18]
        let ranks = try manifest.controlSections.map { try #require(order[$0.name], "Unclassified section: \($0.name)") }
        #expect(ranks == ranks.sorted())
        if case .group(let group) = manifest.controlsEntries.last {
            #expect(group.type == .advanced)
        } else {
            Issue.record("Advanced must be last")
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [PartType.container, .flex, .grid])
    func sizingMatchesNativeUtilities(environment: PartTemplateEnvironment, layout: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(layout)
        part.anchor = "sized"
        let manifest = try #require(layout.definition.package?.manifest)
        let group = try #require(manifest.controlGroups.first { $0.type == .sizing })
        #expect(group.properties.allSatisfy { $0.responsive == false })
        #expect(group.properties.contains { $0.id == "sizing.width" } == (layout != .container))
        #expect(group.properties.contains { $0.id == "sizing.maxWidth" } == (layout != .container))
        for property in group.properties {
            #expect(BootstrapControlGroupClasses.resolve(node: part, key: .init(rawValue: property.id), theme: .standard) == "")
        }
        var classes = ["vh-100", "min-h-0", "max-h-100", "ratio-16x9"]
        for (key, value) in [("height", "vh-100"), ("minHeight", "min-h-0"), ("maxHeight", "max-h-100"), ("aspectRatio", "ratio-16x9")] {
            part.setProperty(.init(rawValue: "sizing." + key), value: .choice(value))
        }
        if layout != .container {
            for (key, value) in [("width", "w-50"), ("minWidth", "min-w-0"), ("maxWidth", "max-w-100")] {
                part.setProperty(.init(rawValue: "sizing." + key), value: .choice(value))
                classes.append(value)
            }
        }
        let page = Page(title: "Sizing", slug: "index", parts: [part])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Sizing", pages: [page], theme: .standard))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            let css = try #require(bundle.file(at: "files/site.css")?.contents) + (try #require(bundle.file(at: "files/page.css")?.contents))
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
            (()=>{const actual=document.getElementById('sized'),ref=document.createElement('div'),errors=[];
            ref.className='\(classes.joined(separator: " "))';actual.parentElement.append(ref);
            for(const c of ref.classList)if(!actual.classList.contains(c))errors.push('missing '+c);
            for(const key of ['height','minHeight','maxHeight','aspectRatio'\(layout == .container ? "" : ", 'width','minWidth','maxWidth'")]){
              if(getComputedStyle(actual)[key]!==getComputedStyle(ref)[key])errors.push(key);
            }
            if(getComputedStyle(actual).aspectRatio!=='16 / 9')errors.push('native ratio');
            return errors;})()
            """) as? [String]
        #expect(errors == [])
    }
}
