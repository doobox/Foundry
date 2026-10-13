import Foundation
import Testing
@testable import Foundry

@Suite(.serialized)
struct CollectionControlTests {
    @Test @MainActor
    func builtInMasonryGalleryUsesAResponsiveImageCollection() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let package = try #require(catalog.packages.values.first {
            $0.manifest.identifier == "foundry.media.masonry-gallery"
        })

        #expect(package.manifest.showsInPartLibrary)
        let errors = PartPackageValidator.validate(
            package.manifest,
            rootURL: package.resourceRootURL
        ).filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let definition = PartPackageAdapter.definition(from: package)
        let images = try #require(definition.properties.first { $0.key.rawValue == "images" })
        let columns = try #require(definition.properties.first { $0.key.rawValue == "columns" })
        guard case .collection(let itemLabel, let fields) = images.control else {
            Issue.record("Expected an image collection")
            return
        }
        #expect(itemLabel == "Image")
        #expect(fields.filter(\.isInspectorVisible).map { $0.key.rawValue } == [
            "image", "shape", "title", "description", "link"
        ])
        #expect(images.defaultValue.arrayValue?.count == 6)
        #expect(columns.isResponsive)
        #expect(!definition.properties.contains { $0.key.rawValue == "cards" })
        #expect(!definition.properties.contains { $0.key.rawValue == "cardShadow" })
        #expect(package.manifest.libraries == [FoundryWebLibraryRegistry.glightboxRequirement])

        let part = PartNode.make(.init(rawValue: package.manifest.identifier))
        let page = Page(title: "Masonry", slug: "index", parts: [part])
        let site = Site(name: "Masonry", pages: [page])
        let html = HTMLPageRenderer(site: site).render(
            page: page,
            language: "en",
            theme: site.theme,
            assets: [:],
            breakpoint: .large
        )
        #expect(html.contains("foundry-masonry__media--portrait"))
        #expect(html.contains("Portrait image"))
        #expect(html.contains("column-count: 3"))
        #expect(html.contains("font-family: var(--foundry-font-heading);"))
        #expect(html.contains("font-weight: 700;"))
        #expect(html.contains("font-size: var(--foundry-font-size-sm);"))
        #expect(html.contains("color: inherit;"))
        #expect(html.contains("foundry-masonry__shell") == false)
        #expect(!html.contains("-webkit-mask-image"))
        #expect(html.contains("width: 102.5%"))
        #expect(!html.contains("transform: scale(1.025)"))
        #expect(!html.contains("data-foundry-masonry-lightbox"))
        #expect(!html.contains("data-foundry-library=\"glightbox\""))
        #expect(!html.contains("{{"))
    }

    @Test @MainActor
    func masonryUsesLightboxInPreviewAndPublishUnlessAnImageHasALink() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let package = try #require(catalog.packages.values.first {
            $0.manifest.identifier == "foundry.media.masonry-gallery"
        })
        let definition = PartPackageAdapter.definition(from: package)
        let images = try #require(definition.properties.first { $0.key.rawValue == "images" })
        guard case .collection(_, let fields) = images.control else {
            Issue.record("Expected an image collection")
            return
        }

        var destination = PartLink()
        destination.destination = .url("https://example.com/destination")
        var part = PartNode.make(.init(rawValue: package.manifest.identifier))
        part.setProperty(images.key, value: .array([
            PartCollectionValue.record(fields: fields, overriding: [
                "image": .url("https://example.com/lightbox.jpg"),
                "title": .string("Lightbox image"),
                "description": .string("Opens the full image")
            ]),
            PartCollectionValue.record(fields: fields, overriding: [
                "image": .url("https://example.com/linked.jpg"),
                "title": .string("Linked image"),
                "link": .link(destination)
            ])
        ]))
        let page = Page(title: "Masonry", slug: "index", parts: [part])
        let site = Site(name: "Masonry", pages: [page])

        let canvas = HTMLPageRenderer(site: site).render(
            page: page,
            language: "en",
            theme: site.theme,
            assets: [:],
            breakpoint: .large
        )
        #expect(!canvas.contains("data-foundry-masonry-lightbox"))
        #expect(!canvas.contains("data-foundry-library=\"glightbox\""))

        for environment in [PartTemplateEnvironment.preview, .published] {
            let bundle = StaticSiteRenderer(environment: environment).render(site: site)
            #expect(bundle.errors.isEmpty)
            let document = try #require(bundle.file(at: "index.html")?.contents)
            let pageJavaScript = try #require(bundle.file(at: "files/page.js")?.contents)
            let stylesheet = try #require(bundle.file(at: "files/site.css")?.contents)

            #expect(document.contains("href=\"https://example.com/lightbox.jpg\""))
            #expect(document.contains("data-title=\"Lightbox image\""))
            #expect(document.contains("data-description=\"Opens the full image\""))
            #expect(document.contains("href=\"https://example.com/destination\""))
            #expect(document.components(separatedBy: "data-foundry-masonry-lightbox").count - 1 == 1)
            #expect(document.contains("files/libraries/glightbox/glightbox.min.js"))
            #expect(pageJavaScript.contains("GLightbox({"))
            #expect(pageJavaScript.contains("enableGeometryZoom"))
            #expect(pageJavaScript.contains("image.naturalWidth"))
            #expect(stylesheet.contains(".glightbox-container"))
            #expect(stylesheet.contains(".glightbox-clean .gslide-desc { color: #3f3f46; }"))
            #expect(bundle.file(at: "files/libraries/glightbox/glightbox.min.js") != nil)
        }
    }

    @Test @MainActor
    func masonryPageAndLightboxCaptionsCanBeChosenIndependently() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let package = try #require(catalog.packages.values.first {
            $0.manifest.identifier == "foundry.media.masonry-gallery"
        })
        let definition = PartPackageAdapter.definition(from: package)
        let images = try #require(definition.properties.first { $0.key.rawValue == "images" })
        let captionStyle = try #require(package.manifest.resolvedProperties.first { $0.id == "captionStyle" })
        let lightboxCaptions = try #require(package.manifest.resolvedProperties.first { $0.id == "lightboxCaptions" })
        guard case .collection(_, let fields) = images.control else {
            Issue.record("Expected an image collection")
            return
        }

        #expect(captionStyle.control.options?.map(\.value) == ["below", "overlay", "hidden"])
        #expect(captionStyle.control.options?.map(\.title) == ["Below", "Overlay", "None"])
        #expect(lightboxCaptions.defaultValue == .boolean(true))

        let titleSection = PartPropertySection(rawValue: "Titles Text")
        let descriptionSection = PartPropertySection(rawValue: "Descriptions Text")
        let titleCondition = try #require(definition.visibilityCondition(for: titleSection))
        let descriptionCondition = try #require(definition.visibilityCondition(for: descriptionSection))

        var part = PartNode.make(.init(rawValue: package.manifest.identifier))
        part.setProperty(images.key, value: .array([
            PartCollectionValue.record(fields: fields, overriding: [
                "image": .url("https://example.com/captioned.jpg"),
                "title": .string("Caption title"),
                "description": .string("Caption description")
            ])
        ]))

        func document(for part: PartNode) throws -> String {
            let page = Page(title: "Masonry", slug: "index", parts: [part])
            let site = Site(name: "Masonry", pages: [page])
            let bundle = StaticSiteRenderer(environment: .published).render(site: site)
            #expect(bundle.errors.isEmpty)
            return try #require(bundle.file(at: "index.html")?.contents)
        }

        let both = try document(for: part)
        #expect(both.contains("<figcaption"))
        #expect(both.contains("data-title=\"Caption title\""))
        #expect(PartPackageVisibilityEvaluator.isVisible(titleCondition, for: part, at: .mobile))
        #expect(PartPackageVisibilityEvaluator.isVisible(descriptionCondition, for: part, at: .mobile))

        part.setProperty(.init(rawValue: "lightboxCaptions"), value: .boolean(false))
        let pageOnly = try document(for: part)
        #expect(pageOnly.contains("<figcaption"))
        #expect(!pageOnly.contains("data-title=\"Caption title\""))
        #expect(!pageOnly.contains("data-description=\"Caption description\""))

        part.setProperty(.init(rawValue: "captionStyle"), value: .choice("hidden"))
        part.setProperty(.init(rawValue: "lightboxCaptions"), value: .boolean(true))
        let lightboxOnly = try document(for: part)
        #expect(!lightboxOnly.contains("<figcaption"))
        #expect(lightboxOnly.contains("data-title=\"Caption title\""))
        #expect(lightboxOnly.contains("data-description=\"Caption description\""))
        #expect(!PartPackageVisibilityEvaluator.isVisible(titleCondition, for: part, at: .mobile))
        #expect(!PartPackageVisibilityEvaluator.isVisible(descriptionCondition, for: part, at: .mobile))

        part.setProperty(.init(rawValue: "lightboxCaptions"), value: .boolean(false))
        let neither = try document(for: part)
        #expect(!neither.contains("<figcaption"))
        #expect(!neither.contains("data-title=\"Caption title\""))
        #expect(!neither.contains("data-description=\"Caption description\""))
    }

    @Test @MainActor
    func collectionDefaultsDeclareRecordsAndRenderThem() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let resources = root.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = """
        {
          "id": "com.example.collection-records", "title": "Collection", "version": "1.0.0", "minimumAPIVersion": 1,
          "templates": {"html": "part.html"},
          "inspector": [{"section": "Cards", "controls": [{
            "type": "collection", "id": "cards", "itemLabel": "Card",
            "controls": [
              {"type": "image", "id": "image"},
              {"type": "text", "id": "title", "defaults": {"xs": ""}},
              {"type": "textArea", "id": "description", "defaults": {"xs": ""}},
              {"type": "link", "id": "link", "defaults": {"xs": ""}}
            ],
            "defaults": {"xs": [{"title": "First card"}, {"title": "Second card"}]}
          }]}]
        }
        """
        try manifest.write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        try """
        <section class="{{ part.class }}" {{ part.attributes }}>{{ loop control.cards as card }}<h3>{{ card.title }}</h3>{{ endloop }}</section>
        """.write(to: resources.appending(path: "part.html"), atomically: true, encoding: .utf8)
        let package = try PartPackageLoader.load(from: root)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let errors = PartPackageValidator.validate(
            package.manifest,
            rootURL: package.resourceRootURL
        ).filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let definition = PartPackageAdapter.definition(from: package)
        let property = try #require(definition.properties.first { $0.key.rawValue == "cards" })
        guard case .collection(let itemLabel, let fields) = property.control else {
            Issue.record("Expected a collection control")
            return
        }
        #expect(itemLabel == "Card")
        #expect(fields.filter(\.isInspectorVisible).map { $0.key.rawValue } == ["image", "title", "description", "link"])
        let records = try #require(property.defaultValue.arrayValue)
        #expect(records.count == 2)
        #expect(Set(records.compactMap(PartCollectionValue.id)).count == 2)
        #expect(PartCollectionValue.title(itemLabel: itemLabel, position: 0) == "Card 1")

        let part = PartNode.make(.init(rawValue: package.manifest.identifier))
        let site = Site(name: "Collection", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let html = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        #expect(html.contains("First card"))
        #expect(html.contains("Second card"))
        #expect(html.contains("{{") == false)
    }

    @Test @MainActor
    func collectionLinkUsesTheOrdinaryResolvedTemplateValues() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let package = try #require(catalog.packages.values.first {
            $0.manifest.identifier == "foundry.media.masonry-gallery"
        })
        let definition = PartPackageAdapter.definition(from: package)
        let images = try #require(definition.properties.first { $0.key.rawValue == "images" })
        guard case .collection(_, let fields) = images.control else {
            Issue.record("Expected a collection control")
            return
        }

        var destination = PartLink()
        destination.destination = .url("https://example.com/card")
        destination.opensInNewWindow = true
        var part = PartNode.make(.init(rawValue: package.manifest.identifier))
        part.setProperty(images.key, value: .array([
            PartCollectionValue.record(
                fields: fields,
                overriding: [
                    "title": .string("Linked card"),
                    "link": .link(destination)
                ]
            )
        ]))
        let page = Page(title: "Home", slug: "index", parts: [part])
        let site = Site(name: "Collection", pages: [page])
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)

        #expect(html.contains("href=\"https://example.com/card\""))
        #expect(html.contains("target=\"_blank\""))
        #expect(html.contains("rel=\"noopener noreferrer\""))
    }

    @Test
    func loopAttributesIdentifyCanvasItemsButDoNotPublish() throws {
        let template = "{{ loop control.cards as card }}<article {{ loop.attributes }}>{{ card.title }}</article>{{ endloop }}"
        let properties: [String: PartPackageValue] = [
            "__foundry_collection_label.cards": .string("Card"),
            "cards": .array([
                .object(["title": .string("One")]),
                .object(["title": .string("Two")])
            ])
        ]
        let canvas = try PartTemplateLoop.expand(
            template,
            properties: properties,
            maximums: [:],
            environment: .canvas
        ).template
        let published = try PartTemplateLoop.expand(
            template,
            properties: properties,
            maximums: [:],
            environment: .published
        ).template

        #expect(canvas.contains("data-foundry-collection-property=\"cards\""))
        #expect(canvas.contains("data-foundry-collection-label=\"Card\""))
        #expect(canvas.contains("data-foundry-property-path=\"0\""))
        #expect(canvas.contains("data-foundry-property-path=\"1\""))
        #expect(!published.contains("data-foundry-collection-property"))
        #expect(!published.contains("loop.attributes"))
    }

    @Test
    func collectionRecordsRoundTripWithStableIdentity() throws {
        let id = UUID()
        let value = PartCollectionValue.record(
            fields: [],
            overriding: ["title": .string("Example")],
            id: id
        )
        let encoded = try FoundryDocument.encoder.encode(value)
        let decoded = try FoundryDocument.decoder.decode(PartProperty.Value.self, from: encoded)
        #expect(decoded == value)
        #expect(PartCollectionValue.id(of: decoded) == id.uuidString)
    }

    @Test
    func collectionFieldsResolveResponsiveValuesPerItem() throws {
        let field = PartPropertyDefinition(
            key: .init(rawValue: "title"),
            label: "Title",
            section: .content,
            control: .singleLineText,
            defaultValue: .string("Base"),
            isResponsive: true
        )
        var record = PartCollectionValue.record(fields: [field])
        record = PartCollectionValue.setting(
            .string("Medium"),
            fieldID: "title",
            in: record,
            at: .medium
        )

        #expect(PartCollectionValue.value(fieldID: "title", in: record, at: .mobile, screens: .standard) == .string("Base"))
        #expect(PartCollectionValue.value(fieldID: "title", in: record, at: .medium, screens: .standard) == .string("Medium"))
        #expect(PartCollectionValue.value(fieldID: "title", in: record, at: .large, screens: .standard) == .string("Medium"))
        #expect(PartCollectionValue.hasOverride(fieldID: "title", in: record, at: .medium))
        #expect(PartCollectionValue.resolved(record, fields: [field], at: .medium, screens: .standard).objectValue?["_responsive"] == nil)
    }

    @Test
    func collectionSchemaRejectsNestedCollections() throws {
        let manifest = """
        {
          "minimumAPIVersion": 1,
          "id": "com.example.collection",
          "title": "Collection",
          "version": "1.0.0",
          "inspector": [{
            "type": "collection",
            "id": "items",
            "controls": [{
              "type": "collection",
              "id": "children",
              "controls": [],
              "defaults": {"xs": []}
            }],
            "defaults": {"xs": []}
          }],
          "templates": {"html": "part.html"}
        }
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest.utf8))
        #expect(diagnostics.contains { $0.message == "Collections cannot be nested." })
    }
}
