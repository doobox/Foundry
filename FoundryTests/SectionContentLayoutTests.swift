import Foundation
import Testing
@testable import Foundry

struct SectionContentLayoutTests {
    private func package() throws -> LoadedPartPackage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Section"))
    }

    private func innerDeclarations(width: String) throws -> [String: String] {
        let package = try package()
        try package.preparePayload()
        var values = Dictionary(uniqueKeysWithValues: package.manifest.resolvedProperties.map { ($0.id, $0.defaultValue) })
        values["contentWidth"] = .string(width)
        values["contentWidthSpacing"] = .string("45rem")
        values["contentAlignment"] = .string("center")
        values["contentGap"] = .string("2rem")
        PartPackageControlGroupCSSResolver.resolve(&values, properties: package.manifest.resolvedProperties)
        let css = PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier,
            properties: values, slots: [:]
        ))
        let expression = try NSRegularExpression(pattern: #"(?s):instance > \.fd-section__content \{(.*?)\}"#)
        let match = try #require(expression.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)))
        let range = try #require(Range(match.range(at: 1), in: css))
        let body = String(css[range]).replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
        var declarations: [String: String] = [:]
        // Later declarations win, as in CSS.
        for declaration in body.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                declarations[pair[0].trimmingCharacters(in: .whitespacesAndNewlines)] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return declarations
    }

    @Test
    func contentControlsHaveOneSectionAndExplicitAxisLabels() throws {
        let manifest = try package().manifest
        let controls = manifest.resolvedProperties.filter { $0.group == "Section" }
        #expect(manifest.controlSections.first?.name == "Section")
        #expect(manifest.controlSections.contains { $0.name == "Content Spacing" } == false)
        #expect(["contentWidth", "contentWidthSpacing", "contentAlignment", "contentGap"].allSatisfy { id in
            controls.contains { $0.id == id }
        })
        #expect(controls.first { $0.id == "contentAlignment" }?.label == "Vertical position")
        let width = try #require(controls.first { $0.id == "contentWidth" })
        #expect(width.label == "Content width")
        #expect(width.control.options?.map(\.title) == ["Fit content", "Full", "Site width", "Custom"])
        #expect(width.control.options?.map(\.value) == ["auto", "full", "breakpoint", "custom"])
        #expect(width.defaultValue == .string("breakpoint"))
        #expect(controls.first { $0.id == "contentWidthSpacing" }?.label == "Custom width")
        #expect(controls.contains { $0.id == "contentHeight" } == false)
        #expect(manifest.controlGroups.contains { $0.type == .flexbox } == false)
        #expect(manifest.controlGroups.contains { $0.type == .layout && $0.id == "layout" })
        #expect(manifest.controlGroups.contains { $0.id == "contentSpacing" } == false)
        // Vertical position only matters once the section has spare height.
        let vertical = try #require(controls.first { $0.id == "contentAlignment" })
        #expect(vertical.visibleWhen != nil)
    }

    @Test(arguments: ["breakpoint", "custom", "full", "auto"])
    func innerSectionStacksAndPositionsItsContent(_ width: String) throws {
        let css = try innerDeclarations(width: width)
        #expect(css["display"] == "flex")
        #expect(css["flex-direction"] == "column")
        // Children keep their own widths, like blocks in a div.
        #expect(css["align-items"] == "flex-start")
        #expect(css["align-self"] == "center")
        #expect(css["justify-self"] == "center")
        #expect(css["justify-self"] != "end")
        #expect(css["gap"] == "2rem")
        switch width {
        case "breakpoint": #expect(css["max-width"] == "var(--foundry-container-width)")
        case "custom":
            #expect(css["width"] == "45rem")
            #expect(css["max-width"] == "100%")
        case "full": #expect(css["width"] == "100%")
        default: #expect(css["width"] == "auto")
        }
    }

    @Test @MainActor
    func contentBoxIsCentredWithoutASecondSpacingControl() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let part = PartNode.make(.section)
        let site = Site(name: "Section", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let html = HTMLPageRenderer(site: site).render(page: site.pages[0], theme: site.theme)
        let expression = try NSRegularExpression(pattern: #"(?s)\.fd-section__content \{(.*?)\}"#)
        let match = try #require(expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)))
        let body = String(html[try #require(Range(match.range(at: 1), in: html))])
        #expect(body.contains("justify-self: center;"), "\(body)")
        #expect(body.contains("margin:") == false, "\(body)")
        #expect(body.contains("align-items: flex-start;"))
    }

    @Test(arguments: ["breakpoint", "custom"])
    func fullWidthResetsAnEarlierBreakpointLimit(_ earlierWidth: String) throws {
        var cascade = try innerDeclarations(width: earlierWidth)
        cascade.merge(try innerDeclarations(width: "full")) { _, wider in wider }
        #expect(cascade["max-width"] == "none")
        #expect(cascade["margin"] == nil)
        #expect(cascade["padding"] == nil)
    }
}
