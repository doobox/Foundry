import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapContainerTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"])
    func nativeWidthsAndGuttersAtBreakpointBoundaries(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let propertyIDs = PartNode.make(.container).definition.properties.map(\.key.rawValue)
        #expect(propertyIDs.contains("background.backgroundMode"))
        #expect(propertyIDs.contains("width"))
        #expect(propertyIDs.contains("contentSpacing"))
        #expect(propertyIDs.contains("theme") == false)
        let classes = ["container", "container-fluid", "sm:container", "md:container", "lg:container", "xl:container", "2xl:container"]
        let containers = classes.enumerated().map { index, value in
            var container = PartNode.make(.container)
            container.anchor = "sample-\(index)"
            container.setProperty(.init(rawValue: "width"), value: .choice(value))
            container.setProperty(.init(rawValue: "theme"), value: .choice("theme-danger"))
            container.setProperty(.init(rawValue: "background.backgroundMode"), value: .choice("static"))
            container.setProperty(.init(rawValue: "background.backgroundColor"), value: .choice("token:black"))
            if index > 0 { container.setProperty(.init(rawValue: "contentSpacing"), value: .choice("space-y-24")) }
            container.children = [PartNode.make(.container), PartNode.make(.button)]
            return container
        }
        let page = Page(title: "Containers", slug: "index", parts: containers)
        var site = Site(name: "Containers", pages: [page])
        site.theme.screens.update(.extraLarge) { $0.isEnabled = true }
        site.theme.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, theme: site.theme)
        } else {
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
            #expect(bundle.errors.isEmpty)
            let output = try #require(bundle.file(at: "index.html"))
            #expect(bundle.file(at: FoundryWebLibraryRegistry.bootstrapStylesheetPath) != nil)
            #expect(output.contents.contains("bootstrap-extensions.css") == false)
            #expect(output.contents.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = output.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 800))
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('sample-6')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        for width in [375, 575, 576, 767, 768, 1023, 1024, 1279, 1280, 1535, 1536, 1800] {
            view.setFrameSize(CGSize(width: width, height: 800))
            var resized = false
            for _ in 0..<100 {
                resized = (try? await view.evaluateJavaScript("innerWidth === \(width)")) as? Bool == true
                if resized { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(resized)
            let errors = try #require(try await view.evaluateJavaScript("""
                (() => {
                    const classes = ['container','container-fluid','sm:container','md:container','lg:container','xl:container','2xl:container'];
                    const thresholds = [0,Infinity,576,768,1024,1280,1536];
                    const stops = [[576,540],[768,720],[1024,960],[1280,1200],[1536,1440]];
                    const errors = [];
                    for (const mode of ['light','dark']) {
                        document.documentElement.dataset.bsTheme = mode;
                        for (const direction of ['ltr','rtl']) {
                            document.documentElement.dir = direction;
                            classes.forEach((value,index) => {
                                const wrapper = document.getElementById('sample-'+index);
                                const element = wrapper.firstElementChild;
                                if (!wrapper.classList.contains('w-100')) errors.push('Missing full-width wrapper '+value);
                                if (wrapper.classList.contains(value)) errors.push('Container width applied to wrapper '+value);
                                if (Math.abs(wrapper.getBoundingClientRect().width-wrapper.parentElement.clientWidth)>1) errors.push('Wrapper not full width '+value);
                                if (!element.classList.contains(value)) errors.push('Missing class '+value);
                                if (Array.from(element.classList).some(name => /^space-y-[0-9a-f]{24}$/.test(name)) !== (index > 0)) errors.push('Wrong spacing class '+value);
                                const spacing = parseFloat(getComputedStyle(element.firstElementChild).marginBottom);
                                const expectedSpacing = index > 0 ? 16*parseFloat(getComputedStyle(document.documentElement).fontSize) : 0;
                                if (Math.abs(spacing-expectedSpacing)>0.1) errors.push('Wrong child spacing '+value+': '+spacing);
                                if (element.querySelectorAll('a.btn').length !== 1) errors.push('Missing child '+value);
                                const reference = document.createElement('div');
                                reference.className = value;
                                element.parentElement.append(reference);
                                const actual = getComputedStyle(element), expected = getComputedStyle(reference);
                                if (getComputedStyle(wrapper).backgroundColor !== 'rgb(0, 0, 0)') errors.push('Background not on wrapper '+value);
                                if (actual.backgroundColor !== 'rgba(0, 0, 0, 0)') errors.push('Inner container paints background '+value);
                                if (wrapper.classList.contains('theme-danger')) errors.push('Removed theme control still applied '+value);
                                for (const key of ['width','maxWidth','paddingLeft','paddingRight','marginLeft','marginRight']) {
                                    if (actual[key] !== expected[key]) errors.push(value+'/'+key+': '+actual[key]+' != '+expected[key]);
                                }
                                let cap = 'none';
                                if (innerWidth >= thresholds[index]) {
                                    for (const [breakpoint,max] of stops) if (innerWidth >= breakpoint) cap = max+'px';
                                }
                                if (actual.maxWidth !== cap) errors.push(value+' maxWidth '+actual.maxWidth+' expected '+cap);
                                const gutter = parseFloat(getComputedStyle(document.documentElement).fontSize)*0.75;
                                if (Math.abs(parseFloat(actual.paddingLeft)-gutter)>0.1 || Math.abs(parseFloat(actual.paddingRight)-gutter)>0.1) errors.push('Wrong gutters '+value);
                                reference.remove();
                            });
                        }
                    }
                    return errors;
                })()
                """) as? [String])
            #expect(errors.isEmpty, "\(destination), viewport \(width): \(errors.joined(separator: "; "))")
        }
    }
}
