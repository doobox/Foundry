import Foundation
import Testing
@testable import Foundry

@Suite("Theme padding")
@MainActor
struct ThemePaddingTests {
    @Test func singleSpacingSwitchesBetweenThemeAndCustomModes() {
        var value = ThemeSingleSpacingValue()
        #expect(value.selection.token == "sm")
        #expect(!value.selection.isCustom)
        value.setUsesThemeTokens(false, theme: .standard)
        #expect(value.selection.isCustom)
        // Custom starts with the selected token's own amount: SM is 4 × 0.25rem.
        #expect(value.selection.amount == 1)
        #expect(value.selection.unit == "rem")
        value.selection.amount = 1.6
        value.setUsesThemeTokens(true, theme: .standard)
        #expect(!value.selection.isCustom)
        // 1.6rem snaps to the nearest theme value: MD at 1.5rem.
        #expect(value.selection.token == "md")
    }

    @Test func defaultsAndResolution() throws {
        for invalid: PartPackageValue in [.string("auto"), .string("10px"), .number(-1),
            .object(["value": .number(-1), "unit": .string("px")]),
            .object(["value": .number(1), "unit": .string("auto")]),
            .object(["top": .string("sm")])] {
            #expect(PartPackageThemePaddingControl.defaultValue(invalid) == nil)
        }
        let initial = try #require(PartPackageThemePaddingControl.defaultValue(.object([
            "top": .string("sm"), "right": .string("none"), "bottom": .string("lg"),
            "left": .object(["value": .number(2), "unit": .string("rem")])
        ])))
        #expect(!initial.verticalLinked && !initial.horizontalLinked)
        #expect(try JSONDecoder().decode(ThemePaddingValue.self, from: JSONEncoder().encode(initial)) == initial)
        guard case .object(let output) = PartPackageThemePaddingControl.resolved(initial, theme: .standard) else { return }
        #expect(output["css"] == .string("var(--foundry-space-sm) 0 var(--foundry-space-lg) 2.0rem"))
        #expect(output["values"] == .object(["top": .number(1), "right": .number(0), "bottom": .number(2), "left": .number(2)]))
        #expect(output["units"] == .object(["top": .string("rem"), "right": .string(""), "bottom": .string("rem"), "left": .string("rem")]))
    }

    @Test func numericValuesFollowThemeAndPreserveCustomUnits() throws {
        var theme = Theme.standard
        theme.spacing.small = 7
        var padding = ThemePaddingValue()
        for unit in PartPackageThemePaddingControl.units {
            var edge = ThemePaddingValue.EdgeValue()
            edge.isCustom = true
            edge.amount = 2.5
            edge.unit = unit
            padding.unlinkAll()
            padding.set(edge, for: .left)
            guard case .object(let output) = PartPackageThemePaddingControl.resolved(padding, theme: theme),
                  case .object(let amounts) = output["values"],
                  case .object(let units) = output["units"] else { Issue.record("Missing numeric output"); return }
            #expect(amounts["top"] == .number(1.75))
            #expect(units["top"] == .string("rem"))
            #expect(amounts["left"] == .number(2.5))
            #expect(units["left"] == .string(unit))
        }
        var missing = ThemePaddingValue.EdgeValue()
        missing.token = "custom:" + UUID().uuidString
        padding.set(missing, for: .right)
        guard case .object(let output) = PartPackageThemePaddingControl.resolved(padding, theme: theme),
              case .object(let amounts) = output["values"],
              case .object(let units) = output["units"] else { Issue.record("Missing numeric output"); return }
        #expect(amounts["right"] == .number(0))
        #expect(units["right"] == .string(""))
    }

    @Test func malformedStoredPaddingIsRejected() throws {
        let data = try JSONEncoder().encode(ThemePaddingValue())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["values"] = []
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ThemePaddingValue.self, from: invalid) }
    }
    @Test func pairLinkUsesFirstEdgeAndOnlyUpdatesPartner() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        var padding = state.value(for: .bottom)
        padding.token = "lg"
        state.set(padding, for: .bottom)
        state.togglePair(using: .bottom)
        #expect(state.value(for: .top).token == "sm")
        #expect(state.value(for: .bottom).token == "sm")
        #expect(state.value(for: .left).token == "sm")
        padding.token = "xl"
        state.set(padding, for: .top)
        #expect(state.value(for: .bottom) == padding)
        state.togglePair(using: .top)
        #expect(!state.isPairLinked(.bottom))
        #expect(state.value(for: .bottom) == padding)
    }

    @Test func togglingTheSecondPairCascadesToAllFourEdges() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        state.togglePair(using: .top)
        var customTop = state.value(for: .top)
        customTop.token = "xl"
        state.set(customTop, for: .top)
        state.togglePair(using: .right)
        #expect(state.verticalLinked && state.horizontalLinked)
        // Completing the second link while the first is already on means every
        // edge is now tied together — the toggle cascades its axis's leading
        // edge (left, for horizontal) across all four, not just its own pair,
        // discarding the vertical pair's custom value in the process.
        #expect(state.values.allSatisfy { $0.token == "sm" })
    }

    @Test func togglingTheSecondPairCascadesToAllFourEdgesHorizontalFirst() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        state.togglePair(using: .left)
        var customLeft = state.value(for: .left)
        customLeft.token = "xl"
        state.set(customLeft, for: .left)
        state.togglePair(using: .bottom)
        #expect(state.verticalLinked && state.horizontalLinked)
        #expect(state.values.allSatisfy { $0.token == "sm" })
    }

    @Test func unlinkingOnePairFromAllRetainsOtherPair() {
        var state = ThemePaddingValue()
        state.togglePair(using: .bottom)
        #expect(!state.isPairLinked(.top))
        #expect(state.isPairLinked(.left))
        #expect(state.allEqual)
    }

    @Test func linkedEditsUpdateEveryEdge() {
        var state = ThemePaddingValue()
        var padding = state.value(for: .top)
        padding.token = "lg"
        state.set(padding, for: .top)
        #expect(state.values.allSatisfy { $0.token == "lg" })
        state.unlinkAll()
        #expect(state.values.allSatisfy { $0.token == "lg" })
    }

    @Test func linkAllUsesTop() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        var custom = state.value(for: .right)
        custom.isCustom = true
        custom.amount = 23
        custom.unit = "px"
        state.set(custom, for: .right)
        #expect(!state.allEqual)
        #expect(!state.value(for: .top).isCustom)
        #expect(state.value(for: .right).token == "sm")
        state.linkAll()
        #expect(state.verticalLinked && state.horizontalLinked)
        #expect(state.values.allSatisfy { $0 == ThemePaddingValue.EdgeValue() })
    }

    @Test func horizontalPairUsesLeftEvenWhenRightIsClicked() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        var left = state.value(for: .left)
        left.token = "xl"
        state.set(left, for: .left)
        state.togglePair(using: .right)
        #expect(state.value(for: .right) == left)
        #expect(state.value(for: .top).token == "sm")
    }
}
