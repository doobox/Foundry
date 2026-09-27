import Foundation
import Testing
@testable import Foundry

struct SizingControlGroupTests {
    private func css(_ values: [String: PartPackageValue], omit: [String] = []) throws -> String {
        let manifest: [String: Any] = [
            "minimumAPIVersion": 1, "id": "test.sizing", "title": "Sizing", "version": "1.0.0",
            "inspector": [["type": "sizing", "id": "sizing", "excludeControls": omit]],
            "templates": ["html": "part.html"]
        ]
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: JSONSerialization.data(withJSONObject: manifest))
        var resolved = Dictionary(uniqueKeysWithValues: values.map { ("sizing." + $0.key, $0.value) })
        PartPackageControlGroupCSSResolver.resolve(&resolved, properties: decoded.resolvedProperties)
        return try #require(resolved["sizing.css"]?.stringValue)
    }

    // Published breakpoint rules accumulate. Declarations omitted by the wider
    // breakpoint remain active, so examine the combined cascade, not just output.
    private func cascade(_ blocks: String...) -> [String: String] {
        var result: [String: String] = [:]
        for block in blocks {
            for declaration in block.split(separator: ";") {
                let pair = declaration.split(separator: ":", maxSplits: 1)
                if pair.count == 2 {
                    result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return result
    }

    @Test(arguments: ["auto", "custom", "viewport"])
    func leavingFillResetsGrowthAndMaximumHeight(mode: String) throws {
        let narrow = try css(["heightMode": .string("fill"), "maxHeight": .string("200px")])
        let wide = try css(["heightMode": .string(mode), "customHeight": .number(400), "maxHeight": .string("none")])
        let computed = cascade(narrow, wide)
        #expect(computed["flex-grow"] == "0")
        #expect(computed["max-height"] == "none")
    }

    @Test(arguments: ["200px", "800px"])
    func maximumCannotReplaceCustomWidth(maximum: String) throws {
        let output = try css(["widthMode": .string("custom"), "customWidth": .number(400), "maxWidth": .string(maximum)])
        #expect(cascade(output)["max-width"] == "min(100%, 400px, \(maximum))")
    }

    @Test
    func viewportHonoursMinimumAndCanReturnToContentHeight() throws {
        let viewport = try css(["heightMode": .string("viewport"), "minHeight": .string("1200px")])
        #expect(cascade(viewport)["min-height"] == "max(100svh, 1200px)")
        let content = try css(["heightMode": .string("auto"), "minHeight": .string("0")])
        #expect(cascade(viewport, content)["min-height"] == "0")
    }

    @Test
    func heightModeResetsItsOwnMinimumWhenMinimumControlIsOmitted() throws {
        let viewport = try css(["heightMode": .string("viewport")], omit: ["minHeight"])
        #expect(cascade(viewport)["min-height"] == "max(100svh, 0px)")
        let content = try css(["heightMode": .string("auto")], omit: ["minHeight"])
        #expect(cascade(viewport, content)["min-height"] == "0")
    }

    @Test
    func constraintsOnlyGroupComposesAndClearsLimits() throws {
        let omit = ["widthMode", "customWidth", "heightMode", "customHeight"]
        let limited = try css(["maxWidth": .string("400px"), "maxHeight": .string("200px")], omit: omit)
        let unlimited = try css(["maxWidth": .string("none"), "maxHeight": .string("none")], omit: omit)
        let computed = cascade(limited, unlimited)
        #expect(computed["max-width"] == "none")
        #expect(computed["max-height"] == "none")
        #expect(computed["width"] == nil)
        #expect(computed["flex-grow"] == nil)
    }
}
