import Foundation
import Testing
@testable import Foundry

struct TransitionsControlGroupTests {
    private func resolved(_ overrides: [String: PartPackageValue] = [:], namespace: String = "motion") -> String {
        let group = PartPackageControlGroup(type: .transitions, id: namespace)
        var values = Dictionary(uniqueKeysWithValues: group.properties.map { ($0.id, $0.defaultValue) })
        for (key, value) in overrides { values[namespace + "." + key] = value }
        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        return values[namespace + ".css"]?.stringValue ?? ""
    }

    @Test func disabledExplicitlyClearsEarlierTransitions() {
        #expect(resolved() == "transition: none;")
    }

    @Test func enabledUsesMillisecondsAndReducedMotionForDurationAndDelay() {
        let css = resolved(["transitionsEnabled": .boolean(true),
                            "transitionDuration": .number(450), "transitionDelay": .number(120)])
        #expect(css.contains("transition-property: all;"))
        #expect(css.contains("calc(450ms * var(--foundry-transition-motion, 1))"))
        #expect(css.contains("calc(120ms * var(--foundry-transition-motion, 1))"))
        #expect(css.contains("transition-timing-function: ease-in-out;"))
    }

    @Test(arguments: ["colors", "opacity", "transform", "shadow", "border", "size", "filters"])
    func scopesResolveToCSSProperties(scope: String) {
        let css = resolved(["transitionsEnabled": .boolean(true), "transitionProperty": .string(scope)])
        #expect(css.contains("transition-property: all;") == false)
        #expect(css.contains("transition-property:"))
    }

    @Test func invalidValuesAreBoundedAndCannotInjectCSS() {
        let css = resolved(["transitionsEnabled": .boolean(true),
                            "transitionDuration": .number(-50), "transitionDelay": .number(20000),
                            "transitionFunction": .string("bad; color: red"),
                            "transitionProperty": .string("bad; color: red")])
        #expect(css.contains("calc(0ms *"))
        #expect(css.contains("calc(10000ms *"))
        #expect(css.contains("bad") == false)
    }

    @Test func controlsAreResponsiveAndEnableUsesSwitch() throws {
        let group = PartPackageControlGroup(type: .transitions, id: "motion")
        #expect(group.properties.allSatisfy { $0.responsive })
        let enable = try #require(group.properties.first { $0.id == "motion.transitionsEnabled" })
        #expect(enable.control.presentation?.rawValue == "switch")
        #expect(PartPackageControlGroupCSSResolver.composedNamespaces(for: group.properties) == ["motion"])
    }
}
