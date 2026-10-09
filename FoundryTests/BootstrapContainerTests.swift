import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapContainerTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"])
    func spacingGroupUsesNativeResponsiveUtilities(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.container)
        node.anchor = "spacing-test"
        let horizontal = PartProperty.Key(rawValue: "spacing.padding")
        var padding = FrameworkPaddingValue()
        padding.setAll(.init(token: "3"))
        padding.set(.init(token: "2"), for: .left)
        padding.set(.init(token: "2"), for: .right)
        node.setProperty(horizontal, value: .frameworkPadding(padding))
        padding.togglePair(using: .left)
        padding.set(.init(token: "5"), for: .left)
        #expect(padding.value(for: .right).token == "5")
        node.setResponsiveProperty(horizontal, value: .frameworkPadding(padding), at: .medium)
        padding.set(.init(token: "12"), for: .left)
        node.setResponsiveProperty(horizontal, value: .frameworkPadding(padding), at: .extraLarge)
        var margin = FrameworkMarginValue()
        margin.setAll(.init(token: "none"))
        margin.set(.init(token: "hero"), for: .top)
        margin.set(.init(token: "hero"), for: .bottom)
        node.setProperty(.init(rawValue: "spacing.margin"), value: .frameworkMargin(margin))
        var framework = Framework.standard
        framework.spacing.custom = [.init(name: "hero", value: 6)]
        #expect(BootstrapSpacingClasses.resolve(node: node.resolved(at: .medium), key: horizontal, screens: framework.screens) == "py-3 px-2 md:py-3 md:px-5")
        var allScreens = framework.screens
        allScreens.update(.extraLarge) { $0.isEnabled = true }
        #expect(BootstrapSpacingClasses.resolve(node: node, key: horizontal, screens: allScreens)?.contains("xl:px-12") == true)
        let page = Page(title: "Spacing", slug: "index", parts: [node])
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, framework: framework)
        } else {
            var site = Site(name: "Spacing", pages: [page])
            site.framework = framework
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
            #expect(bundle.errors.isEmpty)
            let output = try #require(bundle.file(at: "index.html"))
            #expect(output.contents.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = output.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        for _ in 0..<200 {
            if (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('spacing-test')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        for width in [375, 768, 1400] {
            view.setFrameSize(CGSize(width: width, height: 600))
            for _ in 0..<100 {
                if (try? await view.evaluateJavaScript("innerWidth === \(width)")) as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let values = try #require(try await view.evaluateJavaScript("(() => { const e=document.getElementById('spacing-test'), s=getComputedStyle(e), rem=parseFloat(getComputedStyle(document.documentElement).fontSize); return [parseFloat(s.paddingLeft)/rem,parseFloat(s.paddingTop)/rem,parseFloat(s.marginTop)/rem]; })()") as? [Double])
            #expect(values == [(width < 768 ? 0.375 : 1), 0.5, 6], "\(destination) at \(width)")
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"])
    func nativeWidthsAndGuttersAtBreakpointBoundaries(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let classes = ["container", "container-fluid", "sm:container", "md:container", "lg:container", "xl:container", "2xl:container"]
        let containers = classes.enumerated().map { index, value in
            var container = PartNode.make(.container)
            container.anchor = "sample-\(index)"
            container.setProperty(.init(rawValue: "width"), value: .choice(value))
            container.children = [PartNode.make(.button)]
            return container
        }
        let page = Page(title: "Containers", slug: "index", parts: containers)
        var site = Site(name: "Containers", pages: [page])
        site.framework.screens.update(.extraLarge) { $0.isEnabled = true }
        site.framework.screens.update(.doubleExtraLarge) { $0.isEnabled = true }
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, framework: site.framework)
        } else {
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
            #expect(bundle.errors.isEmpty)
            let output = try #require(bundle.file(at: "index.html"))
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
                                const element = document.getElementById('sample-'+index);
                                if (!element.classList.contains(value)) errors.push('Missing class '+value);
                                if (element.querySelectorAll('a.btn').length !== 1) errors.push('Missing child '+value);
                                const reference = document.createElement('div');
                                reference.className = value;
                                element.parentElement.append(reference);
                                const actual = getComputedStyle(element), expected = getComputedStyle(reference);
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
