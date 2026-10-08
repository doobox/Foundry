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

        let part = PartNode.make(.init(rawValue: package.manifest.identifier))
        let page = Page(title: "Masonry", slug: "index", parts: [part])
        let site = Site(name: "Masonry", pages: [page])
        let html = HTMLPageRenderer(site: site).render(
            page: page,
            language: "en",
            framework: site.framework,
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
        #expect(!html.contains("{{"))
    }

    @Test @MainActor
    func bundledExampleDeclaresRecordsAndRendersThem() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        await catalog.loadControlShowcase()
        let package = try #require(catalog.packages.values.first {
            $0.manifest.identifier == "foundry.showcase.collection"
        })
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
        let html = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
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
              "defaults": {"base": []}
            }],
            "defaults": {"base": []}
          }],
          "templates": {"html": "part.html"}
        }
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest.utf8))
        #expect(diagnostics.contains { $0.message == "Collections cannot be nested." })
    }
}
