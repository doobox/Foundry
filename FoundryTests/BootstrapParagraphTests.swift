import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapParagraphTests {
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func htmlIsUnwrappedAndInheritsParentTheme(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.html)
        #expect(PartType.html.definition.properties.contains { $0.key.rawValue.hasPrefix("prose.") } == false)
        #expect(PartType.html.definition.package?.manifest.controlGroups.contains { $0.type == .advanced } == false)
        part.anchor = "old-html-anchor"
        // Previously saved Prose settings must no longer affect the output.
        part.setProperty(.init(rawValue: "prose.style"), value: .choice("prose"))
        part.setProperty(.init(rawValue: "content"), value: .string(#"<div class="form-field"><div class="switch" id="inherited-switch"><input type="checkbox" role="switch" switch checked></div><label>Switch</label></div>"#))
        var container = PartNode.make(.container)
        container.anchor = "html-theme"
        container.customClasses = "theme-danger"
        container.children = [part]
        let page = Page(title: "HTML theme", slug: "index", parts: [container])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "HTML theme", pages: [page]))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            #expect(source.contains("old-html-anchor") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [], root = document.getElementById('html-theme');
          if (!root || !root.classList.contains('theme-danger')) return ['missing advanced class'];
          if (root.classList.contains('prose')) errors.push('unexpected prose');
          const sw = document.getElementById('inherited-switch');
          if (\(environment != .canvas) && sw.parentElement.parentElement !== root.firstElementChild)
            errors.push('unexpected HTML wrapper');
          const probe = document.createElement('div');
          probe.style.backgroundColor = 'var(--bs-danger-bg)';
          root.append(probe);
          sw.style.transition = 'none';
          for (const mode of ['light', 'dark']) {
            root.setAttribute('data-bs-theme', mode);
            if (getComputedStyle(sw).backgroundColor !== getComputedStyle(probe).backgroundColor)
              errors.push('switch theme ' + mode);
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func truncationSelectionAndProseRenderNatively(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var paragraph = PartNode.make(.paragraph)
        paragraph.anchor = "truncated"
        paragraph.setProperty(.init(rawValue: "content"), value: .string(String(repeating: "Long text ", count: 60)))
        paragraph.setProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-truncate"))
        paragraph.setProperty(.init(rawValue: "typography.userSelect"), value: .choice("user-select-all"))
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: .init(rawValue: "typography.textWrap"), theme: .standard) == "text-truncate")
        var container = PartNode.make(.container)
        container.anchor = "prose-container"
        container.customClasses = "prose"
        container.children = [PartNode.make(.paragraph)]
        let page = Page(title: "Text helpers", slug: "index", parts: [paragraph, container])
        let html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Text helpers", pages: [page]))
            #expect(bundle.errors.isEmpty)
            let source = try #require(bundle.file(at: "index.html")?.contents)
            #expect(source.contains("data-foundry-") == false)
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined()
            html = source.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (()=>{const errors=[],p=document.getElementById('truncated'),s=getComputedStyle(p);
          if(s.whiteSpace!=='nowrap'||s.textOverflow!=='ellipsis'||s.overflowX!=='hidden') errors.push('truncation');
          if(p.scrollWidth<=p.clientWidth) errors.push('not overflowing');
          if(s.userSelect!=='all'&&s.webkitUserSelect!=='all') errors.push('selection');
          for(const id of ['prose-container']) {
            const e=document.getElementById(id);
            if(!e.classList.contains('prose')||getComputedStyle(e).display!=='flex') errors.push(id);
          }
          return errors;})()
        """) as? [String]
        #expect(errors == [])
        paragraph.setProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-wrap"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-pretty"), at: .medium)
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: .init(rawValue: "typography.textWrap"), theme: .standard) == "text-wrap md:text-pretty")
    }

    @Test(.timeLimit(.minutes(1))) func reusableLinkStylingProducesNativeClasses() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let id = "test.links." + UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".foundrypack", directoryHint: .isDirectory)
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = """
        {"id":"\(id)","title":"Links","version":"1.0.0","minimumAPIVersion":1,
         "libraries":[{"id":"bootstrap","majorVersion":6}],
         "inspector":[{"section":"Links","controls":[{"type":"linkStyling","id":"links"},{"type":"typography","id":"type","excludeControls":["fontSize"]}]}],
         "templates":{"html":"part.html"}}
        """
        try Data(manifest.utf8).write(to: root.appending(path: "manifest.json"))
        try Data(##"<a href="#" class="{{ part.class }} {{ control.links.classes }} {{ control.type.classes }}" {{ part.attributes }}>Link</a>"##.utf8).write(to: resources.appending(path: "part.html"))
        let package = try PartPackageLoader.load(from: root)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: id) }
        var node = PartNode.make(PartType(rawValue: id))
        node.anchor = "styled-link"
        node.setProperty(.init(rawValue: "links.colour"), value: .choice("token:link-color"))
        node.setProperty(.init(rawValue: "links.decoration"), value: .choice("off"))
        #expect(package.manifest.resolvedProperties.filter { $0.controlGroupSource?.type == .linkStyling }.map(\.id) == ["links.colour", "links.decoration"])
        node.setProperty(.init(rawValue: "type.verticalAlignment"), value: .choice("align-middle"))
        let page = Page(title: "Links", slug: "index", parts: [node])
        let browser = BootstrapTokenBrowser()
        try await browser.load(HTMLPageRenderer().render(page: page, theme: .standard))
        let errors = try await browser.web.evaluateJavaScript("""
        (()=>{const a=document.getElementById('styled-link'),errors=[],s=getComputedStyle(a),ref=document.createElement('a');document.body.append(ref);
          ref.style.color='var(--bs-link-color)';
          if(s.color!==getComputedStyle(ref).color) errors.push('link colour');
          if(s.textDecorationLine!=='none') errors.push('decoration');
          if(s.verticalAlign!=='middle') errors.push('vertical align');
          const selectors=[];function scan(rules){for(const r of rules){if(r.selectorText) selectors.push(r.selectorText);if(r.cssRules)scan(r.cssRules)}}
          for(const sheet of document.styleSheets){try{scan(sheet.cssRules)}catch{}}
          for(const cls of a.classList){if(cls.startsWith('hover:')&&!selectors.some(s=>s.includes('.'+CSS.escape(cls)+':hover')))errors.push(cls)}
          ref.remove();return errors;})()
        """) as? [String]
        #expect(errors == [])
    }

    @Test func paragraphHasOnlyNativeControlsAndNoAuthoredCSS() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let definition = PartType.paragraph.definition
        let package = try #require(definition.package)
        try package.preparePayload()
        #expect(package.css.isEmpty)
        #expect(package.instanceJavaScript.isEmpty)
        #expect(definition.allowsChildren == false)
        #expect(package.manifest.resolvedProperties.filter { $0.controlGroupSource?.type == .typography }.map(\.id) == [
            "typography.fontFamily", "typography.textSize", "typography.fontStyle", "typography.fontWeight",
            "typography.textAlignment", "typography.textDecoration",
            "typography.textTransform", "typography.textWrap", "typography.wordWrap",
            "typography.userSelect"
        ])
        let group = PartPackageControlGroup(type: .typography, id: "type")
        #expect(group.properties.count == 13)
        #expect(group.properties.contains { $0.id == "type.truncation" } == false)
        #expect(group.properties.first { $0.id == "type.textWrap" }?.control.options?.contains { $0.value == "text-truncate" } == true)
        #expect(group.properties.filter(\.responsive).map(\.id) == ["type.fontSize", "type.textSize", "type.fontWeight", "type.textAlignment", "type.textWrap"])
        var values: [String: PartPackageValue] = ["type.textAlignment": .string("text-start md:text-center")]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        #expect(values["type.classes"] == .string("text-start md:text-center"))
        #expect(values["type.css"] == nil)
    }

    @Test func themeFontsUseReadableClassesAndKeepSelectionsAfterRename() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        let font = ThemeCustomFont(name: "Brand", font: .system(family: "Georgia", weights: [400]))
        theme.typography.customFonts = [font]
        theme.typography.headingFont = .system(family: "Verdana", weights: [400])
        var paragraph = PartNode.make(.paragraph)
        let key = PartProperty.Key(rawValue: "typography.fontFamily")
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: key, theme: theme) == "")
        let reference = "font-custom-" + font.id.uuidString.lowercased()
        paragraph.setProperty(key, value: .choice(reference))
        #expect(BootstrapCustomTokenClasses.label(for: reference, theme: theme) == "Brand — font-brand")
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: key, theme: theme) == "font-brand")
        #expect(BootstrapEditorCSS.render(theme).contains(".font-brand{font-family:var(--bs-font-brand)}"))
        #expect(BootstrapEditorCSS.render(theme).contains("--bs-font-heading:Verdana"))
        theme.typography.customFonts[0].name = "Editorial"
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: key, theme: theme) == "font-editorial")
        #expect(BootstrapEditorCSS.render(theme).contains("font-brand") == false)
        theme.typography.customFonts.removeAll()
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: key, theme: theme) == "")
        #expect(BootstrapEditorCSS.render(theme).contains("font-editorial") == false)
        paragraph.setProperty(key, value: .choice("font-heading"))
        #expect(BootstrapControlGroupClasses.resolve(node: paragraph, key: key, theme: theme) == "font-heading")
    }

    @Test func customFontNamesAreSafeAndCannotCollideWithNativeUtilities() {
        var theme = Theme.standard
        theme.typography.customFonts = ["Body", "Brand", "Brand!", "Héading", "💛", "123"].map {
            ThemeCustomFont(name: $0, font: .system(family: "Georgia", weights: [400]))
        }
        let names = BootstrapCustomTokenClasses.fontClasses(theme: theme)
        #expect(Set(names.values) == ["font-body-2", "font-brand", "font-brand-2", "font-heading-2", "font-custom", "font-123"])
        theme.typography.customFonts.reverse()
        #expect(BootstrapCustomTokenClasses.fontClasses(theme: theme) == names)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"], [375, 800])
    func paragraphMatchesHandwrittenBootstrap(destination: String, width: Int) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var siteTheme = Theme.standard
        let brand = ThemeCustomFont(name: "Brand", font: .system(family: "Georgia", weights: [400, 700]))
        siteTheme.typography.customFonts = [brand]
        var paragraph = PartNode.make(.paragraph)
        paragraph.setProperty(.init(rawValue: "typography.fontFamily"), value: .choice("font-custom-" + brand.id.uuidString.lowercased()))
        paragraph.anchor = "paragraph-test"
        paragraph.setProperty(.init(rawValue: "content"), value: .string("Text <safe> & editable"))
        paragraph.setProperty(.init(rawValue: "typography.textSize"), value: .choice("text-sm"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.textSize"), value: .choice("text-lg"), at: .medium)
        paragraph.setProperty(.init(rawValue: "typography.fontWeight"), value: .choice("fw-normal"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.fontWeight"), value: .choice("fw-bold"), at: .medium)
        paragraph.setProperty(.init(rawValue: "typography.textAlignment"), value: .choice("text-start"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.textAlignment"), value: .choice("text-center"), at: .medium)
        paragraph.setProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-pretty"))
        paragraph.setResponsiveProperty(.init(rawValue: "typography.textWrap"), value: .choice("text-nowrap"), at: .medium)
        let page = Page(title: "Paragraph", slug: "index", parts: [paragraph])
        let initial = try CanvasScene.render(renderer: HTMLPageRenderer(), page: page, language: "en",
            theme: siteTheme, assets: [:], breakpoint: .medium, packageRevision: 0, previous: nil)
        let html: String
        if destination == "canvas" {
            guard case .page(let document) = initial.result else { Issue.record("Expected canvas document"); return }
            html = document
            #expect(html.contains("data-foundry-inline-property=\"content\""))
        } else {
            var site = Site(name: "Paragraph", pages: [page])
            site.theme = siteTheme
            let bundle = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published)
                .render(site: site)
            #expect(bundle.errors.isEmpty)
            let document = try #require(bundle.file(at: "index.html")?.contents)
            #expect(document.contains("data-foundry-") == false)
            #expect(document.contains("foundry-package-") == false)
            #expect(document.contains("Text &lt;safe&gt; &amp; editable"))
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(.init(source: WebCanvasView.Coordinator.interactionScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 600), configuration: configuration)
        let navigation = ParagraphNavigation()
        defer { web.stopLoading() }
        try await navigation.load(html, in: web)
        let errors = try await web.evaluateJavaScript("""
            (() => {
                const actual=document.getElementById('paragraph-test'), errors=[];
                if(actual.tagName!=='P') errors.push('Not a paragraph');
                if(actual.textContent!=='Text <safe> & editable') errors.push('Text editing value lost');
                const reference=document.createElement('p');
                reference.className='font-brand text-sm md:text-lg fw-normal md:fw-bold text-start md:text-center text-pretty md:text-nowrap';
                reference.textContent=actual.textContent;
                actual.after(reference);
                for(const mode of ['light','dark']) {
                    document.documentElement.dataset.bsTheme=mode;
                    for(const direction of ['ltr','rtl']) {
                        document.documentElement.dir=direction;
                        const a=getComputedStyle(actual), b=getComputedStyle(reference);
                        for(const key of ['display','fontSize','fontWeight','lineHeight','fontFamily','color','textAlign','textWrap','marginTop','marginBottom']) {
                            if(a[key]!==b[key]) errors.push(mode+'/'+direction+'/'+key+': '+a[key]+' != '+b[key]);
                        }
                    }
                }
                reference.remove();
                document.documentElement.dir='ltr';
                return errors;
            })()
            """) as? [String]
        #expect(errors == [])
        let fontFamily = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).fontFamily") as? String
        #expect(fontFamily == "Georgia")
        let alignment = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).textAlign") as? String
        #expect(alignment == (width == 800 ? "center" : "start"))
        let weight = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).fontWeight") as? String
        #expect(weight == (width == 800 ? "700" : "400"))
        let wrapping = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).textWrap") as? String
        #expect(wrapping == (width == 800 ? "nowrap" : "pretty"))
        let size = try await web.evaluateJavaScript("parseFloat(getComputedStyle(document.getElementById('paragraph-test')).fontSize)") as? Double
        #expect((size ?? 0) == (width == 800 ? 20 : 14))
        let lineHeight = try await web.evaluateJavaScript("parseFloat(getComputedStyle(document.getElementById('paragraph-test')).lineHeight)") as? Double
        #expect(lineHeight == (size ?? 0) * 1.5, "Text size includes Bootstrap's paired line height")
        let wrappingErrors = try await web.evaluateJavaScript("""
        (()=>{const errors=[],wide=matchMedia('(min-width:768px)').matches;
          for(const mode of ['wrap','nowrap','balance','pretty']) {
            for(const reverse of [false,true]) {
              const el=document.createElement('p');
              el.className=reverse?`text-${mode} md:text-truncate`:`text-truncate md:text-${mode}`;
              document.body.append(el);const s=getComputedStyle(el),truncated=reverse?wide:!wide;
              if(s.textOverflow!==(truncated?'ellipsis':'clip')||s.overflowX!==(truncated?'hidden':'visible'))errors.push(mode+'/'+reverse+'/overflow');
              if(s.textWrap!==(truncated?'nowrap':mode))errors.push(mode+'/'+reverse+'/wrap');
              el.remove();
            }
          }return errors;})()
        """) as? [String]
        #expect(wrappingErrors == [])

        // Runtime theme edits must preserve responsive precedence, including
        // a custom base size underneath a standard medium size.
        var theme = Theme.standard
        theme.bootstrapTokens.custom["fontSize"] = ["hero"]
        theme.bootstrapTokens.values["font-size-hero"] = "40px"
        theme.bootstrapTokens.values["line-height-hero"] = "1.2"
        theme.bootstrapTokens.values["font-size-lg"] = "30px" // Bootstrap's own sizes are fixed; stray overrides are ignored.
        let overrides = BootstrapThemeCSS.render(theme: theme)
        _ = try await web.callAsyncJavaScript(
            "const style=document.createElement('style');style.textContent=css;document.head.append(style);const p=document.createElement('p');p.id='custom-size';p.className='text-hero md:text-lg fw-normal md:fw-bold';document.body.append(p);",
            arguments: ["css": overrides], in: nil, contentWorld: .page)
        let custom = try await web.evaluateJavaScript("(()=>{const s=getComputedStyle(document.getElementById('custom-size'));return [s.fontSize,s.fontWeight,s.lineHeight]})()") as? [String]
        #expect(custom == (width == 800 ? ["20px", "700", "30px"] : ["40px", "400", "48px"]))

        if destination == "canvas" && width == 800 {
            var edited = page
            let key = PartProperty.Key(rawValue: "typography.textAlignment")
            var previous = initial.scene
            for (revision, value) in ["text-end", "none"].enumerated() {
                if value == "none" {
                    edited.parts[0].removeResponsiveOverride(key, at: .medium)
                } else {
                    edited.parts[0].setResponsiveProperty(key, value: .choice(value), at: .medium)
                }
                let result = try CanvasScene.render(renderer: HTMLPageRenderer(), page: edited, language: "en",
                    theme: siteTheme, assets: [:], breakpoint: .medium, packageRevision: 0, previous: previous,
                    consecutiveImpact: .partProperty(partID: paragraph.id, propertyKey: key))
                guard case .scene(let update) = result.result else { Issue.record("Expected live patch"); return }
                let applied = try await web.callAsyncJavaScript(
                    "return window.foundryApplyScene(html, styles, removed, roots, revision, styleMoves, childMoves)",
                    arguments: ["html": update.html, "styles": update.styles, "removed": update.removed,
                        "roots": update.roots as Any? ?? NSNull(), "revision": revision + 1,
                        "styleMoves": update.styleMoves, "childMoves": update.childMoves],
                    in: nil, contentWorld: .defaultClient)
                try #require(applied as? Bool == true)
                #expect(try await web.evaluateJavaScript("getComputedStyle(document.getElementById('paragraph-test')).textAlign") as? String == (value == "none" ? "start" : "end"))
                previous = result.scene
            }
        }
    }
}

@MainActor
private final class ParagraphNavigation: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String, in web: WKWebView) async throws {
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
