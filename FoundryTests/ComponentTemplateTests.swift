import Foundation
import Testing
@testable import Foundry

struct ComponentTemplateTests {
    @Test
    func cssSelectorsDistinguishPackageFromInstance() {
        let instanceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let css = ":host { display: block; } :instance { color: red; }"

        let rendered = ComponentTemplateRenderer.scopedCSS(
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
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.container",
            properties: [:],
            slots: ["content": "<strong>Child</strong>"],
            dropZones: ["content": "<p>Child</p>"]
        )

        #expect(ComponentTemplateRenderer.render("{{ dropZone(\"content\") }}", context: context) == "<p>Child</p>")
        #expect(ComponentTemplateRenderer.render("{{ childArea(\"content\") }}", context: context) == "<strong>Child</strong>")
        #expect(ComponentTemplateRenderer.render("{{ dropzone(\"content\") }}", context: context).isEmpty)
    }

    @Test
    func namedEditableMacrosKeepValuesWhenTheirTemplateOrderChanges() {
        let context = ComponentTemplateContext(
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

        #expect(ComponentTemplateRenderer.render(original, context: context) == "<h2>Saved heading</h2><p>Saved body</p>")
        #expect(ComponentTemplateRenderer.render(reordered, context: context) == "<p>Saved body</p><h2>Saved heading</h2>")
    }

    @Test
    func editableMacroDefaultsSupportEscapedStringCharacters() throws {
        let template = #"<p>{{ text("caption", default: "Say \"hello\"") }}</p>"#
        let primitive = try #require(ComponentTemplateRenderer.textPrimitives(in: template).first)

        #expect(primitive.key == "caption")
        #expect(primitive.defaultValue == #"Say "hello""#)
    }

    @Test
    func developerExpressionsResolveInstanceControlsAndReadableColorFilters() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let context = ComponentTemplateContext(
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

        let rendered = ComponentTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("[data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(rendered.contains("/* AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE */"))
        #expect(rendered.contains("padding: 24px"))
        #expect(rendered.contains("color: #336699"))
        #expect(rendered.contains("border-color: #5C85AD"))
        #expect(rendered.contains("background-color: #264D73"))
    }

    @Test
    func rendersEscapedPropertiesConditionsSlotsAssetsAndEditorHooks() {
        let context = ComponentTemplateContext(
            instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            packageIdentifier: "com.example.card",
            properties: [
                "title": .string("<A & B>"),
                "visible": .boolean(true),
                "alignment": .string("center")
            ],
            slots: ["content": "<strong>Child</strong>"],
            componentClass: "c-instance",
            componentAttributes: "data-editor=\"true\"",
            assetBasePath: "assets/components/com.example.card"
        )
        let template = """
        <article class="card {{ component.class }}" {{ component.attributes }}>
          <h2>{{ control.title }}</h2>
          {{ if control.visible }}<span>Shown</span>{{ else }}<span>Hidden</span>{{ endif }}
          {{ if control.alignment == "center" }}<b>Centered</b>{{ endif }}
          <img src="{{ asset("images/icon.svg") }}">
          {{ childArea("content") }}
        </article>
        """

        let html = ComponentTemplateRenderer.render(template, context: context)

        #expect(html.contains("class=\"card c-instance\""))
        #expect(html.contains("data-editor=\"true\""))
        #expect(html.contains("&lt;A &amp; B&gt;"))
        #expect(html.contains("<span>Shown</span>"))
        #expect(!html.contains("Hidden"))
        #expect(html.contains("<b>Centered</b>"))
        #expect(html.contains("assets/components/com.example.card/images/icon.svg"))
        #expect(html.contains("<strong>Child</strong>"))
    }

    @Test
    func rendersMutuallyExclusiveEnvironmentAndElseIfConditions() {
        let properties: [String: ComponentPackageValue] = ["variant": .string("compact")]
        let template = """
        {{ if control.variant == "wide" }}Wide
        {{ elseif control.variant == "compact" }}Compact
        {{ elseif canvas }}Canvas
        {{ else }}Published{{ endif }}
        """
        let canvasContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: properties, slots: [:], environment: .canvas
        )
        let publishedContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:]
        )
        let previewContext = ComponentTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:], environment: .preview
        )

        #expect(ComponentTemplateRenderer.render(template, context: canvasContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Compact")
        #expect(ComponentTemplateRenderer.render(template, context: publishedContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Published")
        #expect(ComponentTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: canvasContext) == "Canvas")
        #expect(ComponentTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: publishedContext) == "Published")
        let environmentTemplate = "{{ if canvas }}Canvas{{ elseif preview }}Preview{{ elseif published }}Published{{ endif }}"
        #expect(ComponentTemplateRenderer.render(environmentTemplate, context: canvasContext) == "Canvas")
        #expect(ComponentTemplateRenderer.render(environmentTemplate, context: previewContext) == "Preview")
        #expect(ComponentTemplateRenderer.render(environmentTemplate, context: publishedContext) == "Published")
    }

    @Test
    func supportsArithmeticComparisonLogicAndFunctions() {
        let context = ComponentTemplateContext(
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

        #expect(ComponentTemplateRenderer.render("{{ control.otherNumber + 2 * 3 }}", context: context) == "16")
        #expect(ComponentTemplateRenderer.render("{{ (control.otherNumber + 2) * 3 }}", context: context) == "36")
        #expect(ComponentTemplateRenderer.render("{{ clamp(control.number, 0, 32) }}", context: context) == "32")
        #expect(ComponentTemplateRenderer.render("{{ max(control.values[0], control.values[1]) }}", context: context) == "7")

        let condition = #"{{ if control.text == "xxxx" && control.number == control.otherNumber + 32 && !control.disabled }}Matched{{ else }}Missed{{ endif }}"#
        #expect(ComponentTemplateRenderer.render(condition, context: context) == "Matched")
        #expect(ComponentTemplateRenderer.render("{{ if control.number < 10 || control.number >= 42 }}Matched{{ endif }}", context: context) == "Matched")
    }

    @Test
    func rendersSitePageAndScopedAssetPaths() {
        let context = ComponentTemplateContext(
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

        let rendered = ComponentTemplateRenderer.render(
            "{{ site.baseURL }}|{{ page.url }}|{{ path.siteRoot }}|{{ path.siteAssets }}|{{ asset(\"images/badge.svg\") }}|{{ asset(\"shared/icons/star.svg\") }}",
            context: context
        )

        #expect(rendered == "https://example.com|https://example.com/about/|..|../assets|files/badge.svg|../assets/shared/icons/star.svg")
    }
}
