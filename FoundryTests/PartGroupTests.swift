import Testing
@testable import Foundry

/// The Parts-panel headings a manifest's `group` may name.
struct PartGroupTests {
    @Test
    func everyDocumentedGroupResolvesAndOthersFallBack() {
        let documented = [
            "Accessibility", "Animation", "CMS", "Content", "Dynamic", "Ecommerce", "Forms",
            "Interactive", "Layout", "Media", "Navigation", "Security", "SEO", "Utility", "Other"
        ]
        #expect(PartPackageGroup.allCases.map(\.rawValue) == documented)
        for name in documented {
            #expect(PartPackageGroup.resolve(name).rawValue == name)
            #expect(PartPackageGroup.resolve(name.lowercased()).rawValue == name)
        }
        #expect(PartPackageGroup.resolve("Widgets") == .other)
        #expect(PartPackageGroup.resolve("") == .other)
        #expect(PartPackageGroup.allCases.allSatisfy { !$0.summary.isEmpty })
    }
}
