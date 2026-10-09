import Testing
@testable import Foundry

struct SizingCustomDefaultsTests {
    @Test(arguments: ["sizing", "dimensions"])
    func limitsStartInherited(namespace: String) throws {
        let group = PartPackageControlGroup(type: .sizing, id: namespace)
        for id in ["minWidth", "maxWidth", "minHeight", "maxHeight"] {
            let property = try #require(group.properties.first { $0.id == namespace + "." + id })
            #expect(property.defaultValue == .string("none"))
            #expect(property.responsive == false)
        }
    }

    @Test func nativeDefaultsAndSubsetsArePreserved() throws {
        let group = PartPackageControlGroup(type: .sizing, id: "sizing",
            defaults: ["width": .string("w-50")], allowedOptions: ["width": ["w-25", "w-50"]])
        let property = try #require(group.properties.first { $0.id == "sizing.width" })
        #expect(property.defaultValue == .string("w-50"))
        #expect(property.control.options?.map(\.value) == ["w-25", "w-50"])
    }
}
