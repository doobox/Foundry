import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapMediaTests {
    @Test(.timeLimit(.minutes(1)))
    func customThemeClassesMatchBootstrapComponents() async throws {
        let model = FrameworkColourPreviewModel()
        model.addTheme(named: "brand")
        let source = BootstrapColourCatalogue.palette(role: .primary, hue: "pink")
        let custom = BootstrapPaletteTheme.applying(source, to: try #require(model.storedPalettes.last))
        var framework = Framework.standard
        framework.colourPalettes = [source, custom]
        let css = BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let navigation = MediaNavigation()
        defer { web.stopLoading() }
        try await navigation.load("<style>\(css)</style><button id='native'>Native</button><button id='custom'>Custom</button>", in: web)
        let errors = try await web.evaluateJavaScript("""
          (() => {
            const a=document.getElementById('native'), b=document.getElementById('custom'), errors=[];
            for(const mode of ['light','dark']) {
              document.documentElement.dataset.bsTheme=mode;
              for(const variant of ['btn-solid','btn-outline','btn-subtle','btn-ghost']) {
                a.className='btn '+variant+' theme-primary'; b.className='btn '+variant+' theme-brand';
                for(const property of ['color','backgroundColor','borderTopColor']) {
                  if(getComputedStyle(a)[property]!==getComputedStyle(b)[property]) errors.push(mode+'/'+variant+'/'+property);
                }
              }
              for(const utility of ['fg','fg-emphasis','fg-contrast','bg','bg-subtle','bg-muted','border','border-subtle','underline','shadow']) {
                a.className=utility+'-primary'; b.className=utility+'-brand';
                for(const property of ['color','backgroundColor','borderTopColor','textDecorationColor']) {
                  if(getComputedStyle(a)[property]!==getComputedStyle(b)[property]) errors.push(mode+'/'+utility+'/'+property);
                }
              }
            }
            return errors;
          })()
          """) as? [String]
        #expect(errors == [])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [false, true])
    func svgPaintOverrideUsesThemeAndRestoresOriginal(environment: PartTemplateEnvironment, enabled: Bool) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let data = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><g color="green"><path fill="red" style="stroke:blue!important" d="M0 0L10 10"/></g><path fill="none" d="M0 0L1 1"/></svg>"#.utf8)
        let asset = ProjectAsset(filename: "paint.svg", mediaType: "image/svg+xml", byteCount: data.count, contentDigest: "paint")
        let assets: ProjectAssetContents = [asset.id: .init(asset: asset, data: data)]
        var part = PartNode.make(.svg)
        part.anchor = "paint"
        part.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        part.setProperty(.init(rawValue: "foreground.theme"), value: .choice("framework.primary"))
        part.setProperty(.init(rawValue: "fillEnabled"), value: .boolean(enabled))
        part.setProperty(.init(rawValue: "strokeEnabled"), value: .boolean(enabled))
        let page = Page(title: "Paint", slug: "index", parts: [part])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: assets, breakpoint: .mobile)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Paint", pages: [page]), assets: assets)
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let navigation = MediaNavigation()
        defer { web.stopLoading() }
        try await navigation.load(html, in: web)
        let errors = try await web.evaluateJavaScript("""
            (() => {
              const root=document.getElementById('paint'), shape=root.querySelector('g path'), errors=[];
              for(const mode of ['light','dark']) {
                document.documentElement.dataset.bsTheme=mode;
                const color=getComputedStyle(root).color, paint=getComputedStyle(shape);
                if(paint.fill!==(\(enabled) ? color : 'rgb(255, 0, 0)')) errors.push('fill/'+mode);
                if(paint.stroke!==(\(enabled) ? color : 'rgb(0, 0, 255)')) errors.push('stroke/'+mode);
                const empty=getComputedStyle(root.querySelector(':scope > path'));
                if(empty.fill!=='none'||empty.stroke!=='none') errors.push('unpainted/'+mode);
              }
              return errors;
            })()
            """) as? [String]
        #expect(errors == [])
    }
    @Test(arguments: [PartType.html, .svg, .image])
    func restoredPartsAreNativeAndHaveNoLegacyCSS(type: PartType) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let package = try #require(type.definition.package)
        try package.preparePayload()
        #expect(package.css.isEmpty)
        #expect(package.instanceJavaScript.isEmpty)
        #expect(type.definition.allowsChildren == false)
        #expect(package.manifest.controlGroups.allSatisfy { $0.type.generatesBootstrapClasses || $0.type == .advanced })
    }

    @Test(arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func rawHTMLHasOnlyACanvasWrapper(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.html)
        let authored = #"<h2 class="fg-primary">Custom</h2><p class="mb-5">Literal {{ untouched }} &amp; content</p>"#
        part.setProperty(.init(rawValue: "content"), value: .string(authored))
        let page = Page(title: "HTML", slug: "index", parts: [part])
        let output: String
        if environment == .canvas {
            output = HTMLPageRenderer().render(page: page, framework: .standard)
            #expect(output.contains("data-foundry-inline-html"))
            #expect(output.contains("data-foundry-id"))
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "HTML", pages: [page]))
            #expect(bundle.errors.isEmpty)
            output = try #require(bundle.file(at: "index.html")?.contents)
            #expect(output.contains("<div") == false)
            #expect(output.contains("data-foundry-") == false)
        }
        #expect(output.contains(authored))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published], [375, 800])
    func mediaMatchesNativeBootstrap(environment: PartTemplateEnvironment, width: Int) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let data = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50" width="100" height="50"><path fill="currentColor" d="M0 0H50V50H0Z"/><path fill="red" d="M50 0H100V50H50Z"/><text>{{ literal }}</text></svg>"#.utf8)
        let asset = ProjectAsset(filename: "art.svg", mediaType: "image/svg+xml", byteCount: data.count, contentDigest: "media-svg")
        let assets: ProjectAssetContents = [asset.id: .init(asset: asset, data: data)]
        var svg = PartNode.make(.svg)
        svg.anchor = "art"
        svg.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        svg.setProperty(PartPackageAdapter.imageAltKey(for: "source"), value: .string("Two colours"))
        svg.setProperty(.init(rawValue: "foreground.theme"), value: .choice("framework.primary"))
        svg.setProperty(.init(rawValue: "sizing.width"), value: .choice("w-50"))
        svg.setProperty(.init(rawValue: "sizing.height"), value: .choice("h-auto"))
        svg.setResponsiveProperty(.init(rawValue: "display.display"), value: .choice("d-none"), at: .medium)
        var image = PartNode.make(.image)
        image.anchor = "photo"
        // A data URL avoids any network or missing-file loads during computed-style checks.
        image.setProperty(.init(rawValue: "source"), value: .url("data:image/svg+xml;base64," + data.base64EncodedString()))
        image.setProperty(.init(rawValue: "appearance"), value: .choice("img-thumbnail"))
        image.setProperty(.init(rawValue: "sizing.width"), value: .choice("w-50"))
        image.setProperty(.init(rawValue: "sizing.aspectRatio"), value: .choice("ratio-1x1"))
        image.setProperty(.init(rawValue: "objectFit.fit"), value: .choice("object-fit-cover"))
        image.setResponsiveProperty(.init(rawValue: "objectFit.fit"), value: .choice("object-fit-contain"), at: .medium)
        image.setProperty(.init(rawValue: "borders.radius"), value: .choice("rounded-circle"))
        let page = Page(title: "Media", slug: "index", parts: [svg, image])
        let initial = try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en",
            framework: .standard, assets: assets, breakpoint: .medium, packageRevision: 0, previous: nil)
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, language: "en", framework: .standard, assets: assets, breakpoint: .medium)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Media", pages: [page], assets: [asset]), assets: assets)
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            #expect(source.contains("fd-inline-svg") == false)
            #expect(source.contains("<figure") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 600), configuration: configuration)
        let navigation = MediaNavigation()
        defer { web.stopLoading() }
        try await navigation.load(html, in: web)
        let errors = try await web.evaluateJavaScript("""
            (() => {
                const errors=[], svg=document.getElementById('art'), img=document.getElementById('photo');
                if(svg.tagName.toLowerCase()!=='svg') errors.push('SVG has wrapper');
                if(img.tagName!=='IMG') errors.push('Image has wrapper');
                if(svg.getAttribute('viewBox')!=='0 0 100 50') errors.push('Lost viewBox');
                if(svg.getAttribute('aria-label')!=='Two colours') errors.push('Lost accessible name');
                if(svg.querySelector('text').textContent!=='{{ literal }}') errors.push('Imported template evaluated');
                const rs=svg.cloneNode(true), ri=img.cloneNode(true);
                rs.removeAttribute('id'); ri.removeAttribute('id');
                rs.className.baseVal='max-w-100 fg-primary w-50 h-auto md:d-none';
                ri.className='img-thumbnail w-50 ratio-1x1 object-fit-cover md:object-fit-contain rounded-circle';
                svg.after(rs);img.after(ri);
                for(const mode of ['light','dark']) {
                    document.documentElement.dataset.bsTheme=mode;
                    for(const direction of ['ltr','rtl']) {
                        document.documentElement.dir=direction;
                        for(const [a,b] of [[svg,rs],[img,ri]]) {
                            const sa=getComputedStyle(a), sb=getComputedStyle(b);
                            for(const p of ['display','width','height','maxWidth','color','objectFit','aspectRatio','borderRadius','borderTopWidth','paddingTop']) {
                                if(sa[p]!==sb[p]) errors.push(mode+'/'+direction+'/'+p+': '+sa[p]+' != '+sb[p]);
                            }
                        }
                        if(getComputedStyle(svg.querySelector('path')).fill!==getComputedStyle(svg).color) errors.push('currentColor lost');
                        if(getComputedStyle(svg.querySelectorAll('path')[1]).fill!=='rgb(255, 0, 0)') errors.push('Explicit paint replaced');
                    }
                }
                rs.remove();ri.remove();return errors;
            })()
            """) as? [String]
        #expect(errors == [])
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('photo')).objectFit") as? String == (width == 800 ? "contain" : "cover"))
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('art')).display") as? String == (width == 800 ? "none" : "inline"))
        if environment == .canvas && width == 800 {
            var edited = page
            var previous = initial.scene
            let key = PartProperty.Key(rawValue: "objectFit.fit")
            for (revision, value) in ["object-fit-fill", "none"].enumerated() {
                if value == "none" {
                    edited.parts[1].removeResponsiveOverride(key, at: .medium)
                } else {
                    edited.parts[1].setResponsiveProperty(key, value: .choice(value), at: .medium)
                }
                let result = try CanvasScene.render(renderer: HTMLPageRenderer(), page: edited, language: "en",
                    framework: .standard, assets: assets, breakpoint: .medium, packageRevision: 0, previous: previous,
                    consecutiveImpact: .partProperty(partID: image.id, propertyKey: key))
                guard case .scene(let update) = result.result else { Issue.record("Expected live media patch"); return }
                let applied = try await web.callAsyncJavaScript(
                    "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                    arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                        "roots": update.roots as Any? ?? NSNull(), "revision": revision + 1,
                        "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                    in: nil, contentWorld: .defaultClient)
                try #require(applied as? Bool == true)
                #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('photo')).objectFit") as? String == (value == "none" ? "cover" : "fill"))
                previous = result.scene
            }
        }
    }

    @Test(arguments: [PartPackageControlGroup.Kind.sizing, .borders, .objectFit, .foreground])
    func mediaGroupsEmitOnlyClasses(kind: PartPackageControlGroup.Kind) {
        let group = PartPackageControlGroup(type: kind, id: "test")
        #expect(group.type.generatesBootstrapClasses)
        #expect(group.properties.allSatisfy { $0.responsive == (kind == .objectFit) })
        var values: [String: PartPackageValue] = [:]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        #expect(values["test.css"] == nil)
        #expect(values["test.classes"] == .string(""))
    }
}

@MainActor
private final class MediaNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?
    func load(_ html: String, in web: WKWebView) async throws {
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
}
