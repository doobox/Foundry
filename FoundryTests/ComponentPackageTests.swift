import Foundation
import Testing
@testable import Foundry

struct ComponentPackageTests {
    @Test
    func textPrimitivesUseAutomaticUniqueKeysAndStoredValues() throws {
        let template = #"<h2>%text="Start here"%</h2><p>%text%</p><small>%text="Note"%</small>"#
        let defaultContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )
        let editedContext = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [
                "content1": .string("Edited & ready"),
                "content2": .string("A shorter paragraph."),
                "content3": .string("Updated note")
            ],
            slots: [:]
        )

        let primitives = ComponentTemplateRenderer.textPrimitives(in: template)
        #expect(primitives.map(\.key) == ["content1", "content2", "content3"])
        let first = try #require(primitives.first)
        let paragraph = try #require(primitives.dropFirst().first)
        #expect(first.defaultValue == "Start here")
        #expect(paragraph.defaultValue.components(separatedBy: ".").count >= 3)
        #expect(ComponentTemplateRenderer.render(template, context: defaultContext).contains("Start here"))
        let edited = ComponentTemplateRenderer.render(template, context: editedContext)
        #expect(edited.contains("Edited &amp; ready"))
        #expect(edited.contains("A shorter paragraph."))
        #expect(edited.contains("Updated note"))
    }

    @Test
    func bareTextPrimitiveUsesOneLoremParagraphWithoutAnExportedWrapper() {
        let template = "<p>%text%</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )

        let primitive = ComponentTemplateRenderer.textPrimitives(in: template)[0]
        #expect(primitive.key == "content1")
        #expect(primitive.defaultValue.components(separatedBy: ".").count >= 6)
        let rendered = ComponentTemplateRenderer.render(template, context: context)
        #expect(rendered.hasPrefix("<p>Lorem ipsum"))
        #expect(!rendered.contains("<span"))
    }

    @Test
    func textPrimitivePreservesEditedLineBreaks() {
        let template = "<p>%text%</p>"
        let context = ComponentTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["content1": .string("First line\nSecond & final line")],
            slots: [:]
        )

        #expect(
            ComponentTemplateRenderer.render(template, context: context)
                == "<p>First line<br>Second &amp; final line</p>"
        )
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
        #{{ id }} {
          padding: {{ control.padding }}px;
          color: {{ control.accent }};
          border-color: {{ control.accent | lighten(20) }};
          background-color: {{ control.accent | darken(25) }};
        }
        """

        let rendered = ComponentTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("#foundry-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        #expect(rendered.contains("padding: 24px"))
        #expect(rendered.contains("color: #336699"))
        #expect(rendered.contains("border-color: #5C85AD"))
        #expect(rendered.contains("background-color: #264D73"))
    }

    @Test
    func templateRendersEscapedPropertiesConditionsSlotsAssetsAndEditorHooks() {
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
        <article class="card{{ component.class }}" {{ component.attributes }}>
          <h2>{{ property.title }}</h2>
          {% if property.visible %}<span>Shown</span>{% else %}<span>Hidden</span>{% endif %}
          {% if property.alignment == "center" %}<b>Centered</b>{% endif %}
          <img src="{{ asset.images/icon.svg }}">
          {% slot id="content" %}
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
    func validatorReportsTemplateContractErrorsWithLineLocations() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: """
            <section>
              {{ property.missing }}
              {% slot id="unknown" %}
              {{ asset.../secret.txt }}
              {% mystery %}
              {% if property.title %}
            </section>
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            ComponentPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = ComponentPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        let messages = diagnostics.map(\.message)

        #expect(messages.contains(where: { $0.contains("component.attributes") }))
        #expect(messages.contains(where: { $0.contains("Unknown property 'missing'") }))
        #expect(messages.contains(where: { $0.contains("Unknown slot 'unknown'") }))
        #expect(messages.contains(where: { $0.contains("Declared slot 'content'") }))
        #expect(messages.contains(where: { $0.contains("Asset paths must be relative") }))
        #expect(messages.contains(where: { $0.contains("unbalanced") }))
        #expect(messages.contains(where: { $0.contains("Unknown template directive 'mystery'") }))
        #expect(diagnostics.contains(where: { $0.location == "component.html:2" }))
    }

    @Test
    func loaderRejectsUnapprovedRuntimeCapabilities() throws {
        let manifest = validManifest.replacingOccurrences(
            of: "<key>assets</key>",
            with: """
            <key>runtime</key>
            <dict>
                <key>entry</key><string>component.js</string>
                <key>capabilities</key><array><string>network</string></array>
            </dict>
            <key>assets</key>
            """
        )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ component.attributes }}>{{ property.title }}{% slot id=\"content\" %}</section>",
            additionalFiles: ["component.js": "export function mount() {}"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        #expect(throws: ComponentPackageLoadingError.self) {
            try ComponentPackageLoader.load(from: packageURL)
        }
    }

    @Test
    func insertingIntoNamedSlotStoresTheSlotOnTheChild() throws {
        let parentID = UUID()
        var tree = [ComponentNode(id: parentID, type: .container)]
        let child = ComponentNode.make(.paragraph)

        let didInsert = tree.insert(child, at: .insideSlot(parentID, "sidebar"))

        #expect(didInsert)
        let insertedChild = try #require(tree.first?.children.first)
        #expect(insertedChild.slotID == "sidebar")
    }

    @Test @MainActor
    func builtInsAreLoadedAsPublicComponentPackages() {
        let builtIns = ComponentRegistry.builtInTypes.map(\.definition)

        #expect(builtIns.allSatisfy { $0.renderKind == .package })
        #expect(builtIns.allSatisfy { $0.package?.rootURL.pathExtension == "foundrypack" })
        #expect(Set(builtIns.compactMap { $0.package?.manifest.identifier }).count == builtIns.count)
    }

    @Test @MainActor
    func paragraphUsesUnifiedCustomColorWithOptInCapabilities() throws {
        _ = ComponentPackageCatalog.shared
        let properties = ComponentType.paragraph.definition.properties
        let color = try #require(properties.first(where: { $0.key.rawValue == "textColor" }))
        let custom = try #require(properties.first(where: { $0.key.rawValue == "textColorCustom" }))
        let colorMath = try #require(properties.first(where: { $0.key.rawValue == "textColorColorMath" }))
        let opacity = try #require(properties.first(where: { $0.key.rawValue == "textColorOpacity" }))

        #expect(color.defaultValue == .choice(ThemeColorRole.text.rawValue))
        if case .packageColor(let themeValues, _, let mathKey, let opacityKey) = color.control {
            #expect(themeValues)
            #expect(mathKey == colorMath.key)
            #expect(opacityKey == opacity.key)
        } else {
            Issue.record("Paragraph should use the package colour control")
        }
        #expect(custom.defaultValue == .color("#000000"))
        #expect(colorMath.defaultValue == .number(0))
        #expect(opacity.defaultValue == .number(1))
    }

    @Test
    func packDiscoveryRecursesThroughFunctionalAndCollectionPacksWithoutFlattening() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let nested = root.appending(path: "Nested.foundrypack", directoryHint: .isDirectory)
        let deeplyNested = nested.appending(path: "Deep.foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePackHeader(type: .collection, identifier: "com.example.collection", at: root)
        try writePackHeader(type: .component, identifier: "com.example.nested", at: nested)
        try writePackHeader(type: .theme, identifier: "com.example.deep", at: deeplyNested)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root, deeplyNested, nested].map(\.standardizedFileURL).sorted { $0.path < $1.path })
        #expect(try FoundryPackLoader.load(from: urls[0]).rootURL.standardizedFileURL == urls[0].standardizedFileURL)
        #expect(deeplyNested.path.hasPrefix(nested.path))
    }

    private var validManifest: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>type</key><string>component</string>
            <key>CFBundleIdentifier</key><string>com.example.card</string>
            <key>title</key><string>Card</string>
            <key>description</key><string>A test card.</string>
            <key>group</key><string>Content component</string>
            <key>icon</key><string>icon.svg</string>
            <key>slots</key>
            <array>
                <dict>
                    <key>id</key><string>content</string>
                    <key>title</key><string>Content</string>
                    <key>accepts</key><array><string>*</string></array>
                    <key>minimum</key><integer>0</integer>
                </dict>
            </array>
            <key>customItems</key>
            <array>
                <dict>
                    <key>id</key><string>title</string>
                    <key>title</key><string>Title</string>
                    <key>section</key><string>Content</string>
                    <key>control</key><dict><key>type</key><string>text</string></dict>
                    <key>default</key><string>Hello</string>
                    <key>responsive</key><false/>
                    <key>inlineEditable</key><true/>
                </dict>
            </array>
            <key>templates</key>
            <dict>
                <key>html</key><string>component.html</string>
                <key>css</key><string>component.css</string>
            </dict>
            <key>assets</key><array><string>images/icon.svg</string></array>
        </dict>
        </plist>
        """
    }

    private func makePackage(
        manifest: String,
        template: String,
        additionalFiles: [String: String] = [:]
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let resourcesURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: resourcesURL.appending(path: "images", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let files = [
            "component.html": template,
            "component.css": ":host { display: block; }",
            "icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
            "images/icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        ].merging(additionalFiles) { _, additional in additional }
        try Data(manifest.utf8).write(to: rootURL.appending(path: "Contents/Info.plist"))
        for (path, contents) in files {
            try Data(contents.utf8).write(to: resourcesURL.appending(path: path))
        }
        return rootURL
    }

    private func writePackHeader(type: FoundryPackType, identifier: String, at rootURL: URL) throws {
        let contentsURL = rootURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = ["type": type.rawValue, "CFBundleIdentifier": identifier]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
    }
}
