import Testing
@testable import Foundry

struct TypographyControlGroupTests {
    @Test
    func composesReusableTextCSS() throws {
        let group = PartPackageControlGroup(type: .typography, id: "titleTypography")
        var values: [String: PartPackageValue] = [
            "titleTypography.font.family": .string("var(--foundry-font-heading)"),
            "titleTypography.font.weight": .number(700),
            "titleTypography.font.style": .string("normal"),
            "titleTypography.font.size": .string("var(--foundry-font-size-base)"),
            "titleTypography.font.size.lineHeight": .string("var(--foundry-line-height-base)"),
            "titleTypography.customColorEnabled": .boolean(false),
            "titleTypography.textColor": .string("#123456"),
            "titleTypography.textAlignment": .string("center"),
            "titleTypography.textDecoration": .string("underline"),
            "titleTypography.textTransform": .string("uppercase")
        ]

        PartPackageControlGroupCSSResolver.resolve(&values, properties: group.properties)
        let css = try #require(values["titleTypography.css"]?.stringValue)
        #expect(css.contains("font-family: var(--foundry-font-heading);"))
        #expect(css.contains("font-weight: 700;"))
        #expect(css.contains("font-size: var(--foundry-font-size-base);"))
        #expect(css.contains("line-height: var(--foundry-line-height-base);"))
        #expect(css.contains("color: inherit;"))
        #expect(css.contains("text-align: center;"))
        #expect(css.contains("text-decoration-line: underline;"))
        #expect(css.contains("text-transform: uppercase;"))
    }
}
