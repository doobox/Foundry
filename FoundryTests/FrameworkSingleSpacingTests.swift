import Foundation
import Testing
@testable import Foundry

@Suite("Single framework spacing") @MainActor
struct FrameworkSingleSpacingTests {
    @Test func defaultsAndOutputs() throws {
        for raw: PartPackageValue in [.string("none"), .string("sm"), .object(["value": .number(2.5), "unit": .string("em")])] {
            let value = try #require(PartPackageSingleSpacingControl.defaultValue(raw))
            #expect(try JSONDecoder().decode(FrameworkSingleSpacingValue.self, from: JSONEncoder().encode(value)) == value)
        }
        let none = try #require(PartPackageSingleSpacingControl.defaultValue(.string("none")))
        #expect(PartPackageSingleSpacingControl.resolved(none, framework: .standard) == .object(["css": .string("0"), "value": .number(0), "unit": .string("")]))
        let custom = try #require(PartPackageSingleSpacingControl.defaultValue(.object(["value": .number(2.5), "unit": .string("em")])))
        #expect(PartPackageSingleSpacingControl.resolved(custom, framework: .standard) == .object(["css": .string("2.5em"), "value": .number(2.5), "unit": .string("em")]))
        for raw: PartPackageValue in [.string("auto"), .string("12px"), .object(["value": .number(-1), "unit": .string("px")]), .object(["top": .string("sm")])] {
            #expect(PartPackageSingleSpacingControl.defaultValue(raw) == nil)
        }
        var invalid = FrameworkSingleSpacingValue()
        invalid.selection.amount = -1
        #expect(throws: (any Error).self) { try JSONDecoder().decode(FrameworkSingleSpacingValue.self, from: JSONEncoder().encode(invalid)) }
    }
}
