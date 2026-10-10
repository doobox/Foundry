import Foundation
import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Foundry

struct SVGControlTests {
    @Test(arguments: [false, true], [false, true])
    func paintOverridesAreIndependentAndProtectHelpers(fill: Bool, stroke: Bool) throws {
        let data = Data("""
        <svg><defs><linearGradient id="gradient"><stop stop-color="red"/></linearGradient></defs>
        <g fill="none" stroke="blue" color="green">
          <path d="M0 0L5 5"/>
          <rect fill="red" stroke="none"/>
          <circle style="fill:none !important;fill:red;stroke:none"/>
          <ellipse fill="url(#gradient)" stroke="none"/>
          <polygon fill="transparent" stroke="none"/>
          <clipPath><rect fill="red"/></clipPath><mask><rect fill="white"/></mask>
        </g></svg>
        """.utf8)
        let result = try #require(PartSVGRenderer.sanitized(data, prefix: "paint",
            overrideFill: fill, overrideStroke: stroke))
        let doc = try XMLDocument(xmlString: result)
        func attribute(_ path: String) throws -> String? { try doc.nodes(forXPath: path).first?.stringValue }
        #expect(try attribute("//g/rect/@fill") == (fill ? "currentColor" : "red"))
        #expect(try attribute("//g/path/@stroke") == (stroke ? "currentColor" : nil))
        #expect(try attribute("//g/@fill") == "none")
        #expect(try attribute("//g/rect/@stroke") == "none")
        #expect(try attribute("//g/circle/@style") == "fill:none !important;fill:red;stroke:none")
        #expect(try attribute("//g/ellipse/@fill") == (fill ? "currentColor" : "url(#fd-svg-paint-0)"))
        #expect(try attribute("//g/polygon/@fill") == "transparent")
        #expect(try attribute("//clipPath/rect/@fill") == "red")
        #expect(try attribute("//mask/rect/@fill") == "white")
        #expect(result.contains("data-foundry-") == false)
    }
    @Test @MainActor func suppliedOrangeSVGImportsWithItsPaintAndClipIntact() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Fixtures/SVG/s-orange.svg")
        let data = try Data(contentsOf: fixture)
        let result = try #require(PartSVGRenderer.sanitized(data, prefix: "orange"))
        #expect(result.contains("fill:rgb(254,91,0)"))
        #expect(result.contains("clip-path=\"url(#fd-svg-orange-1)\""))
        #expect(result.contains("<path"))
        #expect(result.contains("DOCTYPE") == false)
        let svg = try XMLDocument(xmlString: result)
        #expect(try svg.nodes(forXPath: "//*[@data-foundry-svg-fill]").isEmpty)
        #expect(try svg.nodes(forXPath: "//rect[@data-foundry-svg-fill]").isEmpty)
        #expect(try svg.nodes(forXPath: "//*[@data-foundry-svg-stroke]").isEmpty)
        let preview = try #require(NSImage(data: data))
        #expect(preview.isValid)
    }
    @Test(arguments: ["image/svg+xml", "application/octet-stream", "text/xml", ""])
    func recognizesSVGWithGenericDragMetadata(mediaType: String) {
        #expect(PartMediaImport.contentType(filename: "drawing.svg", mediaType: mediaType) == .svg)
    }
    @Test func preservesPaintWithoutLegacyOverrideMarkers() throws {
        let data = Data("""
        <svg><g fill="none" stroke="blue">
        <path d="M0 0L5 5"/><rect fill="red" stroke="none"/>
        <circle style="fill:none !important;fill:red;stroke:none"/>
        <clipPath><rect fill="red"/></clipPath><mask><rect fill="white"/></mask>
        </g></svg>
        """.utf8)
        let result = try #require(PartSVGRenderer.sanitized(data, prefix: "paint"))
        let svg = try XMLDocument(xmlString: result)
        #expect(try svg.nodes(forXPath: "//*[@data-foundry-svg-fill]").isEmpty)
        #expect(try svg.nodes(forXPath: "//*[@data-foundry-svg-stroke]").isEmpty)
        #expect(try svg.nodes(forXPath: "//g[@stroke='blue']").count == 1)
        #expect(try svg.nodes(forXPath: "//circle[@data-foundry-svg-fill]").isEmpty)
    }
    @Test func acceptsStandardSVGDoctypeWithoutLoadingItsDTD() throws {
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0L10 10"/></svg>
        """
        let result = try #require(PartSVGRenderer.sanitized(Data(source.utf8), prefix: "doctype"))
        #expect(result.contains("<path"))
        #expect(result.contains("DOCTYPE") == false)
    }
    @Test func removesActiveContentAndNamespacesLocalPaint() throws {
        let data = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" onload="alert(1)">
        <defs><linearGradient id="paint"><stop stop-color="red"/></linearGradient></defs>
        <script>alert(1)</script><foreignObject><p>bad</p></foreignObject>
        <path fill="url(#paint)" d="M0 0L20 20" style="stroke:blue;fill:url(https://evil.test/x)"/>
        <text>{{ control.secret }}</text></svg>
        """.utf8)
        let result = try #require(PartSVGRenderer.sanitized(data, prefix: "first", alt: "Logo"))
        #expect(result.contains("onload") == false)
        #expect(result.contains("<script") == false)
        #expect(result.contains("foreignObject") == false)
        #expect(result.contains("evil.test") == false)
        #expect(result.contains("url(#fd-svg-first-0)"))
        #expect(result.contains("stroke:blue"))
        #expect(result.contains("aria-label=\"Logo\""))
        #expect(result.contains("{{") == false)
        #expect(PartSVGRenderer.sanitized(data, prefix: "second")?.contains("fd-svg-first") == false)
    }

    @Test(arguments: ["<html/>", "<svg>", "<!DOCTYPE svg [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><svg>&x;</svg>"])
    func rejectsInvalidDocuments(source: String) {
        #expect(PartSVGRenderer.sanitized(Data(source.utf8), prefix: "test") == nil)
    }

    @Test @MainActor func builtInRendersInlineAndProvidesCanvasWell() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = try PartPackageLoader.load(from: root.appending(path: "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/SVG"))
        let previous = PartType.svg.definition.package
        PartRegistry.register(package)
        defer {
            if let previous { PartRegistry.register(previous) }
            else { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        }
        let data = try Data(contentsOf: root.appending(path: "FoundryTests/Fixtures/SVG/s-orange.svg"))
        let asset = ProjectAsset(filename: "logo.svg", mediaType: "image/svg+xml", byteCount: data.count, contentDigest: "svg-test")
        let assets: ProjectAssetContents = [asset.id: .init(asset: asset, data: data)]
        var part = PartNode(type: .svg)
        part.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        let site = Site(name: "SVG", pages: [Page(title: "Home", slug: "index", parts: [part])])
        var values: [String: PartPackageValue] = [:]
        PartSVGRenderer.insert(node: part, package: package, assets: assets, canvas: true, into: &values)
        #expect(values["source"]?.stringValue.contains("data-foundry-svg-drop-zone") == true)
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], language: "en", theme: site.theme, assets: assets, breakpoint: .mobile)
        #expect(canvas.contains("fill:rgb(254,91,0)"))
        #expect(canvas.contains("data-foundry-svg-drop-zone"))
        let output = StaticSiteRenderer().render(site: site, assets: assets)
        #expect(output.errors.isEmpty)
        let page = try #require(output.files.first(where: { $0.path == "index.html" }))
        let html = String(decoding: page.data, as: UTF8.self)
        #expect(html.contains("<svg"))
        #expect(html.contains("fill:rgb(254,91,0)"))
        #expect(html.contains("&lt;svg") == false)
        #expect(html.contains("data-foundry-svg-drop-zone") == false)
    }

    @Test func namedSVGPrimitiveIsRecognized() throws {
        let primitives = PartTemplateRenderer.imagePrimitives(in: "<div>{{ svg(\"artwork\") }}</div>")
        #expect(primitives.count == 1)
        #expect(primitives.first?.isSVG == true)
    }

    @Test func deeplyNestedContentCannotBypassCleaning() throws {
        let source = "<svg>" + String(repeating: "<g>", count: 128)
            + "<path onload=\"bad()\"/>" + String(repeating: "</g>", count: 128) + "</svg>"
        let result = try #require(PartSVGRenderer.sanitized(Data(source.utf8), prefix: "deep"))
        #expect(result.contains("onload") == false)
    }

    @Test func repeatedEmptySVGsHaveIndependentDropTargets() {
        let result = PartTemplateRenderer.render("<div>{{ loop 2 }}{{ svg(\"artwork\") }}{{ endloop }}</div>", context: .init(
            instanceID: UUID(), packageIdentifier: "test.svg", properties: [:],
            templateValues: ["__foundry_svg.artwork": .boolean(true), "artwork": .array([])],
            slots: [:], assetBasePath: "", enablesEditorMarkup: true, loopMaximums: [:]))
        #expect(result.contains("data-foundry-property-path=\"0\""))
        #expect(result.contains("data-foundry-property-path=\"1\""))
        #expect(result.contains("data-foundry-svg-drop-zone"))
    }
}
