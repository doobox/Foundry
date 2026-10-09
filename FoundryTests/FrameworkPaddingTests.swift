import Foundation
import Testing
@testable import Foundry

@Suite("Framework padding")
@MainActor
struct FrameworkPaddingTests {
    @Test func singleSpacingSwitchesBetweenFrameworkAndCustomModes() {
        var value = FrameworkSingleSpacingValue()
        #expect(value.selection.token == "sm")
        #expect(!value.selection.isCustom)
        value.setUsesFrameworkTokens(false)
        #expect(value.selection.isCustom)
        // Each mode keeps its own state: custom starts untouched at 0px.
        #expect(value.selection.amount == 0)
        #expect(value.selection.unit == "px")
        value.selection.amount = 1.6
        value.setUsesFrameworkTokens(true)
        #expect(!value.selection.isCustom)
        // Nothing snaps: the token survives the round trip untouched…
        #expect(value.selection.token == "sm")
        value.setUsesFrameworkTokens(false)
        // …and so does the custom amount.
        #expect(value.selection.amount == 1.6)
    }

    @Test func defaultsAndResolution() throws {
        for invalid: PartPackageValue in [.string("auto"), .string("10px"), .number(-1),
            .object(["value": .number(-1), "unit": .string("px")]),
            .object(["value": .number(1), "unit": .string("auto")]),
            .object(["top": .string("sm")])] {
            #expect(PartPackageFrameworkPaddingControl.defaultValue(invalid) == nil)
        }
        let initial = try #require(PartPackageFrameworkPaddingControl.defaultValue(.object([
            "top": .string("sm"), "right": .string("none"), "bottom": .string("lg"),
            "left": .object(["value": .number(2), "unit": .string("rem")])
        ])))
        #expect(!initial.verticalLinked && !initial.horizontalLinked)
        #expect(try JSONDecoder().decode(FrameworkPaddingValue.self, from: JSONEncoder().encode(initial)) == initial)
        guard case .object(let output) = PartPackageFrameworkPaddingControl.resolved(initial, framework: .standard) else { return }
        #expect(output["css"] == .string("var(--foundry-space-sm) 0 var(--foundry-space-lg) 2.0rem"))
        #expect(output["values"] == .object(["top": .number(1), "right": .number(0), "bottom": .number(2), "left": .number(2)]))
        #expect(output["units"] == .object(["top": .string("rem"), "right": .string(""), "bottom": .string("rem"), "left": .string("rem")]))
    }

    @Test func numericValuesFollowFrameworkAndPreserveCustomUnits() throws {
        var framework = Framework.standard
        framework.spacing.custom = [.init(name: "section", value: 1.75)]
        var padding = FrameworkPaddingValue()
        padding.setAll(.init(token: "section"))
        for unit in PartPackageFrameworkPaddingControl.units {
            var edge = FrameworkPaddingValue.EdgeValue()
            edge.isCustom = true
            edge.amount = 2.5
            edge.unit = unit
            padding.unlinkAll()
            padding.set(edge, for: .left)
            guard case .object(let output) = PartPackageFrameworkPaddingControl.resolved(padding, framework: framework),
                  case .object(let amounts) = output["values"],
                  case .object(let units) = output["units"] else { Issue.record("Missing numeric output"); return }
            #expect(amounts["top"] == .number(1.75))
            #expect(units["top"] == .string("rem"))
            #expect(amounts["left"] == .number(2.5))
            #expect(units["left"] == .string(unit))
        }
        var missing = FrameworkPaddingValue.EdgeValue()
        missing.token = "custom:" + UUID().uuidString
        padding.set(missing, for: .right)
        guard case .object(let output) = PartPackageFrameworkPaddingControl.resolved(padding, framework: framework),
              case .object(let amounts) = output["values"],
              case .object(let units) = output["units"] else { Issue.record("Missing numeric output"); return }
        #expect(amounts["right"] == .number(0))
        #expect(units["right"] == .string(""))
    }

    @Test func malformedStoredPaddingIsRejected() throws {
        let data = try JSONEncoder().encode(FrameworkPaddingValue())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["values"] = []
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(FrameworkPaddingValue.self, from: invalid) }
    }
    @Test func pairLinkUsesFirstEdgeAndOnlyUpdatesPartner() {
        var state = FrameworkPaddingValue()
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

    @Test func togglingTheSecondPairLeavesTheOtherPairUntouched() {
        var state = FrameworkPaddingValue()
        state.togglePair(using: .top)
        var customTop = state.value(for: .top)
        customTop.token = "xl"
        state.set(customTop, for: .top)
        state.togglePair(using: .right)
        #expect(state.verticalLinked && state.horizontalLinked)
        // Pairs stay independent even with both links on: the horizontal link
        // syncs left/right only, and the vertical pair keeps its value.
        #expect(state.value(for: .top).token == "xl")
        #expect(state.value(for: .bottom).token == "xl")
        #expect(state.value(for: .left).token == "sm")
        #expect(state.value(for: .right).token == "sm")
    }

    @Test func togglingTheSecondPairLeavesTheOtherPairUntouchedHorizontalFirst() {
        var state = FrameworkPaddingValue()
        state.togglePair(using: .left)
        var customLeft = state.value(for: .left)
        customLeft.token = "xl"
        state.set(customLeft, for: .left)
        state.togglePair(using: .bottom)
        #expect(state.verticalLinked && state.horizontalLinked)
        #expect(state.value(for: .left).token == "xl")
        #expect(state.value(for: .right).token == "xl")
        #expect(state.value(for: .top).token == "sm")
        #expect(state.value(for: .bottom).token == "sm")
    }

    @Test func defaultsStartUnlinkedAndTogglingLinksOneAxis() {
        var state = FrameworkPaddingValue()
        #expect(!state.isPairLinked(.top))
        #expect(!state.isPairLinked(.left))
        state.togglePair(using: .bottom)
        #expect(state.isPairLinked(.top))
        #expect(!state.isPairLinked(.left))
    }

    @Test func pairLinkedEditsUpdateOnlyTheirAxis() {
        var state = FrameworkPaddingValue()
        state.togglePair(using: .top)
        state.togglePair(using: .left)
        var padding = state.value(for: .top)
        padding.token = "lg"
        state.set(padding, for: .top)
        #expect(state.value(for: .bottom).token == "lg")
        #expect(state.value(for: .left).token == "sm")
        #expect(state.value(for: .right).token == "sm")
        state.unlinkAll()
        #expect(state.value(for: .bottom).token == "lg")
    }

    @Test func linkAllUsesTop() {
        var state = FrameworkPaddingValue()
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
        #expect(state.values.allSatisfy { $0 == FrameworkPaddingValue.EdgeValue() })
    }

    @Test func horizontalPairUsesLeftEvenWhenRightIsClicked() {
        var state = FrameworkPaddingValue()
        state.unlinkAll()
        var left = state.value(for: .left)
        left.token = "xl"
        state.set(left, for: .left)
        state.togglePair(using: .right)
        #expect(state.value(for: .right) == left)
        #expect(state.value(for: .top).token == "sm")
    }
}
