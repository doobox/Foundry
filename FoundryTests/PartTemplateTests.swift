import Foundation
import Testing
@testable import Foundry

struct PartTemplateTests {
    @Test
    func cssSelectorsDistinguishPackageFromInstance() {
        let instanceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let css = ":host { display: block; } :instance { color: red; } :parent:hover :instance { opacity: 1; }"

        let rendered = PartTemplateRenderer.scopedCSS(
            css,
            packageIdentifier: "com.example.card",
            instanceID: instanceID
        )

        #expect(rendered.contains(":is([data-foundry-package=\"com.example.card\"], .foundry-package-com-example-card)"))
        #expect(rendered.contains("[data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(rendered.contains("[data-foundry-part]:has([data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]):not(:has([data-foundry-part] [data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"])):hover [data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(!rendered.contains(":host"))
        #expect(!rendered.contains(":instance"))
    }

    @Test
    func namedDropZoneAndChildAreaRenderTheirOwnContent() {
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.container",
            properties: [:],
            slots: ["content": "<strong>Child</strong>"],
            dropZones: ["content": "<p>Child</p>"]
        )

        #expect(PartTemplateRenderer.render("{{ dropZone(\"content\") }}", context: context) == "<p>Child</p>")
        #expect(PartTemplateRenderer.render("{{ childArea(\"content\") }}", context: context) == "<strong>Child</strong>")
        #expect(PartTemplateRenderer.render("{{ dropzone(\"content\") }}", context: context).isEmpty)
    }

    @Test
    func namedEditableMacrosKeepValuesWhenTheirTemplateOrderChanges() {
        let context = PartTemplateContext(
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

        #expect(PartTemplateRenderer.render(original, context: context) == "<h2>Saved heading</h2><p>Saved body</p>")
        #expect(PartTemplateRenderer.render(reordered, context: context) == "<p>Saved body</p><h2>Saved heading</h2>")
    }

    @Test
    func editableMacroDefaultsSupportEscapedStringCharacters() throws {
        let template = #"<p>{{ text("caption", default: "Say \"hello\"") }}</p>"#
        let primitive = try #require(PartTemplateRenderer.textPrimitives(in: template).first)

        #expect(primitive.key == "caption")
        #expect(primitive.defaultValue == #"Say "hello""#)
    }

    @Test
    func developerExpressionsResolveInstanceControlsAndReadableColorFilters() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let context = PartTemplateContext(
            instanceID: id,
            packageIdentifier: "com.example.card",
            properties: ["accent": .string("#336699"), "frameworkPadding": .string("24px 24px 24px 24px")],
            slots: [:]
        )
        let template = """
        /* {{ instance.id }} */
        [data-foundry-id="{{ instance.id }}"] {
          padding: {{ control.frameworkPadding }};
          color: {{ control.accent }};
          border-color: {{ control.accent | lighten(20) }};
          background-color: {{ control.accent | darken(25) }};
        }
        """

        let rendered = PartTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("[data-foundry-id=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"]"))
        #expect(rendered.contains("/* AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE */"))
        #expect(rendered.contains("padding: 24px"))
        #expect(rendered.contains("color: #336699"))
        #expect(rendered.contains("border-color: #5C85AD"))
        #expect(rendered.contains("background-color: #264D73"))
    }

    @Test
    func rendersEscapedPropertiesConditionsSlotsAssetsAndEditorHooks() {
        let context = PartTemplateContext(
            instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            packageIdentifier: "com.example.card",
            properties: [
                "title": .string("<A & B>"),
                "visible": .boolean(true),
                "alignment": .string("center")
            ],
            slots: ["content": "<strong>Child</strong>"],
            partClass: "c-instance",
            partAttributes: "data-editor=\"true\"",
            assetBasePath: "assets/parts/com.example.card"
        )
        let template = """
        <article class="card {{ part.class }}" {{ part.attributes }}>
          <h2>{{ control.title }}</h2>
          {{ if control.visible }}<span>Shown</span>{{ else }}<span>Hidden</span>{{ endif }}
          {{ if control.alignment == "center" }}<b>Centered</b>{{ endif }}
          <img src="{{ asset("images/icon.svg") }}">
          {{ childArea("content") }}
        </article>
        """

        let html = PartTemplateRenderer.render(template, context: context)

        #expect(html.contains("class=\"card c-instance\""))
        #expect(html.contains("data-editor=\"true\""))
        #expect(html.contains("&lt;A &amp; B&gt;"))
        #expect(html.contains("<span>Shown</span>"))
        #expect(!html.contains("Hidden"))
        #expect(html.contains("<b>Centered</b>"))
        #expect(html.contains("assets/parts/com.example.card/images/icon.svg"))
        #expect(html.contains("<strong>Child</strong>"))
    }

    @Test
    func rendersMutuallyExclusiveEnvironmentAndElseIfConditions() {
        let properties: [String: PartPackageValue] = ["variant": .string("compact")]
        let template = """
        {{ if control.variant == "wide" }}Wide
        {{ elseif control.variant == "compact" }}Compact
        {{ elseif canvas }}Canvas
        {{ else }}Published{{ endif }}
        """
        let canvasContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: properties, slots: [:], environment: .canvas
        )
        let publishedContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:]
        )
        let previewContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.conditions",
            properties: [:], slots: [:], environment: .preview
        )

        #expect(PartTemplateRenderer.render(template, context: canvasContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Compact")
        #expect(PartTemplateRenderer.render(template, context: publishedContext).trimmingCharacters(in: .whitespacesAndNewlines) == "Published")
        #expect(PartTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: canvasContext) == "Canvas")
        #expect(PartTemplateRenderer.render("{{ if canvas }}Canvas{{ else }}Published{{ endif }}", context: publishedContext) == "Published")
        let environmentTemplate = "{{ if canvas }}Canvas{{ elseif preview }}Preview{{ elseif published }}Published{{ endif }}"
        #expect(PartTemplateRenderer.render(environmentTemplate, context: canvasContext) == "Canvas")
        #expect(PartTemplateRenderer.render(environmentTemplate, context: previewContext) == "Preview")
        #expect(PartTemplateRenderer.render(environmentTemplate, context: publishedContext) == "Published")

        let nested = "{{ if control.variant == \"compact\" }}Outer {{ if canvas }}Canvas{{ else }}Published{{ endif }} End{{ endif }}"
        #expect(PartTemplateRenderer.render(nested, context: canvasContext) == "Outer Canvas End")
        #expect(PartTemplateRenderer.render(nested, context: publishedContext).isEmpty)
    }

    @Test
    func supportsArithmeticComparisonLogicAndFunctions() {
        let context = PartTemplateContext(
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

        #expect(PartTemplateRenderer.render("{{ control.otherNumber + 2 * 3 }}", context: context) == "16")
        #expect(PartTemplateRenderer.render("{{ (control.otherNumber + 2) * 3 }}", context: context) == "36")
        #expect(PartTemplateRenderer.render("{{ clamp(control.number, 0, 32) }}", context: context) == "32")
        #expect(PartTemplateRenderer.render("{{ max(control.values[0], control.values[1]) }}", context: context) == "7")

        let condition = #"{{ if control.text == "xxxx" && control.number == control.otherNumber + 32 && !control.disabled }}Matched{{ else }}Missed{{ endif }}"#
        #expect(PartTemplateRenderer.render(condition, context: context) == "Matched")
        #expect(PartTemplateRenderer.render("{{ if control.number < 10 || control.number >= 42 }}Matched{{ endif }}", context: context) == "Matched")
    }

    @Test
    func supportsStringWildcardCollectionAndEmptyPredicates() {
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.predicates",
            properties: [
                "title": .string("Foundry Layout"),
                "slug": .string("docs-layout-2"),
                "tags": .array([.string("featured"), .string("layout")]),
                "emptyText": .string(""),
                "emptyItems": .array([])
            ],
            slots: [:]
        )

        let expressions = [
            #"contains(control.title, "Layout")"#,
            #"notContains(control.title, "Video")"#,
            #"containsInsensitive(control.title, "foundry")"#,
            #"notContainsInsensitive(control.title, "video")"#,
            #"matches(control.slug, "docs-*-?")"#,
            #"notMatches(control.slug, "blog-*")"#,
            #"matchesInsensitive(control.title, "FOUNDRY*")"#,
            #"notMatchesInsensitive(control.title, "VIDEO*")"#,
            #"containsValue(control.tags, "featured")"#,
            #"notContainsValue(control.tags, "draft")"#,
            #"isEmpty(control.emptyText)"#,
            #"isEmpty(control.emptyItems)"#,
            #"isNotEmpty(control.tags)"#
        ]

        for expression in expressions {
            let template = "{{ if \(expression) }}Matched{{ else }}Missed{{ endif }}"
            #expect(PartTemplateRenderer.render(template, context: context) == "Matched", "Failed: \(expression)")
        }
    }

    @Test
    func rendersSitePageAndScopedAssetPaths() {
        let context = PartTemplateContext(
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

        let rendered = PartTemplateRenderer.render(
            "{{ site.baseURL }}|{{ page.url }}|{{ path.siteRoot }}|{{ path.siteAssets }}|{{ asset(\"images/badge.svg\") }}|{{ asset(\"shared/icons/star.svg\") }}",
            context: context
        )

        #expect(rendered == "https://example.com|https://example.com/about/|..|../assets|files/badge.svg|../assets/shared/icons/star.svg")
    }
}
