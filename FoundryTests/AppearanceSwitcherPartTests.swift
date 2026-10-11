import Testing
import WebKit
@testable import Foundry

@MainActor
struct AppearanceSwitcherPartTests {
    @Test(.timeLimit(.minutes(1)))
    func builtInSwitcherRendersAndSynchronizes() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let package = try #require(PartType.appearanceSwitcher.definition.package)
        try package.preparePayload()
        var first = PartNode.make(.appearanceSwitcher)
        first.setProperty(.init(rawValue: "defaultAppearance"), value: .choice("dark"))
        let page = Page(title: "Modes", slug: "index", parts: [first, PartNode.make(.appearanceSwitcher)])
        var site = Site(name: "Modes", pages: [page])
        site.appearanceMode = .both
        let bundle = StaticSiteRenderer().render(site: site)
        #expect(bundle.errors.isEmpty)
        var html = try #require(bundle.file(at: "index.html")?.contents)
        #expect(html.contains("let current = 'dark'"))
        #expect(html.contains("data-appearance-switcher"))
        #expect(html.contains("{{") == false)
        let css = bundle.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
        let js = try #require(bundle.file(at: "files/page.js")?.contents)
        let bootstrap = try #require(bundle.files.first { $0.path.hasSuffix("bootstrap-6.0.0-alpha.1.bundle.min.js") }?.contents)
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        html = html.replacingOccurrences(of: "</body>", with: "<script type=\"module\">\(bootstrap)</script><script>\(js)</script></body>")
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [], roots = [...document.querySelectorAll('[data-appearance-switcher]')];
          if (roots.length !== 2) errors.push('missing switchers');
          if (window.foundryAppearance.get() !== 'dark') errors.push('default not applied');
          for (const mode of ['light', 'dark', 'system']) {
            roots[0].querySelector(`[data-mode="${mode}"]`).click();
            if ((document.documentElement.dataset.bsTheme || 'system') !== mode) errors.push('mode not applied');
            for (const root of roots) {
              if (root.querySelector('.menu-item.active')?.dataset.mode !== mode) errors.push('selection not synced');
              if (root.querySelector('[data-current-icon]').className !== 'bi bi-' + ({light:'sun-fill',dark:'moon-stars-fill',system:'circle-half'})[mode]) errors.push('icon not synced');
            }
          }
          roots[0].querySelector('[data-bs-toggle]').click();
          if (roots[0].querySelector('[data-bs-toggle]').getAttribute('aria-expanded') !== 'true') errors.push('menu did not open');
          const reference = document.createElement('div');
          reference.className = 'btn-group';
          reference.innerHTML = '<button class="btn btn-text">Reference</button>';
          document.body.append(reference);
          for (const mode of ['light', 'dark']) {
            window.foundryAppearance.set(mode);
            const actual = getComputedStyle(roots[0].querySelector('button'));
            const expected = getComputedStyle(reference.firstElementChild);
            for (const property of ['display', 'padding', 'borderRadius', 'fontSize']) {
              if (actual[property] !== expected[property]) errors.push('button styling differs: ' + property);
            }
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }

    @Test func savedChoiceWinsAndDefaultsAreNotPersisted() async throws {
        let bootstrap = SiteAppearanceMode.both.bootstrap(siteID: UUID(), defaultMode: "light")
        let browser = BootstrapTokenBrowser()
        try await browser.load("""
        <script>
        window.savedMode = 'system'; window.writes = 0;
        Object.defineProperty(window, 'localStorage', {value: {
          getItem: () => window.savedMode,
          setItem: (_, value) => { window.savedMode = value; window.writes++; }
        }});
        </script>\(bootstrap)
        """)
        #expect(try await browser.web.evaluateJavaScript("window.foundryAppearance.get()") as? String == "system")
        #expect(try await browser.web.evaluateJavaScript("window.writes") as? Int == 0)
        _ = try await browser.web.evaluateJavaScript("window.foundryAppearance.set('dark')")
        #expect(try await browser.web.evaluateJavaScript("window.savedMode") as? String == "dark")
        #expect(SiteAppearanceMode.light.bootstrap(siteID: UUID()).isEmpty)
    }
}
