import Foundation
import Testing
@testable import Foundry

@Suite("Framework margin")
@MainActor
struct FrameworkMarginTests {
    @Test func autoNegativeAndPersistence() throws {
        let value = try #require(PartPackageFrameworkMarginControl.defaultValue(.object([
            "top": .object(["value": .number(-2), "unit": .string("rem")]),
            "right": .string("auto"), "bottom": .string("none"), "left": .string("sm")
        ])))
        #expect(try JSONDecoder().decode(FrameworkMarginValue.self, from: JSONEncoder().encode(value)) == value)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(FrameworkPaddingValue.self, from: JSONEncoder().encode(value)) }
        guard case .object(let result) = PartPackageFrameworkMarginControl.resolved(value, framework: .standard),
              case .object(let amounts) = result["values"],
              case .object(let units) = result["units"] else { Issue.record("Missing output"); return }
        #expect(result["css"] == .string("-2.0rem auto 0 var(--foundry-space-sm)"))
        #expect(amounts["top"] == .number(-2))
        #expect(amounts["right"] == nil)
        #expect(units["right"] == .string(""))
        #expect(PartPackageFrameworkPaddingControl.defaultValue(.string("auto")) == nil)
        #expect(PartPackageFrameworkMarginControl.defaultValue(.string("auto")).map { $0.verticalLinked && $0.horizontalLinked } == true)
        #expect(PartPackageFrameworkMarginControl.defaultValue(.string("none")).map { $0.verticalLinked && $0.horizontalLinked } == true)
        #expect(PartPackageFrameworkMarginControl.defaultValue(.object(["value": .number(1), "unit": .string("vh")])) == nil)
    }
    @Test func linkingAutoUsesFirstEdge() throws {
        var value = try #require(PartPackageFrameworkMarginControl.defaultValue(.string("auto")))
        value.unlinkAll()
        value.togglePair(using: .bottom)
        #expect(value.value(for: .bottom).token == "auto")
        value.togglePair(using: .right)
        #expect(value.verticalLinked && value.horizontalLinked)
        #expect(value.values.allSatisfy { $0.token == "auto" })
    }
}
