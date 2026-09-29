import Foundation
import Testing
@testable import Foundry

/// Numbers that reach CSS and HTML are written for the browser, not for the
/// user's region: a dot for the decimal point and no grouping. A German
/// tester found `rgb(91 91 214 / 0,819)` being rejected as an invalid value.
struct OutputFormattingTests {
    @Test
    func colourOpacityUsesADecimalPointWhateverTheRegion() {
        #expect(PartTemplateRenderer.colorWithAlpha("#5B5BD6", alpha: 0.819) == "rgb(91 91 214 / 0.819)")
        #expect(PartTemplateRenderer.colorWithAlpha("#5B5BD6", alpha: 1) == "rgb(91 91 214 / 1)")
        #expect(PartTemplateRenderer.colorWithAlpha("#5B5BD6", alpha: 0.5) == "rgb(91 91 214 / 0.5)")
    }

    @Test
    func largeNumbersAreNeverGroupedInTemplateOutput() {
        let rendered = PartTemplateRenderer.render(
            #"<div style="width: {{ control.size }}px; opacity: {{ control.amount }}">{{ control.size }}</div>"#,
            context: .init(
                instanceID: UUID(), packageIdentifier: "com.example.numbers",
                properties: ["size": .number(1200), "amount": .number(0.25)], slots: [:]
            )
        )
        #expect(rendered.contains("width: 1200px"))
        #expect(rendered.contains("opacity: 0.25"))
        #expect(!rendered.contains("1,200"))
        #expect(!rendered.contains("1.200"))
        #expect(PartProperty.Value.number(1200).stringValue == "1200")
        #expect(PartProperty.Value.number(0.5).stringValue == "0.5")
    }
}
