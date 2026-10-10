import Testing
import WebKit
@testable import Foundry

@MainActor
struct LayoutTypographyTests {
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [PartType.container, .flex, .grid])
    func nestedTypographyInheritsAndOverrides(environment: PartTemplateEnvironment, layout: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var parent = PartNode.make(layout)
        parent.anchor = "parent"
        let manifest = try #require(parent.type.definition.package?.manifest)
        let properties = manifest.resolvedProperties.filter { $0.controlGroupSource?.type == .typography }
        #expect(properties.map(\.id) == ["typography.fontFamily", "typography.textSize", "typography.fontWeight", "typography.textAlignment"])
        for property in properties {
            #expect(BootstrapControlGroupClasses.resolve(node: parent, key: .init(rawValue: property.id), theme: .standard) == "")
        }
        parent.setProperty(.init(rawValue: "typography.fontFamily"), value: .choice("font-monospace"))
        for (key, base, medium) in [("textSize", "text-sm", "text-lg"), ("fontWeight", "fw-normal", "fw-bold"), ("textAlignment", "text-start", "text-center")] {
            parent.setProperty(.init(rawValue: "typography." + key), value: .choice(base))
            parent.setResponsiveProperty(.init(rawValue: "typography." + key), value: .choice(medium), at: .medium)
        }
        var inherited = PartNode.make(.paragraph)
        inherited.anchor = "inherited"
        var explicit = PartNode.make(.paragraph)
        explicit.anchor = "explicit"
        for (key, value) in [("fontFamily", "font-body"), ("textSize", "text-xs"), ("fontWeight", "fw-light"), ("textAlignment", "text-end")] {
            explicit.setProperty(.init(rawValue: "typography." + key), value: .choice(value))
        }
        var nested = PartNode.make(layout)
        nested.children = [inherited, explicit]
        parent.children = [nested]
        let page = Page(title: "Typography", slug: "index", parts: [parent])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Typography", pages: [page], theme: .standard))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            let css = try #require(bundle.file(at: "files/site.css")?.contents) + (try #require(bundle.file(at: "files/page.css")?.contents))
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        for width in [375, 800] {
            let browser = BootstrapTokenBrowser()
            browser.web.frame.size.width = CGFloat(width)
            try await browser.load(html)
            let errors = try await browser.web.evaluateJavaScript("""
                (()=>{const errors=[],parent=document.getElementById('parent'),inherited=document.getElementById('inherited'),explicit=document.getElementById('explicit');
                const reference=document.createElement('p');
                reference.className='font-monospace text-sm md:text-lg fw-normal md:fw-bold text-start md:text-center';
                document.body.append(reference);
                const compare=(actual,expected,label)=>{for(const key of ['fontFamily','fontSize','lineHeight','fontWeight','textAlign']){
                  if(getComputedStyle(actual)[key]!==getComputedStyle(expected)[key])errors.push(label+' '+key);
                }};
                compare(parent,reference,'parent');compare(inherited,reference,'inherited');
                reference.className='font-body text-xs fw-light text-end';compare(explicit,reference,'explicit');
                if(getComputedStyle(parent).fontWeight!==(innerWidth>=768?'700':'400'))errors.push('responsive weight');
                return errors;})()
                """) as? [String]
            #expect(errors == [], "Viewport: \(width)")
        }
    }
}
