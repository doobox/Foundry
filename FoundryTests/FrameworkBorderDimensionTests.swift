import Foundation
import Testing
@testable import Foundry

@Suite("Framework border dimensions")
@MainActor
struct FrameworkBorderDimensionTests {
    @Test func borderRowsPreserveHiddenStyleDefault() throws {
        let data = Data(#"{"type":"frameworkBorder","id":"border","responsive":true,"defaults":{"base":{"width":"sm","style":"dotted"}}}"#.utf8)
        let property = try JSONDecoder().decode(PartPackageProperty.self, from: data)
        let rows = PartPackageFrameworkBorderControl.properties(property)
        #expect(rows.map(\.key.rawValue) == ["border.width", "border.style"])
        #expect(rows.map(\.isInspectorVisible) == [true, false])
        #expect(rows.map(\.isResponsive) == [true, true])
        #expect(rows.allSatisfy { $0.inspectorControlID == "border" })
        #expect(rows[1].defaultValue == .choice("dotted"))
        let defaults = try JSONDecoder().decode(PartPackageProperty.self, from: Data(#"{"type":"frameworkBorder","id":"border","defaults":{"base":{"width":"none"}}}"#.utf8))
        let defaultRows = PartPackageFrameworkBorderControl.properties(defaults)
        #expect(defaultRows.map(\.isInspectorVisible) == [true, false])
        #expect(defaultRows[1].defaultValue == .choice("solid"))
    }

    @Test func radiusCornerOrderAndLinking() throws {
        var value = try #require(PartPackageFrameworkRadiusControl.defaultValue(.object([
            "topLeft": .string("xs"), "topRight": .string("sm"),
            "bottomLeft": .string("md"), "bottomRight": .string("lg")
        ])))
        guard case .object(let output) = PartPackageFrameworkRadiusControl.resolved(value, framework: .standard) else { Issue.record("Missing output"); return }
        #expect(output["css"] == .string("var(--foundry-border-radius-xs) var(--foundry-border-radius-sm) var(--foundry-border-radius-lg) var(--foundry-border-radius-md)"))
        #expect(output["topLeft"] == .string("var(--foundry-border-radius-xs)"))
        #expect(output["units"] == .object(["topLeft": .string("px"), "topRight": .string("px"), "bottomLeft": .string("px"), "bottomRight": .string("px")]))
        #expect(FrameworkRadiusValue.Edge.allCases.map(\.title) == ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
        value.togglePair(using: .bottom)
        #expect(value.value(for: .bottom).token == "xs")
        #expect(value.value(for: .left).token == "md")
        value.togglePair(using: .right)
        #expect(value.verticalLinked && value.horizontalLinked)
        // Completing the second link while the first is already on means every
        // corner is now tied together — the toggle cascades left's value across
        // all four, not just left/right.
        #expect(value.values.allSatisfy { $0.token == "md" })
        #expect(try JSONDecoder().decode(FrameworkRadiusValue.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func policiesValidateUnitsAndTokens() throws {
        for invalid: PartPackageValue in [.string("auto"), .string("3xs"), .object(["value": .number(-1), "unit": .string("px")])] {
            #expect(PartPackageFrameworkBorderWidthControl.defaultValue(invalid) == nil)
            #expect(PartPackageFrameworkRadiusControl.defaultValue(invalid) == nil)
        }
        let percent: PartPackageValue = .object(["value": .number(50), "unit": .string("%")])
        #expect(PartPackageFrameworkBorderWidthControl.defaultValue(percent) == nil)
        #expect(PartPackageFrameworkRadiusControl.defaultValue(percent) != nil)
        #expect(PartPackageFrameworkBorderWidthControl.defaultValue(.string("full")) == nil)
        #expect(PartPackageFrameworkRadiusControl.defaultValue(.string("full")) != nil)
        #expect(PartPackageFrameworkRadiusControl.defaultValue(.object(["top": .string("sm"), "bottom": .string("sm"), "left": .string("sm"), "right": .string("sm")])) == nil)
        let width = try #require(PartPackageFrameworkBorderWidthControl.defaultValue(.string("sm")))
        var framework = Framework.standard
        framework.borderWidths.predefined[2].value = 3.5
        guard case .object(let output) = PartPackageFrameworkBorderWidthControl.resolved(width, framework: framework),
              case .object(let amounts) = output["values"] else { Issue.record("Missing output"); return }
        #expect(amounts["top"] == .number(3.5))
        #expect(try JSONDecoder().decode(FrameworkBorderWidthValue.self, from: JSONEncoder().encode(width)) == width)
        let radius = try #require(PartPackageFrameworkRadiusControl.defaultValue(percent))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(FrameworkBorderWidthValue.self, from: JSONEncoder().encode(radius)) }
    }
}
