import Testing
@testable import Foundry

struct BootstrapSpacingClassesTests {
    @Test func matchingEdgesUseShorthandWithoutFillingInheritedEdges() {
        var margin = ThemeMarginValue()
        #expect(BootstrapSpacingClasses.utilities(.themeMargin(margin)).isEmpty)
        margin.set(.init(token: "12"), for: .top)
        margin.set(.init(token: "12"), for: .bottom)
        #expect(BootstrapSpacingClasses.utilities(.themeMargin(margin)) == ["my-12"])
        margin.set(.init(token: "auto"), for: .left)
        margin.set(.init(token: "auto"), for: .right)
        #expect(BootstrapSpacingClasses.utilities(.themeMargin(margin)) == ["my-12", "mx-auto"])
        margin.setAll(.init(token: "0"))
        #expect(BootstrapSpacingClasses.utilities(.themeMargin(margin)) == ["m-0"])
        margin.setAll(.init(token: "auto"))
        #expect(BootstrapSpacingClasses.utilities(.themeMargin(margin)) == ["m-auto"])
    }

    @Test func paddingCombinesOnlyEqualExplicitTokens() {
        var padding = ThemePaddingValue()
        padding.setAll(.init(token: "5"))
        #expect(BootstrapSpacingClasses.utilities(.themePadding(padding)) == ["p-5"])
        padding.set(.init(token: "2"), for: .right)
        #expect(BootstrapSpacingClasses.utilities(.themePadding(padding)) == ["py-5", "ps-5", "pe-2"])
        padding.set(.init(token: "none"), for: .bottom)
        #expect(BootstrapSpacingClasses.utilities(.themePadding(padding)) == ["pt-5", "ps-5", "pe-2"])
        padding.setAll(.init(token: "auto"))
        #expect(BootstrapSpacingClasses.utilities(.themePadding(padding)).isEmpty)
        padding.setAll(.init(token: "5", isCustom: true, amount: 1, unit: "rem"))
        #expect(BootstrapSpacingClasses.utilities(.themePadding(padding)).isEmpty)
    }
}
