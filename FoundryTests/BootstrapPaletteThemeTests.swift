import Testing
import WebKit
@testable import Foundry

@MainActor
struct BootstrapPaletteThemeTests {
    @Test(arguments: [
        ("#000000", "white"), ("#FFFFFF", "black"),
        ("#757575", "white"), ("#767676", "white"), ("#777777", "black"),
        ("#7740FF", "white"), ("#FFC900", "black"), ("#0087FE", "black")
    ])
    func contrastUsesBootstrapCandidateOrder(sample: (String, String)) throws {
        let palette = try ColourPalette(id: "custom.contrast", name: "Contrast", origin: .custom,
            shades: Array(repeating: sample.0, count: 13), lightDefaultShade: .seven, darkDefaultShade: .seven)
        let tokens = Dictionary(uniqueKeysWithValues: BootstrapPaletteTheme.properties(for: palette))
        #expect(tokens["--bs-theme-contrast"] == "var(--bs-\(sample.1))")
        // #767676 is deliberate: both candidates pass, black has the higher
        // ratio, but Bootstrap returns white because it is tested first.
    }

    @Test
    func everyPaletteHasStableCompleteTheme() throws {
        var framework = Framework.standard
        var custom = try BootstrapColourCatalogue.palette(role: .accent).duplicated()
        custom.name = "Primary" // Display-name collisions must not replace native themes.
        framework.colourPalettes.insert(custom, at: 0)
        let css = BootstrapPaletteTheme.css(framework: framework)
        let classes = framework.colourPalettes.map(BootstrapPaletteTheme.className)
        #expect(Set(classes).count == classes.count)
        for palette in framework.colourPalettes {
            let resolved = BootstrapPaletteTheme.resolve(palette.id, framework: framework)
            #expect(resolved == BootstrapPaletteTheme.className(for: palette))
            if BootstrapPaletteTheme.nativeRole(palette) == nil {
                #expect(css.contains(".\(resolved){"))
                #expect(BootstrapPaletteTheme.properties(for: palette).count == 9)
            }
        }
        let original = BootstrapPaletteTheme.className(for: custom)
        custom.name = "Renamed </style>"
        #expect(BootstrapPaletteTheme.className(for: custom) == original)
        #expect(css.contains("Renamed") == false)
        #expect(BootstrapPaletteTheme.resolve("deleted", framework: framework) == "theme-reset")
        #expect(BootstrapPaletteTheme.resolve("theme-danger", framework: framework) == "theme-danger")
        let roundTrip = try JSONDecoder().decode(ColourPalette.self, from: JSONEncoder().encode(custom))
        #expect(BootstrapPaletteTheme.className(for: roundTrip) == original)
        try custom.setBootstrapScale(try #require(BootstrapColourScale.native("pink")),
                                     previews: try #require(BootstrapColourCatalogue.previews.palettes["pink"]))
        framework.colourPalettes[0] = custom
        #expect(BootstrapPaletteTheme.className(for: custom) == original)
        #expect(BootstrapPaletteTheme.css(framework: framework) != css)
        let black = try #require(framework.colourPalettes.first { $0.id == "standard.black" })
        let white = try #require(framework.colourPalettes.first { $0.id == "standard.white" })
        #expect(Dictionary(uniqueKeysWithValues: BootstrapPaletteTheme.properties(for: black))["--bs-theme-contrast"] == "var(--bs-white)")
        #expect(Dictionary(uniqueKeysWithValues: BootstrapPaletteTheme.properties(for: white))["--bs-theme-contrast"] == "var(--bs-black)")
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "export"])
    func customThemeReachesButtonAndBrowser(destination: String) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var framework = Framework.standard
        let custom = try BootstrapColourCatalogue.palette(role: .accent).duplicated()
        let primaryIndex = try #require(framework.colourPalettes.firstIndex { $0.id == "framework.primary" })
        framework.colourPalettes[primaryIndex] = BootstrapColourCatalogue.palette(role: .primary, hue: "indigo")
        framework.colourPalettes.insert(custom, at: 0)
        var button = PartNode.make(.button)
        button.setProperty(.init(rawValue: "theme"), value: .choice(custom.id))
        let page = Page(title: "Theme", slug: "index", parts: [button])
        var site = Site(name: "Theme", pages: [page])
        site.framework = framework
        site.appearanceMode = .both
        var replacement = site
        replacement.replacePartFrameworkReference(custom.id, with: "framework.danger")
        #expect(replacement.pages[0].parts[0].property(.init(rawValue: "theme")) == "framework.danger")
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, framework: framework)
        } else {
            let bundle = StaticSiteRenderer().render(site: site)
            let document = try #require(bundle.file(at: "index.html"))
            let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = document.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
            #expect(document.contents.contains("data-foundry-") == false)
        }
        #expect(html.contains("btn btn-solid " + BootstrapPaletteTheme.className(for: custom)))
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
                    // Primary is remapped to Indigo; only automatic contrast may differ.
                    reference.style.setProperty('--bs-theme-contrast',getComputedStyle(actual).getPropertyValue('--bs-theme-contrast'));
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
