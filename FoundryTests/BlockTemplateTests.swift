import Foundation
import Testing
@testable import Foundry

struct BlockTemplateTests {
    @Test
    func cssSelectorsDistinguishPackageFromInstance() {
        let instanceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let css = ":host { display: block; } :instance { color: red; }"

        let rendered = BlockTemplateRenderer.scopedCSS(
            css,
            packageIdentifier: "com.example.card",
            instanceID: instanceID
        )

        #expect(rendered.contains(":is([data-foundry-package=\"com.example.card\"], .foundry-package-com-example-card)"))
        #expect(rendered.contains("[data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(!rendered.contains(":host"))
        #expect(!rendered.contains(":instance"))
    }

    @Test
    func namedDropZoneAndChildAreaRenderTheirOwnContent() {
        let context = BlockTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.container",
            properties: [:],
            slots: ["content": "<strong>Child</strong>"],
            dropZones: ["content": "<p>Child</p>"]
        )

        #expect(BlockTemplateRenderer.render("{{ dropZone(\"content\") }}", context: context) == "<p>Child</p>")
        #expect(BlockTemplateRenderer.render("{{ childArea(\"content\") }}", context: context) == "<strong>Child</strong>")
        #expect(BlockTemplateRenderer.render("{{ dropzone(\"content\") }}", context: context).isEmpty)
    }

    @Test
    func namedEditableMacrosKeepValuesWhenTheirTemplateOrderChanges() {
        let context = BlockTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.article",
            properties: [
                "heading": .string("Saved heading"),
                "body": .string("Saved body")
            ],
            slots: [:]
        )
        let original = #"<h2>{{ text("heading") }}</h2><p>{{ text("body") }}</p>"#
        let reordered = #"<p>{{ text("body") }}</p><h2>{{ text("heading") }}</h2>"#

        #expect(BlockTemplateRenderer.render(original, context: context) == "<h2>Saved heading</h2><p>Saved body</p>")
        #expect(BlockTemplateRenderer.render(reordered, context: context) == "<p>Saved body</p><h2>Saved heading</h2>")
    }

    @Test
    func editableMacroDefaultsSupportEscapedStringCharacters() throws {
        let template = #"<p>{{ text("caption", default: "Say \"hello\"") }}</p>"#
        let primitive = try #require(BlockTemplateRenderer.textPrimitives(in: template).first)

        #expect(primitive.key == "caption")
        #expect(primitive.defaultValue == #"Say "hello""#)
    }

    @Test
    func developerExpressionsResolveInstanceControlsAndReadableColorFilters() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let context = BlockTemplateContext(
            instanceID: id,
            packageIdentifier: "com.example.card",
            properties: ["accent": .string("#336699"), "padding": .number(24)],
            slots: [:]
        )
        let template = """
        /* {{ instance.id }} */
        [data-foundry-id="{{ instance.id }}"] {
          padding: {{ control.padding }}px;
          color: {{ control.accent }};
          border-color: {{ control.accent | lighten(20) }};
          background-color: {{ control.accent | darken(25) }};
        }
        """

        let rendered = BlockTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("[data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(rendered.contains("/* AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE */"))
        #expect(rendered.contains("padding: 24px"))
        #expect(rendered.contains("color: #336699"))
        #expect(rendered.contains("border-color: #5C85AD"))
        #expect(rendered.contains("background-color: #264D73"))
    }

    @Test
    func rendersEscapedPropertiesConditionsSlotsAssetsAndEditorHooks() {
        let context = BlockTemplateContext(
            instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            packageIdentifier: "com.example.card",
            properties: [
                "title": .string("<A & B>"),
                "visible": .boolean(true),
                "alignment": .string("center")
            ],
            slots: ["content": "<strong>Child</strong>"],
            blockClass: "c-instance",
            blockAttributes: "data-editor=\"true\"",
            assetBasePath: "assets/blocks/com.example.card"
        )
        let template = """
        <article class="card {{ block.class }}" {{ block.attributes }}>
          <h2>{{ control.title }}</h2>
          {{ if control.visible }}<span>Shown</span>{{ else }}<span>Hidden</span>{{ endif }}
          {{ if control.alignment == "center" }}<b>Centered</b>{{ endif }}
          <img src="{{ asset("images/icon.svg") }}">
          {{ childArea("content") }}
        </article>
        """

        let html = BlockTemplateRenderer.render(template, context: context)

        #expect(html.contains("class=\"card c-instance\""))
        #expect(html.contains("data-editor=\"true\""))
        #expect(html.contains("&lt;A &amp; B&gt;"))
        #expect(html.contains("<span>Shown</span>"))
        #expect(!html.contains("Hidden"))
        #expect(html.contains("<b>Centered</b>"))
        #expect(html.contains("assets/blocks/com.example.card/images/icon.svg"))
        #expect(html.contains("<strong>Child</strong>"))
    }

    @Test
    func rendersMutuallyExclusiveEnvironmentAndElseIfConditions() {
        let properties: [String: BlockPackageValue] = ["variant": .string("compact")]
        let template = """
        {{ if control.variant == "wide" }}Wide
        {{ elseif control.variant == "compact" }}Compact
        {{ elseif canvas }}Canvas
        {{ else }}Published{{ endif }}
        """
        let canvasContext = BlockTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: properties, slots: [:], environment: .canvas
        )
        let publishedContext = BlockTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:]
        )
        let previewContext = BlockTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:], environment: .preview
        )

        #expect(BlockTemplateRenderer.render(template, context: canvasContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Compact")
        #expect(BlockTemplateRenderer.render(template, context: publishedContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Published")
        #expect(BlockTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: canvasContext) == "Canvas")
        #expect(BlockTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: publishedContext) == "Published")
        let environmentTemplate = "{{ if canvas }}Canvas{{ elseif preview }}Preview{{ elseif published }}Published{{ endif }}"
        #expect(BlockTemplateRenderer.render(environmentTemplate, context: canvasContext) == "Canvas")
        #expect(BlockTemplateRenderer.render(environmentTemplate, context: previewContext) == "Preview")
        #expect(BlockTemplateRenderer.render(environmentTemplate, context: publishedContext) == "Published")
    }

    @Test
    func supportsArithmeticComparisonLogicAndFunctions() {
        let context = BlockTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.expressions",
            properties: [
                "text": .string("xxxx"),
                "number": .number(42),
                "otherNumber": .number(10),
                "disabled": .boolean(false),
                "values": .array([.number(3), .number(7)])
            ],
            slots: [:]
        )

        #expect(BlockTemplateRenderer.render("{{ control.otherNumber + 2 * 3 }}", context: context) == "16")
        #expect(BlockTemplateRenderer.render("{{ (control.otherNumber + 2) * 3 }}", context: context) == "36")
        #expect(BlockTemplateRenderer.render("{{ clamp(control.number, 0, 32) }}", context: context) == "32")
        #expect(BlockTemplateRenderer.render("{{ max(control.values[0], control.values[1]) }}", context: context) == "7")

        let condition = #"{{ if control.text == "xxxx" && control.number == control.otherNumber + 32 && !control.disabled }}Matched{{ else }}Missed{{ endif }}"#
        #expect(BlockTemplateRenderer.render(condition, context: context) == "Matched")
        #expect(BlockTemplateRenderer.render("{{ if control.number < 10 || control.number >= 42 }}Matched{{ endif }}", context: context) == "Matched")
    }

    @Test
    func rendersSitePageAndScopedAssetPaths() {
        let context = BlockTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.paths",
            properties: [:],
            slots: [:],
            assetPaths: [
                "images/badge.svg": "files/badge.svg",
                "shared/icons": "../assets/shared/icons"
            ],
            siteBaseURL: "https://example.com",
            pageURL: "https://example.com/about/",
            siteRootPath: "..",
            siteAssetsPath: "../assets"
        )

        let rendered = BlockTemplateRenderer.render(
            "{{ site.baseURL }}|{{ page.url }}|{{ path.siteRoot }}|{{ path.siteAssets }}|{{ asset(\"images/badge.svg\") }}|{{ asset(\"shared/icons/star.svg\") }}",
            context: context
        )

        #expect(rendered == "https://example.com|https://example.com/about/|..|../assets|files/badge.svg|../assets/shared/icons/star.svg")
    }
}
