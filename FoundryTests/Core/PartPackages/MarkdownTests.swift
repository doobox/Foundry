import Foundation
import Testing
import WebKit
@testable import Foundry

struct MarkdownTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.canvas, .preview, .published])
    func proseUsesBundledBootstrap(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.init(rawValue: "foundry.content.markdown"))
        part.anchor = "markdown-probe"
        part.setProperty(.init(rawValue: "content"), value: .string("# Heading\n\nA paragraph.\n\n- List item"))
        let page = Page(title: "Markdown", slug: "index", parts: [part])
        var html: String
        if environment == .canvas {
            html = HTMLPageRenderer().render(page: page, theme: .standard)
        } else {
            let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Markdown", pages: [page]))
            #expect(bundle.errors.isEmpty)
            html = try #require(bundle.file(at: "index.html")?.contents)
            #expect(html.contains("data-foundry-") == false)
        }
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: app.appending(path: "Foundry/Resources/BuiltInLibraries.bundle/Contents/Resources/bootstrap-6.0.0-alpha.1.min.css"), encoding: .utf8)
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [], root = document.getElementById('markdown-probe');
          if (!root || !root.classList.contains('prose')) return ['missing prose'];
          for (const mode of ['light', 'dark']) {
            document.documentElement.setAttribute('data-bs-theme', mode);
            const style = getComputedStyle(root);
            if (style.display !== 'flex' || style.flexDirection !== 'column') errors.push(mode + ': prose layout');
            if (!root.querySelector('h1') || !root.querySelector('ul > li')) errors.push(mode + ': content');
          }
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }

    @Test func rendersLongFormContent() {
        let html = FoundryMarkdown.html(from: """
        # A **heading**

        A [link](https://example.com "Title") and ![Alt text](image.png).

        > A quote

        - One
        - Two

        | Name | Value |
        | --- | --- |
        | A | B |

        ~~Removed~~
        """)
        for expected in ["<h1>A <strong>heading</strong></h1>", "<blockquote>", "<ul>",
                         "<table>", "<th>Name</th>", "<td>A</td>", "<del>Removed</del>",
                         "alt=\"Alt text\"", "title=\"Title\""] {
            #expect(html.contains(expected), "\(expected)\n\(html)")
        }
    }

    @Test func preservesCodeAndRejectsExecutableMarkup() {
        let html = FoundryMarkdown.html(from: """
        `<script>&`

        ```html
        <script>alert(1)</script>
        ```

        [unsafe](javascript:alert%281%29)

        <script>alert(1)</script>
        """)
        #expect(html.contains("<code>&lt;script&gt;&amp;</code>"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(html.contains("<script>") == false)
        #expect(html.contains("href=\"javascript:") == false)
    }
    @Test func fencedCodeHasSafeThemedControls() {

        let html = FoundryMarkdown.html(from: """
        ```swift
        print("<hello>")
        ```
        """)
        #expect(html.contains("class=\"fd-markdown-code\" data-language=\"swift\""))
        #expect(html.contains("class=\"fd-markdown-code-language\">swift</span>"))
        #expect(html.contains("type=\"button\" aria-label=\"Copy code\""))
        #expect(html.contains("<code class=\"language-swift\">print(&quot;&lt;hello&gt;&quot;)"))
        #expect(html.contains("<script>") == false)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [PartTemplateEnvironment.preview, .published])
    func codeAssetsAreConditional(environment: PartTemplateEnvironment) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.init(rawValue: "foundry.content.markdown"))
        part.setProperty(.init(rawValue: "content"), value: .string("```swift\nprint(1)\n```"))
        let page = Page(title: "Code", slug: "index", parts: [part])
        let bundle = StaticSiteRenderer(environment: environment).render(site: Site(name: "Code", pages: [page]))
        #expect(bundle.errors.isEmpty)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        #expect(html.contains("files/libraries/foundry/foundry-markdown-code.css"))
        #expect(html.contains("highlight-11.12.0.min.js") == false)
        #expect(html.contains("files/libraries/foundry/foundry-markdown-code.js"))
        for path in [FoundryWebLibraryRegistry.markdownCodeStylesheetPath,
                     FoundryWebLibraryRegistry.markdownCodeScriptPath] {
            #expect(bundle.file(at: path) != nil)
        }

        part.setProperty(.init(rawValue: "content"), value: .string("No code block."))
        let plain = StaticSiteRenderer(environment: environment).render(site: Site(name: "Plain", pages: [
            Page(title: "Plain", slug: "index", parts: [part])
        ]))
        #expect(plain.errors.isEmpty)
        #expect(bundle.file(at: "files/libraries/foundry/highlight-11.12.0.min.js") == nil)
        #expect(plain.file(at: "index.html")?.contents.contains("foundry-markdown-code.js") == false)
    }
    @Test func onDemandPreviewPlansCodeAssetsBeforeRenderingPages() throws {
        let site = Site(name: "Blank", pages: [Page(title: "Blank", slug: "index")])
        var files: [SiteExportFile] = []
        try StaticSiteRenderer(environment: .preview).generate(
            site: site, assets: [:], pageIDs: []
        ) { files.append($0) }
        #expect(files.contains { $0.path == FoundryWebLibraryRegistry.markdownCodeStylesheetPath })
        #expect(files.contains { $0.path == FoundryWebLibraryRegistry.markdownCodeScriptPath })
    }


    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func codeBoxInheritsPageThemeAndNestedAppearance() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var part = PartNode.make(.init(rawValue: "foundry.content.markdown"))
        part.setProperty(.init(rawValue: "content"), value: .string("```swift\nlet answer = 42\n```"))
        let page = Page(title: "Code", slug: "index", parts: [part], themeOverride: "theme-primary")
        let html = HTMLPageRenderer().render(page: page, theme: .standard)
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.evaluateJavaScript("""
        (() => {
          const errors = [];
          const body = document.body;
          const block = document.querySelector(".fd-markdown-code");
          if (!block || !body.classList.contains("theme-primary")) return ["missing themed block: " + body.className + " / " + Boolean(block)];
          body.setAttribute("data-bs-theme", "light");
          const light = getComputedStyle(block).backgroundColor;
          body.setAttribute("data-bs-theme", "dark");
          const dark = getComputedStyle(block).backgroundColor;
          block.setAttribute("data-bs-theme", "light");
          const nestedLight = getComputedStyle(block).backgroundColor;
          if (light === "rgba(0, 0, 0, 0)" || light === "transparent") errors.push("transparent");
          if (light === dark) errors.push("appearance did not change");
          if (nestedLight !== light) errors.push("nested appearance did not override");
          block.removeAttribute("data-bs-theme");
          body.classList.remove("theme-primary");
          if (getComputedStyle(block).backgroundColor === dark) errors.push("theme did not change");
          return errors;
        })()
        """) as? [String]
        #expect(errors == [])
    }
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func copyWorksInBrowser() async throws {
        let behavior = try #require(FoundryWebLibraryRegistry.resourceData(at: "FOUNDRY-MARKDOWN-CODE.js"))
        let source = "```swift\nlet answer = 42\n```"
        let html = """
        <!doctype html><html><body>
        \(FoundryMarkdown.html(from: source))
        <script>\(String(decoding: behavior, as: UTF8.self))</script>
        </body></html>
        """
        let browser = BootstrapTokenBrowser()
        try await browser.load(html)
        let errors = try await browser.web.callAsyncJavaScript("""
        const errors = [];
        const code = document.querySelector(".fd-markdown-code code");
        const button = document.querySelector(".fd-markdown-code-copy");
        Object.defineProperty(navigator, "clipboard", {
          configurable: true,
          value: { writeText: async (value) => { window.copiedCode = value; } }
        });
        button.click();
        await new Promise(resolve => setTimeout(resolve, 0));
        if (window.copiedCode !== "let answer = 42\\n") errors.push("wrong clipboard contents");
        if (button.textContent !== "Copied") errors.push("no copy feedback");
        return errors;
        """, arguments: [:], in: nil, contentWorld: .page) as? [String]
        #expect(errors == [])
    }

    @Test func macroSupportsDefaultsSavedSourceAndCanvasEditing() {
        let template = ##"<div class="prose">{{ markdown("body", default: "# Default") }}</div>"##
        let primitives = PartTemplateRenderer.textPrimitives(in: template)
        #expect(primitives.first?.defaultValue == "# Default")
        #expect(PartTemplateRenderer.isMarkdownPrimitive("body", in: template))
        let context = PartTemplateContext(instanceID: UUID(), packageIdentifier: "test.markdown",
            properties: ["body": .string("# Saved\n\n`{{ control.secret }}`")], slots: [:], enablesEditorMarkup: true)
        let html = PartTemplateRenderer.render(template, context: context)
        #expect(html.contains("<h1>Saved</h1>"))
        #expect(html.contains("{{ control.secret }}"))
        #expect(html.contains("data-foundry-inline-source="))
        let published = PartTemplateRenderer.render(template, context: .init(
            instanceID: UUID(), packageIdentifier: "test.markdown", properties: [:], slots: [:]))
        #expect(published.contains("<h1>Default</h1>"))
        #expect(published.contains("data-foundry") == false)
    }

    @Test func repeatedMarkdownKeepsIndependentSources() {
        let template = #"{{ loop 2 }}<div>{{ markdown("body", default: "Default") }}</div>{{ endloop }}"#
        let html = PartTemplateRenderer.render(template, context: .init(instanceID: UUID(),
            packageIdentifier: "test.markdown", properties: ["body": .array([.string("**One**"), .string("*Two*")])],
            slots: [:], enablesEditorMarkup: true))
        #expect(html.contains("<strong>One</strong>"))
        #expect(html.contains("<em>Two</em>"))
        #expect(html.contains("data-foundry-property-path=\"1\""))
    }

    @Test func builtInPartValidatesAndDefaultsToProse() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: app.appending(
            path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Markdown"))
        let definition = PartPackageAdapter.definition(from: package)
        #expect(definition.properties.contains { $0.key.rawValue == "content" })
        let style = try #require(definition.properties.first { $0.key.rawValue == "prose.style" })
        #expect(style.defaultValue == .choice("prose"))
        #expect(package.preparedPrimitives.text.count == 1)
    }
}
