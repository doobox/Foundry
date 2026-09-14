import Foundation
import Testing
@testable import Foundry

@Suite("Theme border dimensions")
@MainActor
struct ThemeBorderDimensionTests {
    @Test func borderRowsPreserveHiddenStyleDefault() throws {
        let data = Data(#"{"type":"themeBorder","id":"border","responsive":true,"default":{"width":"sm","style":"dotted"}}"#.utf8)
        let property = try JSONDecoder().decode(PartPackageProperty.self, from: data)
        let rows = PartPackageThemeBorderControl.properties(property)
        #expect(rows.map(\.key.rawValue) == ["border.width", "border.style"])
        #expect(rows.map(\.isInspectorVisible) == [true, false])
        #expect(rows.map(\.isResponsive) == [true, false])
        #expect(rows.allSatisfy { $0.inspectorControlID == "border" })
        #expect(rows[1].defaultValue == .choice("dotted"))
        let defaults = try JSONDecoder().decode(PartPackageProperty.self, from: Data(#"{"type":"themeBorder","id":"border","default":{"width":"none"}}"#.utf8))
        let defaultRows = PartPackageThemeBorderControl.properties(defaults)
        #expect(defaultRows.map(\.isInspectorVisible) == [true, false])
        #expect(defaultRows[1].defaultValue == .choice("solid"))
    }

    @Test func radiusCornerOrderAndLinking() throws {
        var value = try #require(PartPackageThemeRadiusControl.defaultValue(.object([
            "topLeft": .string("xs"), "topRight": .string("sm"),
            "bottomLeft": .string("md"), "bottomRight": .string("lg")
        ])))
        guard case .object(let output) = PartPackageThemeRadiusControl.resolved(value, theme: .standard) else { Issue.record("Missing output"); return }
        #expect(output["css"] == .string("var(--foundry-border-radius-xs) var(--foundry-border-radius-sm) var(--foundry-border-radius-lg) var(--foundry-border-radius-md)"))
        #expect(output["topLeft"] == .string("var(--foundry-border-radius-xs)"))
        #expect(output["units"] == .object(["topLeft": .string("px"), "topRight": .string("px"), "bottomLeft": .string("px"), "bottomRight": .string("px")]))
        #expect(ThemeRadiusValue.Edge.allCases.map(\.title) == ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
        value.togglePair(using: .bottom)
        #expect(value.value(for: .bottom).token == "xs")
        #expect(value.value(for: .left).token == "md")
        value.togglePair(using: .right)
        #expect(value.linked)
        #expect(value.values.allSatisfy { $0.token == "xs" })
        #expect(try JSONDecoder().decode(ThemeRadiusValue.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func policiesValidateUnitsAndTokens() throws {
        for invalid: PartPackageValue in [.string("auto"), .string("3xs"), .object(["value": .number(-1), "unit": .string("px")])] {
            #expect(PartPackageThemeBorderWidthControl.defaultValue(invalid) == nil)
            #expect(PartPackageThemeRadiusControl.defaultValue(invalid) == nil)
        }
        let percent: PartPackageValue = .object(["value": .number(50), "unit": .string("%")])
        #expect(PartPackageThemeBorderWidthControl.defaultValue(percent) == nil)
        #expect(PartPackageThemeRadiusControl.defaultValue(percent) != nil)
        #expect(PartPackageThemeBorderWidthControl.defaultValue(.string("full")) == nil)
        #expect(PartPackageThemeRadiusControl.defaultValue(.string("full")) != nil)
        #expect(PartPackageThemeRadiusControl.defaultValue(.object(["top": .string("sm"), "bottom": .string("sm"), "left": .string("sm"), "right": .string("sm")])) == nil)
        let width = try #require(PartPackageThemeBorderWidthControl.defaultValue(.string("sm")))
        var theme = Theme.standard
        theme.borderWidths.predefined[2].value = 3.5
        guard case .object(let output) = PartPackageThemeBorderWidthControl.resolved(width, theme: theme),
              case .object(let amounts) = output["values"] else { Issue.record("Missing output"); return }
        #expect(amounts["top"] == .number(3.5))
        #expect(try JSONDecoder().decode(ThemeBorderWidthValue.self, from: JSONEncoder().encode(width)) == width)
        let radius = try #require(PartPackageThemeRadiusControl.defaultValue(percent))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ThemeBorderWidthValue.self, from: JSONEncoder().encode(radius)) }
    }
}
