import Foundation
import Testing
import WebKit
@testable import Foundry

struct SpaceControlTests {
    @Test func savedExtendedPresetsBecomeCustomRemLengths() {
        for step in 13...24 {
            let fromClass = PartSpaceValue(.choice("space-y-\(step)"))
            let fromPreset = PartSpaceValue(.object(["custom": .boolean(false), "preset": .string(String(step)), "value": .number(16), "unit": .string("px")]))
            #expect(fromClass.isCustom)
            #expect(fromClass.unit == "rem")
            #expect(fromClass.amount == SpacingTokens.legacyAmount(String(step)))
            #expect(fromPreset == fromClass)
        }
    }
    @Test func selectionsSurviveModeChangesAndSaving() throws {
        var value = PartSpaceValue(.choice("space-y-12"))
        #expect(value.preset == "12")
        #expect(value.amount == 3.5)
        #expect(value.unit == "rem")
        value.isCustom = true
        value.amount = 2.5
        value.unit = "rem"
        value.isCustom = false
        let data = try JSONEncoder().encode(value.storedValue)
        var restored = PartSpaceValue(try JSONDecoder().decode(PartProperty.Value.self, from: data))
        #expect(restored == value)
        restored.isCustom = true
        #expect(restored.cssLength == "2.5rem")
        #expect(restored.preset == "12")
        #expect(PartSpaceValue(.choice("none")).preset == "inherit")
    }

    @Test func defaultValidationRejectsInvalidLengths() {
        #expect(PartSpaceControl.validDefault(.string("inherit")))
        #expect(PartSpaceControl.validDefault(.string("12")))
        #expect(PartSpaceControl.validDefault(.string("13")) == false)
        #expect(PartSpaceControl.validDefault(.string("25")) == false)
        for unit in PartSpaceValue.units {
            #expect(PartSpaceControl.validDefault(.object(["value": .number(16), "unit": .string(unit)])))
        }
        #expect(PartSpaceControl.validDefault(.object(["value": .number(-1), "unit": .string("px")])) == false)
        #expect(PartSpaceControl.validDefault(.object(["value": .number(1), "unit": .string("%;color:red")])) == false)
        let corrupt = PartSpaceValue(.object(["value": .number(-1), "unit": .string("bad")]))
        #expect(corrupt.cssLength == "0px")
    }

    @Test func manifestSupportsAxisAndCustomDefault() throws {
        let data = Data(#"{"type":"space","id":"space","label":"Space","axis":"x","defaults":{"xs":{"value":16,"unit":"px"}}}"#.utf8)
        let property = try JSONDecoder().decode(PartPackageProperty.self, from: data)
        #expect(property.control.type == .space)
        #expect(property.control.axis == "x")
        #expect(PartSpaceControl.validDefault(property.defaultValue))
        let decoded = try JSONDecoder().decode(PartPackageProperty.self, from: JSONEncoder().encode(property))
        #expect(decoded == property)
    }

    @MainActor
    @Test func horizontalSpaceUsesLogicalMarginsAndUniqueClasses() async {
        await PartPackageCatalog.shared.waitUntilLoaded()
        var node = PartNode.make(.container)
        let key = PartProperty.Key(rawValue: "contentSpacing")
        node.setProperty(key, value: .object(["value": .number(2), "unit": .string("em")]))
        let css = PartSpaceControl.css(node: node, key: key, axis: "x")
        #expect(css.contains("margin-inline-end:2em"))
        #expect(css.contains(":where("))
        #expect(css.contains("> :not(:last-child)"))
        let name = PartSpaceControl.className(node: node, key: key, axis: "x")
        #expect(name.range(of: #"^space-x-[0-9a-f]{24}$"#, options: .regularExpression) != nil)
        #expect(PartSpaceControl.className(node: node, key: key, axis: "x") == name)
        let secondKey = PartProperty.Key(rawValue: "otherSpace")
        node.setProperty(secondKey, value: node.propertyValue(key))
        #expect(PartSpaceControl.className(node: node, key: secondKey, axis: "x") != name)
        var other = PartNode.make(.container)
        other.setProperty(key, value: node.propertyValue(key))
        #expect(PartSpaceControl.className(node: node, key: key, axis: "x") != PartSpaceControl.className(node: other, key: key, axis: "x"))
    }

    @MainActor
    @Test func pageCSSGroupsMatchingSpaceIntervalsAndDropsRemovedInstances() async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let key = PartProperty.Key(rawValue: "contentSpacing")
        var first = PartNode.make(.container)
        first.setProperty(key, value: .object(["value": .number(8), "unit": .string("px")]))
        first.setResponsiveProperty(key, value: .object(["value": .number(16), "unit": .string("px")]), at: .medium)
        var second = PartNode.make(.container)
        second.setProperty(key, value: .object(["value": .number(12), "unit": .string("px")]))
        second.setResponsiveProperty(key, value: .object(["value": .number(24), "unit": .string("px")]), at: .medium)

        let firstClass = PartSpaceControl.className(node: first, key: key, axis: "y")
        let secondClass = PartSpaceControl.className(node: second, key: key, axis: "y")
        let theme = Theme.standard
        let grouped = PartSpaceControl.pageCSS(nodes: [first, second], theme: theme)
        #expect(grouped.components(separatedBy: "@media (width < 768px)").count == 2)
        #expect(grouped.components(separatedBy: "@media (width >= 768px)").count == 2)
        #expect(grouped.contains(".\(firstClass) > :not(:last-child)"))
        #expect(grouped.contains(".\(secondClass) > :not(:last-child)"))

        let site = Site(name: "Grouped space", pages: [Page(title: "Home", slug: "index", parts: [first, second])])
        for environment in [PartTemplateEnvironment.preview, .published] {
            let output = StaticSiteRenderer(environment: environment).render(site: site)
            let pageCSS = try #require(output.file(at: "files/page.css")?.contents)
            let siteCSS = try #require(output.file(at: "files/site.css")?.contents)
            #expect(pageCSS.contains(firstClass) && pageCSS.contains(secondClass))
            #expect(pageCSS.components(separatedBy: "@media (width >= 768px)").count == 2)
            #expect(siteCSS.contains(firstClass) == false && siteCSS.contains(secondClass) == false)
        }

        let remaining = PartSpaceControl.pageCSS(nodes: [second], theme: theme)
        #expect(remaining.contains(firstClass) == false)
        #expect(remaining.contains(secondClass))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: ["canvas", "preview", "export"], [375, 767, 768, 1024, 1600])
    func customSpaceStylesOnlyChildrenAndOnlyItsOwnInstance(destination: String, width: Int) async throws {
        await PartPackageCatalog.shared.waitUntilLoaded()
        let key = PartProperty.Key(rawValue: "contentSpacing")
        var custom = PartNode.make(.container)
        custom.anchor = "custom-space"
        var value = PartSpaceValue(.string("inherit"))
        value.isCustom = true
        value.amount = 37
        value.unit = "px"
        custom.setProperty(key, value: value.storedValue)
        custom.responsiveOverrides = [
            .init(breakpoint: .medium, key: key, value: .string("12")),
            .init(breakpoint: .large, key: key, value: .string("inherit")),
            .init(breakpoint: .extraLarge, key: key, value: .object(["value": .number(99), "unit": .string("px")]))
        ]
        #expect(custom.resolved(at: .medium).propertyValue(key) == value.storedValue)
        custom.children = [PartNode.make(.container), PartNode.make(.container)]
        var preset = PartNode.make(.container)
        preset.anchor = "preset-space"
        preset.setProperty(key, value: .string("12"))
        preset.responsiveOverrides = [
            .init(breakpoint: .medium, key: key, value: .object(["value": .number(2), "unit": .string("rem")]))
        ]
        preset.children = custom.children.map { _ in PartNode.make(.container) }
        var inherited = PartNode.make(.container)
        inherited.anchor = "inherited-space"
        inherited.children = custom.children.map { _ in PartNode.make(.container) }
        let page = Page(title: "Space", slug: "index", parts: [custom, preset, inherited])
        let site = Site(name: "Space", pages: [page])
        let html: String
        if destination == "canvas" {
            html = HTMLPageRenderer().render(page: page, theme: site.theme)
        } else {
            let output = StaticSiteRenderer(environment: destination == "preview" ? .preview : .published).render(site: site)
            #expect(output.errors.isEmpty)
            let pageHTML = try #require(output.file(at: "index.html"))
            let css = output.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
            html = pageHTML.contents.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        }
        #expect(html.contains(PartSpaceControl.className(node: custom, key: key, axis: "y")))
        #expect(PartSpaceControl.css(node: preset, key: key, axis: "y").isEmpty == false)
        #expect(PartSpaceControl.className(node: inherited, key: key, axis: "y").isEmpty)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        defer { view.stopLoading() }
        view.loadHTMLString(html, baseURL: nil)
        var ready = false
        for _ in 0..<200 {
            ready = (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('custom-space')")) as? Bool == true
            if ready { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(ready)
        let results = try #require(try await view.evaluateJavaScript("""
            (() => {
                const read = id => {
                    const parent = document.getElementById(id).firstElementChild;
                    return [parent, parent.firstElementChild, parent.lastElementChild].map(e => parseFloat(getComputedStyle(e).marginBottom));
                };
                const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
                return [...read('custom-space'), ...read('preset-space'), ...read('inherited-space'), rem];
            })()
            """) as? [Double])
        #expect(results[0] == 0)
        #expect(results[1] == (width < 768 ? 37 : width < 1024 ? 3 * results[9] : 0))
        #expect(results[2] == 0)
        #expect(results[4] == (width < 768 ? 3 : 2) * results[9])
        #expect(results[5] == 0)
        #expect(results[7] == 0)
    }
}
