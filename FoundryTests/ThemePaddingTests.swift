import Foundation
import Testing
@testable import Foundry

@Suite("Theme padding")
@MainActor
struct ThemePaddingTests {
    @Test func singleSpacingSwitchesBetweenThemeAndCustomModes() {
        var value = ThemeSingleSpacingValue()
        #expect(value.selection.token == "none")
        #expect(!value.selection.isCustom)
        value.setUsesThemeTokens(false)
        #expect(value.selection.isCustom)
        // Each mode keeps its own state: custom starts untouched at 0px.
        #expect(value.selection.amount == 0)
        #expect(value.selection.unit == "px")
        value.selection.amount = 1.6
        value.setUsesThemeTokens(true)
        #expect(!value.selection.isCustom)
        // Nothing snaps: the token survives the round trip untouched…
        #expect(value.selection.token == "none")
        value.setUsesThemeTokens(false)
        // …and so does the custom amount.
        #expect(value.selection.amount == 1.6)
    }

    @Test func defaultsAndResolution() throws {
        for invalid: PartPackageValue in [.string("auto"), .string("10px"), .number(-1),
            .object(["value": .number(-1), "unit": .string("px")]),
            .object(["value": .number(1), "unit": .string("auto")]),
            .object(["top": .string("3")])] {
            #expect(PartPackageThemePaddingControl.defaultValue(invalid) == nil)
        }
        let initial = try #require(PartPackageThemePaddingControl.defaultValue(.object([
            "top": .string("3"), "right": .string("none"), "bottom": .string("7"),
            "left": .object(["value": .number(2), "unit": .string("rem")])
        ])))
        #expect(!initial.verticalLinked && !initial.horizontalLinked)
        #expect(try JSONDecoder().decode(ThemePaddingValue.self, from: JSONEncoder().encode(initial)) == initial)
        guard case .object(let output) = PartPackageThemePaddingControl.resolved(initial, theme: .standard) else { return }
        #expect(output["css"] == .string("var(--bs-spacer-3) 0 var(--bs-spacer-7) 2.0rem"))
        #expect(output["values"] == .object(["top": .number(0.5), "right": .number(0), "bottom": .number(1.5), "left": .number(2)]))
        #expect(output["units"] == .object(["top": .string("rem"), "right": .string(""), "bottom": .string("rem"), "left": .string("rem")]))
    }

    @Test func numericValuesFollowThemeAndPreserveCustomUnits() throws {
        var theme = Theme.standard
        theme.spacing.custom = [.init(name: "section", value: 1.75)]
        var padding = ThemePaddingValue()
        padding.setAll(.init(token: "section"))
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
        padding.token = "7"
        state.set(padding, for: .bottom)
        state.togglePair(using: .bottom)
        #expect(state.value(for: .top).token == "none")
        #expect(state.value(for: .bottom).token == "none")
        #expect(state.value(for: .left).token == "none")
        padding.token = "9"
        state.set(padding, for: .top)
        #expect(state.value(for: .bottom) == padding)
        state.togglePair(using: .top)
        #expect(!state.isPairLinked(.bottom))
        #expect(state.value(for: .bottom) == padding)
    }

    @Test func togglingTheSecondPairLeavesTheOtherPairUntouched() {
        var state = ThemePaddingValue()
        state.togglePair(using: .top)
        var customTop = state.value(for: .top)
        customTop.token = "9"
        state.set(customTop, for: .top)
        state.togglePair(using: .right)
        #expect(state.verticalLinked && state.horizontalLinked)
        // Pairs stay independent even with both links on: the horizontal link
        // syncs left/right only, and the vertical pair keeps its value.
        #expect(state.value(for: .top).token == "9")
        #expect(state.value(for: .bottom).token == "9")
        #expect(state.value(for: .left).token == "none")
        #expect(state.value(for: .right).token == "none")
    }

    @Test func togglingTheSecondPairLeavesTheOtherPairUntouchedHorizontalFirst() {
        var state = ThemePaddingValue()
        state.togglePair(using: .left)
        var customLeft = state.value(for: .left)
        customLeft.token = "9"
        state.set(customLeft, for: .left)
        state.togglePair(using: .bottom)
        #expect(state.verticalLinked && state.horizontalLinked)
        #expect(state.value(for: .left).token == "9")
        #expect(state.value(for: .right).token == "9")
        #expect(state.value(for: .top).token == "none")
        #expect(state.value(for: .bottom).token == "none")
    }

    @Test func defaultsStartUnlinkedAndTogglingLinksOneAxis() {
        var state = ThemePaddingValue()
        #expect(!state.isPairLinked(.top))
        #expect(!state.isPairLinked(.left))
        state.togglePair(using: .bottom)
        #expect(state.isPairLinked(.top))
        #expect(!state.isPairLinked(.left))
    }

    @Test func pairLinkedEditsUpdateOnlyTheirAxis() {
        var state = ThemePaddingValue()
        state.togglePair(using: .top)
        state.togglePair(using: .left)
        var padding = state.value(for: .top)
        padding.token = "7"
        state.set(padding, for: .top)
        #expect(state.value(for: .bottom).token == "7")
        #expect(state.value(for: .left).token == "none")
        #expect(state.value(for: .right).token == "none")
        state.unlinkAll()
        #expect(state.value(for: .bottom).token == "7")
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
        #expect(state.value(for: .right).token == "none")
        state.linkAll()
        #expect(state.verticalLinked && state.horizontalLinked)
        #expect(state.values.allSatisfy { $0 == ThemePaddingValue.EdgeValue() })
    }

    @Test func horizontalPairUsesLeftEvenWhenRightIsClicked() {
        var state = ThemePaddingValue()
        state.unlinkAll()
        var left = state.value(for: .left)
        left.token = "9"
        state.set(left, for: .left)
        state.togglePair(using: .right)
        #expect(state.value(for: .right) == left)
        #expect(state.value(for: .top).token == "none")
    }
}
