import Testing
@testable import Foundry

struct SizingCustomDefaultsTests {
    @Test(arguments: ["sizing", "dimensions"])
    func maximumsStartUnconstrainedWithUsefulCustomPixels(namespace: String) throws {
        let group = PartPackageControlGroup(type: .sizing, id: namespace)
        for (id, amount) in [("maxWidth", 1200.0), ("maxHeight", 800.0)] {
            let property = try #require(group.properties.first { $0.id == namespace + "." + id })
            guard case .frameworkSpacing(var spacing) = PartPackageAdapter.defaultValue(for: property) else {
                Issue.record("Expected a framework spacing default")
                continue
            }
            #expect(spacing.selection.isNone)
            #expect(spacing.selection.amount == amount)
            #expect(spacing.selection.unit == "px")
            spacing.setUsesFrameworkTokens(false)
            #expect(spacing.selection.isCustom)
            #expect(spacing.selection.amount == amount)
            spacing.selection.amount = 640
            spacing.selection.unit = "rem"
            spacing.setUsesFrameworkTokens(true)
            spacing.setUsesFrameworkTokens(false)
            #expect(spacing.selection.amount == 640)
            #expect(spacing.selection.unit == "rem")
        }
    }

    @Test func explicitCustomDefaultsArePreserved() throws {
        let group = PartPackageControlGroup(type: .sizing, id: "sizing", defaults: [
            "maxWidth": .object(["value": .number(90), "unit": .string("%")])
        ])
        let property = try #require(group.properties.first { $0.id == "sizing.maxWidth" })
        guard case .frameworkSpacing(let spacing) = PartPackageAdapter.defaultValue(for: property) else {
            Issue.record("Expected a framework spacing default")
            return
        }
        #expect(spacing.selection.isCustom)
        #expect(spacing.selection.amount == 90)
        #expect(spacing.selection.unit == "%")
    }
}
