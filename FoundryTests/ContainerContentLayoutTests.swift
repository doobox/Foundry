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
            properties: ["contentWidth": .string(width), "contentWidthSpacing": .string("45rem"),
                         "contentAlignment": .string("center"), "contentJustify": .string("end"),
                         "contentGap": .string("2rem")], slots: [:]
        ))
        let expression = try NSRegularExpression(pattern: #"(?s):instance > \.fd-container__content \{(.*?)\}"#)
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
        let controls = manifest.resolvedProperties.filter { $0.group == "Content Layout" }
        #expect(controls.filter { $0.control.type != .note && $0.control.type != .divider }.map(\.id)
            == ["contentWidth", "contentWidthSpacing", "contentAlignment", "contentJustify", "contentGap"])
        #expect(controls.first { $0.id == "contentAlignment" }?.label == "Vertical")
        #expect(controls.first { $0.id == "contentJustify" }?.label == "Horizontal")
        #expect(controls.first { $0.id == "contentWidth" }?.control.options?.map(\.title) == ["Breakpoint", "Full", "Fit Content", "Custom"])
        #expect(controls.contains { $0.id == "contentHeight" } == false)
        #expect(manifest.controlGroups.contains { $0.type == .flexbox } == false)
        #expect(manifest.controlGroups.contains { $0.type == .layout && $0.id == "layout" })
    }

    @Test(arguments: ["breakpoint", "custom", "full", "auto"])
    func innerContainerStacksAndPositionsItsContent(_ width: String) throws {
        let css = try innerDeclarations(width: width)
        #expect(css["display"] == "flex")
        #expect(css["flex-direction"] == "column")
        #expect(css["align-self"] == "center")
        #expect(css["justify-self"] == "end")
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

    @Test(arguments: ["breakpoint", "custom"])
    func fullWidthResetsAnEarlierBreakpointLimit(_ earlierWidth: String) throws {
        var cascade = try innerDeclarations(width: earlierWidth)
        cascade.merge(try innerDeclarations(width: "full")) { _, wider in wider }
        #expect(cascade["max-width"] == "none")
        #expect(cascade["margin-inline"] == "0")
        #expect(cascade["padding-inline"] == "0")
    }
}
