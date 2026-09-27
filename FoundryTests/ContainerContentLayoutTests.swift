import Foundation
import Testing
@testable import Foundry

struct ContainerContentLayoutTests {
    private func package() throws -> LoadedPartPackage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try PartPackageLoader.load(from: root.appending(path:
            "Foundry/Resources/BuiltInParts.bundle/Contents/Resources/BuiltInParts.foundrypack/Parts/Container"))
    }

    private func innerDeclarations(width: String) throws -> [String: String] {
        let package = try package()
        try package.preparePayload()
        let css = PartTemplateRenderer.render(package.css, context: .init(
            instanceID: UUID(), packageIdentifier: package.manifest.identifier,
            properties: ["contentWidth": .string(width), "customContentWidth": .number(720),
                         "contentAlignment": .string("center"), "contentJustify": .string("flex-end"),
                         "contentGap": .string("2rem")], slots: [:]
        ))
        let expression = try NSRegularExpression(pattern: #"(?s):instance > \.fd-container__content \{(.*?)\}"#)
        let match = try #require(expression.firstMatch(in: css, range: NSRange(css.startIndex..., in: css)))
        let range = try #require(Range(match.range(at: 1), in: css))
        let body = String(css[range]).replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
        var declarations: [String: String] = [:]
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
        let controls = manifest.resolvedProperties.filter { $0.group == "Content Layout" }
        #expect(controls.map(\.id) == ["contentWidth", "customContentWidth", "contentAlignment", "contentJustify", "contentGap"])
        #expect(controls.first { $0.id == "contentAlignment" }?.label == "Vertical Alignment")
        #expect(controls.first { $0.id == "contentJustify" }?.label == "Horizontal Alignment")
        #expect(controls.first { $0.id == "contentWidth" }?.control.options?.map(\.title) == ["Site Content Width", "Full Width", "Custom"])
        #expect(manifest.controlGroups.contains { $0.type == .flexbox } == false)
        #expect(manifest.controlGroups.contains { $0.type == .layout && $0.id == "layout" })
    }

    @Test(arguments: ["contained", "custom", "full"])
    func innerContainerAlwaysStacksAndFillsAvailableHeight(_ width: String) throws {
        let css = try innerDeclarations(width: width)
        #expect(css["display"] == "flex")
        #expect(css["flex-direction"] == "column")
        #expect(css["flex"] == "1 1 auto")
        #expect(css["justify-content"] == "center")
        #expect(css["align-items"] == "flex-end")
        #expect(css["gap"] == "2rem")
    }

    @Test(arguments: ["contained", "custom"])
    func fullWidthResetsAnEarlierBreakpointLimit(_ earlierWidth: String) throws {
        var cascade = try innerDeclarations(width: earlierWidth)
        cascade.merge(try innerDeclarations(width: "full")) { _, wider in wider }
        #expect(cascade["max-width"] == "none")
        #expect(cascade["margin-inline"] == "0")
        #expect(cascade["padding-inline"] == "0")
    }
}
