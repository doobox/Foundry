import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapPaletteThemeTests {
    @Test func onlySemanticThemesAreAvailable() throws {
        var theme = Theme.standard
        let custom = try BootstrapColourCatalogue.palette(role: .accent).duplicated()
        theme.colourPalettes.insert(custom, at: 0)
        let palettes = BootstrapPaletteTheme.selectablePalettes(in: theme)
        #expect(palettes.count == 8)
        for palette in palettes {
            #expect(BootstrapPaletteTheme.resolve(palette.id, theme: theme) == "theme-" + (BootstrapPaletteTheme.nativeRole(palette) ?? ""))
        }
        for excluded in [custom.id, "standard.pink", "framework.background", "missing"] {
            #expect(BootstrapPaletteTheme.resolve(excluded, theme: theme) == "theme-reset")
        }
        #expect(BootstrapPaletteTheme.resolve("theme-danger", theme: theme) == "theme-danger")
        let css = BootstrapColorCSS.export(theme: theme, mode: .both)
        #expect(css.contains("theme-palette-") == false)
        #expect(css.contains(".theme-pink") == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "export"])
    func editedThemeReachesButtonAndBrowser(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var theme = Theme.standard
        let primaryIndex = try #require(theme.colourPalettes.firstIndex { $0.id == "framework.primary" })
        theme.colourPalettes[primaryIndex] = BootstrapColourCatalogue.palette(role: .primary, hue: "indigo")
        theme.colourPalettes[primaryIndex].bootstrapTokens["primary-bg"] = BootstrapTokenColour(
            light: BootstrapColourScale(base: "oklch(50% 0.15 350)"), dark: BootstrapColourScale(base: "oklch(40% 0.15 350)"))
        theme.colourPalettes[primaryIndex].bootstrapTokens["primary-contrast"] = BootstrapTokenColour(
            light: BootstrapColourScale.native("white"), dark: BootstrapColourScale.native("white"))
        var button = PartNode.make(.button)
        button.setProperty(.init(rawValue: "theme"), value: .choice("framework.primary"))
        let page = Page(title: "Theme", slug: "index", parts: [button])
        var site = Site(name: "Theme", pages: [page])
        site.theme = theme
        site.appearanceMode = .both
        var replacement = site
        replacement.replacePartThemeReference("framework.primary", with: "framework.danger")
        #expect(replacement.pages[0].parts[0].property(.init(rawValue: "theme")) == "framework.danger")
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, theme: theme)
        } else {
            let bundle = StaticSiteRenderer().render(site: site)
            let document = try #require(bundle.file(at: "index.html"))
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
            #expect(document.contents.contains("data-foundry-") == false)
        }
        #expect(html.contains("btn btn-solid theme-primary"))
        let browser = PaletteThemeTestBrowser()
        try await browser.load(html)
        let errors = try #require(try await browser.view.evaluateJavaScript("""
            const actual = document.querySelector('a.btn');
            const reference = document.createElement('a'); reference.href='#';
            reference.textContent='Reference'; document.body.append(reference);
            const style = document.createElement('style');
            style.textContent = '.btn {transition:none!important;animation:none!important}';document.head.append(style);
            const theme = actual.className.split(' ').find(c=>c.startsWith('theme-'));
            const errors=[];
            for (const mode of ['light','dark']) {
                document.documentElement.setAttribute('data-bs-theme',mode);
                for (const variant of ['solid','outline','subtle']) {
                    actual.className=`btn btn-${variant} ${theme}`;
                    reference.className=`btn btn-${variant} theme-primary`;
                    reference.style.setProperty('--bs-theme-bg', mode === 'light' ? 'oklch(50% 0.15 350)' : 'oklch(40% 0.15 350)');
                    reference.style.setProperty('--bs-theme-contrast','oklch(100% 0 0)');
                    for (const state of ['', 'active','disabled']) {
                        if(state){actual.classList.add(state);reference.classList.add(state)}
                        const a=getComputedStyle(actual), b=getComputedStyle(reference);
                        for(const key of ['color','backgroundColor','borderTopColor','boxShadow','opacity']) {
                            if(a[key]!==b[key]) errors.push(`${mode}/${variant}/${state}/${key}: ${a[key]} != ${b[key]}`);
                        }
                        if(state){actual.classList.remove(state);reference.classList.remove(state)}
                    }
                    actual.focus(); reference.focus();
                    if(getComputedStyle(actual).getPropertyValue('--bs-theme-focus-ring').trim()==='') errors.push('Missing focus token');
                }
            }
            errors;
            """) as? [String])
        #expect(errors.isEmpty, "\(errors)")
    }
}

@MainActor
private final class PaletteThemeTestBrowser: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    private var continuation: CheckedContinuation<Void, any Error>?
    func load(_ html: String) async throws {
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation {
            continuation = $0
            view.loadHTMLString(html, baseURL: nil)
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
