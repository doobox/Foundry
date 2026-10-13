import Foundation
import Testing
import WebKit
@testable import Foundry

struct HeadingTests {
    private var app: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func packageValidatesAndDefaultsToH2() throws {
        let package = try PartPackageLoader.load(from: app.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Heading"))
        let definition = PartPackageAdapter.definition(from: package)
        let level = try #require(definition.properties.first { $0.key.rawValue == "level" })
        #expect(level.defaultValue == .choice("h2"))
        #expect(definition.properties.contains { $0.key.rawValue == "typography.fontSize" })
        #expect(package.preparedPrimitives.text.count == 1)
        #expect(package.css.isEmpty)
        #expect(package.instanceJavaScript.isEmpty)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func semanticHeadingsAndIndependentSizes(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var parts: [PartNode] = []
        for level in 1...6 {
            var part = PartNode.make(.init(rawValue: "foundry.content.heading"))
            part.anchor = "heading-\(level)"
            part.setProperty(.init(rawValue: "level"), value: .choice("h\(level)"))
            parts.append(part)
        }
        var resized = PartNode.make(.init(rawValue: "foundry.content.heading"))
        resized.anchor = "resized"
        resized.setProperty(.init(rawValue: "typography.fontSize"), value: .choice("fs-6xl"))
        parts.append(resized)
        let page = Page(title: "Headings", slug: "index", parts: parts)
        var html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Headings", pages: [page]))
            #expect(bundle.errors.isEmpty)
            html = try #require(bundle.file(at: "index.html")?.contents)
            #expect(html.contains("data-foundry-") == false)
        }
        let css = try String(contentsOf: app.appending(path:
            "Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/bootstrap-6.0.0-alpha.1.min.css"), encoding: .utf8)
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [];
          for (const mode of ['light', 'dark']) {
            document.documentElement.setAttribute('data-bs-theme', mode);
            for (let level = 1; level <= 6; level++) {
              const heading = document.getElementById('heading-' + level);
              if (!heading || heading.tagName !== 'H' + level) { errors.push('heading level ' + level); continue; }
              if (heading.textContent.trim() !== 'Heading') errors.push('default text');
              const reference = document.createElement('h' + level);
              reference.textContent = 'Reference';
              document.body.append(reference);
              if (getComputedStyle(heading).fontSize !== getComputedStyle(reference).fontSize) errors.push(mode + ': native size ' + level);
              reference.remove();
            }
            const resized = document.getElementById('resized');
            if (resized?.tagName !== 'H2' || !resized.classList.contains('fs-6xl')) errors.push('independent visual size');
            if (parseFloat(getComputedStyle(resized).fontSize) <= parseFloat(getComputedStyle(document.getElementById('heading-2')).fontSize)) errors.push('size override');
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }
}
