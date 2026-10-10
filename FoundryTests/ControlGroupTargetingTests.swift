import Foundation
import JavaScriptCore
import Testing
@testable import Foundry

struct ControlGroupTargetingTests {
    @Test
    func groupLocalValuesKeepDerivedAndIndexedValuesWithinTheirNamespace() {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.video])
        let values: [String: PartPackageValue] = [
            "surface.backgroundVideo": .string("clip.mp4"),
            "surface.backgroundVideo.href": .string("resolved.mp4"),
            "surface.backgroundVideo[0].href": .string("first.mp4"),
            "surface.backgroundVideoExtra.href": .string("not a member"),
            "other.backgroundVideo.href": .string("other.mp4")
        ]
        let local = PartPackageControlGroupCSSResolver.localValues(values, members: group.properties)
        #expect(local["backgroundVideo"] == .string("clip.mp4"))
        #expect(local["backgroundVideo.href"] == .string("resolved.mp4"))
        #expect(local["backgroundVideo[0].href"] == .string("first.mp4"))
        #expect(local.count == 3)
    }

    @Test
    func groupValuesMatchDeclarationOrderMapping() {
        let members = PartPackageControlGroup(type: .background, id: "surface").properties
        var values: [String: PartPackageValue] = [:]
        for (index, member) in members.enumerated() {
            for suffix in ["", ".href", "[0].href", ".nested[1].value", "Extra.href"] {
                values[member.id + suffix] = .string("value-\(index)-\(suffix)")
            }
        }
        var expected: [String: PartPackageValue] = [:]
        for member in members {
            guard let source = member.controlGroupSource else { continue }
            let id = member.id
            for (key, value) in values where key == id || key.hasPrefix(id + ".") || key.hasPrefix(id + "[") {
                expected[source.localID + key.dropFirst(id.count)] = value
            }
        }
        #expect(PartPackageControlGroupCSSResolver.localValues(values, members: members) == expected)
        #expect(PartPackageControlGroupCSSResolver.localValues(values, members: []).isEmpty)
        #expect(PartPackageControlGroupCSSResolver.localValues([:], members: members).isEmpty)
    }

    @Test
    func backgroundNeverChangesHostStructure() throws {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.video])
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("static"),
            "surface.backgroundStyle": .string("video"),
            "surface.backgroundVideo.href": .string("film.mp4")
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: false)
        let css = try #require(values["surface.css"]?.stringValue)
        let declarations = css.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(declarations.contains { $0.hasPrefix("position:") } == false)
        #expect(declarations.contains { $0.hasPrefix("isolation:") } == false)
        #expect(declarations.contains { $0.hasPrefix("overflow:") } == false)
        #expect(values["surface.videoCSS"] == nil)
        let markup = try #require(values["surface.video"]?.stringValue)
        #expect(markup.hasPrefix(#"<div class="background-layer" aria-hidden="true""#))
        #expect(markup.contains("<video"))
        #expect(markup.hasSuffix("</video></div>"))
    }

    @Test
    func videoCanvasWithoutPosterDoesNotEmitBrokenImage() {
        let group = PartPackageControlGroup(type: .background, id: "surface", backgroundTypes: [.video])
        var values: [String: PartPackageValue] = [
            "surface.backgroundMode": .string("static"),
            "surface.backgroundStyle": .string("video"),
            "surface.backgroundVideo.href": .string("film.mp4")
        ]
        PartPackageBackgroundResolver.resolve(&values, properties: group.properties, enablesEditorMarkup: true)
        #expect(values["surface.video"] == .string(""))
    }

    private func manifest(_ entry: String) -> Data {
        Data("""
        {"minimumAPIVersion":1,"id":"com.example.targeting","title":"Targeting","version":"1.0.0",
         "inspector":[\(entry)],"templates":{"html":"part.html"}}
        """.utf8)
    }

    @Test(arguments: [
        #"{"type":"reveal","id":"motion","targetSelector":""}"#,
        #"{"type":"reveal","id":"motion","targetSelector":"  "}"#,
        #"{"type":"reveal","id":"motion","targetSelector":false}"#,
        #"{"type":"reveal","id":"motion","targetSelector":"{{ control.selector }}"}"#,
        #"{"type":"flexbox","id":"flow","targetSelector":".content"}"#
    ])
    func rejectsInvalidTargetDeclarations(_ entry: String) throws {
        #expect(try PartPackageManifestSchema.diagnostics(for: manifest(entry)).contains { $0.location.hasSuffix(".targetSelector") })
    }

    @Test
    func revealTargetRoundTrips() throws {
        let data = manifest(#"{"type":"reveal","id":"motion","targetSelector":".content"}"#)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(decoded.controlGroups.first?.target == ".content")
        #expect(try JSONDecoder().decode(PartPackageManifest.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    private func script(id: String = "motion", target: String?, stagger: Int = 0, enabled: Bool = true) -> String {
        let group = PartPackageControlGroup(type: .reveal, id: id, target: target)
        var values = Dictionary(uniqueKeysWithValues: group.properties.map { ($0.id, $0.defaultValue) })
        values[id + ".revealEnabled"] = .boolean(enabled)
        values[id + ".revealStagger"] = .number(Double(stagger))
        return PartTemplateRenderer.render(group.javaScript, context: .init(
            instanceID: UUID(), packageIdentifier: "com.example.targeting", properties: values, slots: [:]
        ))
    }

    /// A small DOM/GSAP boundary fake executes the actual generated script,
    /// exercising selection, cleanup and tween arguments without a network.
    private func runtime() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(#"""
        var calls = [], warnings = [], reverted = 0, reducedMotion = false, queried = [];
        var root = {name: 'root', children: []};
        var content = {name: 'content', children: [], closest: () => root};
        var other = {name: 'other', children: [], closest: () => root};
        var nested = {name: 'nested', closest: () => ({name: 'nestedPart'})};
        content.children = [{name: 'first'}, {name: 'second'}];
        root.children = [content, other];
        root.querySelectorAll = selector => {
            queried.push(selector);
            if (selector === '[') throw new Error('Invalid selector');
            if (selector === '.content') return [content, nested];
            if (selector === '.other') return [other];
            if (selector === '.many') return [content, other];
            if (selector === '.nested') return [nested];
            return [];
        };
        var document = {querySelector: () => root};
        var window = {matchMedia: () => ({matches: reducedMotion})};
        var console = {warn: (...args) => warnings.push(args)};
        var ScrollTrigger = {};
        var gsap = {
            registerPlugin: () => {},
            context: callback => {callback(); return {revert: () => reverted++};},
            from: (targets, options) => calls.push({names: targets.map(t => t.name).join(','), trigger: options.scrollTrigger.trigger.name})
        };
        """#)
        try #require(context.exception == nil)
        return context
    }

    @Test
    func revealSelectsInnerTargetAndStaggersItsChildren() throws {
        let context = try runtime()
        context.evaluateScript(script(target: ".content", stagger: 50))
        #expect(context.exception == nil)
        #expect(context.evaluateScript("calls[0].names")?.toString() == "first,second")
        #expect(context.evaluateScript("calls[0].trigger")?.toString() == "content")
        #expect(context.evaluateScript("warnings.length")?.toInt32() == 0)
    }

    @Test(arguments: [".missing", ".many", ".nested", "[", "body"])
    func revealDoesNotFallBackWhenTargetCannotBeResolved(_ selector: String) throws {
        let context = try runtime()
        context.evaluateScript(script(target: selector))
        #expect(context.exception == nil)
        #expect(context.evaluateScript("calls.length")?.toInt32() == 0)
        #expect(context.evaluateScript("warnings.length")?.toInt32() == 1)
    }

    @Test
    func revealDefaultsToRootAndCleansUpWhenDisabled() throws {
        let context = try runtime()
        context.evaluateScript(script(target: nil))
        #expect(context.evaluateScript("calls[0].names")?.toString() == "root")
        #expect(context.evaluateScript("queried.length")?.toInt32() == 0)
        context.evaluateScript(script(target: nil, enabled: false))
        #expect(context.evaluateScript("reverted")?.toInt32() == 1)
        #expect(context.evaluateScript("calls.length")?.toInt32() == 1)
        context.evaluateScript("reducedMotion = true")
        context.evaluateScript(script(target: ".content"))
        #expect(context.evaluateScript("calls.length")?.toInt32() == 1)
    }

    @Test
    func revealInstancesKeepSeparateTargetsAndCleanupContexts() throws {
        let context = try runtime()
        context.evaluateScript(script(id: "first", target: ".content"))
        context.evaluateScript(script(id: "second", target: ".other"))
        #expect(context.evaluateScript("calls.map(c => c.names).join(',')")?.toString() == "content,other")
        #expect(context.evaluateScript("reverted")?.toInt32() == 0)
        context.evaluateScript(script(id: "first", target: ".content"))
        #expect(context.evaluateScript("reverted")?.toInt32() == 1)
    }

    @Test
    func revealSelectorIsQuotedAsData() throws {
        let selector = "[data-label=\"quoted\"]; </script>\n\\"
        let generated = script(target: selector)
        #expect(generated.contains("</script>") == false)
        let context = try runtime()
        context.evaluateScript(generated)
        #expect(context.exception == nil)
        #expect(context.evaluateScript("queried[0]")?.toString() == selector)
    }

    @Test
    func flexboxClassOutputIsExplicitAndNamespaced() {
        let first = PartPackageControlGroup(type: .flexbox, id: "outer")
        let second = PartPackageControlGroup(type: .flexbox, id: "inner")
        var values: [String: PartPackageValue] = [:]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: first.properties + second.properties)
        #expect(first.css.isEmpty)
        #expect(values["outer.classes"] == .string(""))
        #expect(values["inner.classes"] == .string(""))
        #expect(values["outer.childCSS"] == nil)
        #expect(values["inner.childCSS"] == nil)
    }
}
