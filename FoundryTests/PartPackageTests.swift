import Foundation
import CryptoKit
import Testing
@testable import Foundry

struct PartPackageTests {
    @Test @MainActor func inspectorSectionResetRestoresHiddenAndResponsiveDefaultsWithOneUndo() throws {
        let controls = """
        {"section":"Layout","controls":[
          {"type":"number","id":"width","responsive":true,"defaults":{"base":10,"large":20}},
          {"type":"toggle","id":"enabled","defaults":{"base":false}},
          {"type":"number","id":"hiddenValue","defaults":{"base":5},"visibleWhen":{"id":"enabled","value":true}}
        ]},
        {"section":"Other","controls":[{"type":"number","id":"other","defaults":{"base":1}}]},
        {"type":"advanced"}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: controls), template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode.make(.init(rawValue: package.manifest.identifier))
        let section = PartPropertySection(rawValue: "Layout")
        let state = PartInspectorSectionState(part: node, section: section, framework: .standard)
        let widthDefinition = try #require(node.type.definition.property(for: .init(rawValue: "width")))
        let widthState = PartInspectorControlState(part: node, definition: widthDefinition, framework: .standard)
        #expect(state.hasChanges(in: node) == false)
        #expect(!widthState.hasChanges(in: node, at: .mobile, screens: .standard))
        #expect(!widthState.hasChanges(in: node, at: .large, screens: .standard))
        node.setResponsiveProperty(.init(rawValue: "width"), value: .number(10), at: .medium)
        #expect(state.hasChanges(in: node) == false)
        #expect(!widthState.hasChanges(in: node, at: .medium, screens: .standard))
        #expect(state.canReset(node))
        node.setProperty(.init(rawValue: "hiddenValue"), value: .number(9))
        #expect(state.hasChanges(in: node))
        node.setProperty(.init(rawValue: "width"), value: .number(30))
        node.setResponsiveProperty(.init(rawValue: "width"), value: .number(60), at: .large)
        node.setResponsiveProperty(.init(rawValue: "width"), value: .number(80), at: .extraLarge)
        #expect(widthState.hasChanges(in: node, at: .mobile, screens: .standard))
        #expect(widthState.hasChanges(in: node, at: .large, screens: .standard))
        #expect(widthState.hasChanges(in: node, at: .extraLarge, screens: .standard))
        node.setProperty(.init(rawValue: "other"), value: .number(99))
        node.children = [PartNode(type: .paragraph)]
        node.anchor = "hero"
        let changed = node
        let document = FoundryDocument()
        document.site.pages = [Page(title: "Home", slug: "index", parts: [node])]
        let undo = UndoManager()
        let editor = ProjectEditor(document: document, undoManager: undo)
        editor.resetInspectorSection(ids: [node.id], section: section)
        let reset = try #require(document.site.part(withID: node.id))
        #expect(state.hasChanges(in: reset) == false)
        #expect(reset.propertyValue(.init(rawValue: "width")) == .number(10))
        #expect(reset.responsiveOverrides?.first { $0.breakpoint == .large }?.value == .number(20))
        #expect(reset.hasResponsiveOverride(.init(rawValue: "width"), at: .extraLarge) == false)
        #expect(reset.propertyValue(.init(rawValue: "other")) == .number(99))
        #expect(reset.children == changed.children)
        #expect(reset.anchor == "hero")
        undo.undo()
        #expect(document.site.part(withID: node.id) == changed)
        undo.redo()
        #expect(document.site.part(withID: node.id) == reset)

        let advanced = PartPropertySection(rawValue: "Advanced")
        #expect(PartInspectorSectionState(part: reset, section: advanced, framework: .standard).hasChanges(in: reset))
        editor.resetInspectorSection(ids: [node.id], section: advanced)
        #expect(document.site.part(withID: node.id)?.anchor == nil)
        #expect(document.site.part(withID: node.id)?.propertyValue(.init(rawValue: "other")) == .number(99))

        let global = ReusablePartDefinition(name: "Shared", root: changed)
        var first = changed.duplicatedForReusableDefinition()
        first.reusableDefinitionID = global.id
        var second = changed.duplicatedForReusableDefinition()
        second.reusableDefinitionID = global.id
        var overridden = changed.duplicatedForReusableDefinition()
        overridden.reusableDefinitionID = global.id
        overridden.overridesGlobalDefinition = true
        document.site.globalPartLibrary = [.part(global)]
        document.site.pages = [Page(title: "Globals", slug: "globals", parts: [first, second, overridden])]
        editor.resetInspectorSection(ids: [first.id], section: section)
        #expect(state.hasChanges(in: try #require(document.site.part(withID: first.id))) == false)
        #expect(state.hasChanges(in: try #require(document.site.part(withID: second.id))) == false)
        #expect(document.site.part(withID: overridden.id) == overridden)
        editor.resetInspectorSection(ids: [overridden.id, second.id], section: section)
        #expect(state.hasChanges(in: try #require(document.site.part(withID: overridden.id))) == false)
    }

    private static var developerDocsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry Docs", directoryHint: .isDirectory)
            .appending(path: "developer", directoryHint: .isDirectory)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "index.md").path)))
    @MainActor func developerDocumentationQuickExamplesLoad() throws {
        // Read the current sibling working tree, not copied or stale fixtures.
        let pages = try FileManager.default.contentsOfDirectory(at: Self.developerDocsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let expression = try NSRegularExpression(pattern: #"(?s)## Quick example\s+.*?```json\s*\n(.*?)```"#)
        var checked = 0
        for page in pages {
            let source = try String(contentsOf: page, encoding: .utf8)
            guard let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let range = Range(match.range(at: 1), in: source) else { continue }
            let controls = String(source[range])
            let quickSection = String(source[source.range(of: "## Quick example")!.upperBound...])
                .components(separatedBy: "\n## ")[0]
            func output(_ language: String) throws -> String {
                let pattern = try NSRegularExpression(pattern: "(?s)```\(language)\\s*\\n(.*?)```")
                guard let outputMatch = pattern.firstMatch(in: quickSection, range: NSRange(quickSection.startIndex..., in: quickSection)),
                      let outputRange = Range(outputMatch.range(at: 1), in: quickSection) else { return "" }
                return String(quickSection[outputRange])
            }
            let packageURL = try makePackage(
                manifest: manifest(withInspectorEntries: controls),
                template: "<section class=\"{{ part.class }}\" {{ part.attributes }}>\(try output("html")){{ childArea(\"content\") }}</section>",
                additionalFiles: ["part.css": try output("css")]
            )
            defer { try? FileManager.default.removeItem(at: packageURL) }
            do {
                let package = try PartPackageLoader.load(from: packageURL)
                try package.preparePayload()
            } catch {
                Issue.record("\(page.lastPathComponent): \(error.localizedDescription)")
            }
            checked += 1
        }
        #expect(checked == 48, "Expected every documented control and control group's Quick example; update this count when adding a reference page.")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "index.md").path)))
    @MainActor func developerDocumentationControlGroupPropertyExamplesLoad() throws {
        let pages = try FileManager.default.contentsOfDirectory(at: Self.developerDocsURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("-control-group.md") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let expression = try NSRegularExpression(pattern: #"(?s)```json\s*\n(.*?)```"#)
        #expect(pages.count == 14)
        for page in pages {
            let source = try String(contentsOf: page, encoding: .utf8)
            let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
            #expect(matches.isEmpty == false, "Missing examples in \(page.lastPathComponent)")
            for (index, match) in matches.enumerated() {
                let range = try #require(Range(match.range(at: 1), in: source))
                let url = try makePackage(
                    manifest: manifest(withInspectorEntries: String(source[range])),
                    template: "<section class=\"{{ part.class }}\" {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
                )
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let package = try PartPackageLoader.load(from: url)
                    try package.preparePayload()
                } catch {
                    Issue.record("\(page.lastPathComponent), JSON example \(index + 1): \(error.localizedDescription)")
                }
            }
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "index.md").path)))
    @MainActor func developerDocumentationCompleteExamplesLoad() throws {
        let pages = try FileManager.default.contentsOfDirectory(at: Self.developerDocsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sectionPattern = try NSRegularExpression(pattern: #"(?m)^## (?:Complete example|Example)\s*$"#)
        let fencePattern = try NSRegularExpression(pattern: #"(?s)```(\w+)\s*\n(.*?)```"#)
        var checked = 0
        for page in pages {
            let source = try String(contentsOf: page, encoding: .utf8)
            guard source.contains("## Quick example"),
                  let heading = sectionPattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let headingRange = Range(heading.range, in: source) else { continue }
            let section = String(source[headingRange.upperBound...]).components(separatedBy: "\n## ")[0]
            var snippets: [String: String] = [:]
            for fence in fencePattern.matches(in: section, range: NSRange(section.startIndex..., in: section)) {
                let language = String(section[try #require(Range(fence.range(at: 1), in: section))])
                let content = String(section[try #require(Range(fence.range(at: 2), in: section))])
                snippets[language, default: ""] += content
            }
            let json = try #require(snippets["json"], "Missing declaration in \(page.lastPathComponent)")
            // Older complete examples show the inspector key and array; newer ones show a single item.
            let controls: String
            if json.contains("\"inspector\"") {
                let start = try #require(json.range(of: "["))
                let end = try #require(json.range(of: "]", options: .backwards))
                controls = String(json[start.upperBound..<end.lowerBound])
            } else {
                controls = json
            }
            var exampleManifest = try #require(JSONSerialization.jsonObject(
                with: Data(manifest(withInspectorEntries: controls).utf8)
            ) as? [String: Any])
            var declarations = try #require(exampleManifest["inspector"] as? [[String: Any]])
            declarations.removeLast() // Remove the test helper's unrelated content childPicker.
            exampleManifest["inspector"] = declarations
            let manifestData = try JSONSerialization.data(withJSONObject: exampleManifest)
            let html = snippets["html", default: ""]
            let template = html.contains("{{ part.attributes }}") ? html
                : "<section {{ part.attributes }}>\(html)</section>"
            let url = try makePackage(manifest: String(decoding: manifestData, as: UTF8.self), template: template,
                                      additionalFiles: ["part.css": snippets["css", default: ""]])
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let package = try PartPackageLoader.load(from: url)
                try package.preparePayload()
            } catch {
                Issue.record("\(page.lastPathComponent) complete example: \(error.localizedDescription)")
            }
            checked += 1
        }
        #expect(checked == 28, "Expected all 28 control reference examples.")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "quick-start.md").path)))
    @MainActor func developerDocumentationQuickStartLoads() throws {
        let source = try String(contentsOf: Self.developerDocsURL.appending(path: "quick-start.md"), encoding: .utf8)
        func snippet(_ marker: String) throws -> String {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            let expression = try NSRegularExpression(pattern: "(?s)<!-- \(escaped) -->\\s*```\\w+\\s*\\n(.*?)```")
            let match = try #require(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
            return String(source[try #require(Range(match.range(at: 1), in: source))])
        }
        for stage in ["starter", "complete"] {
            let base = try snippet("starter:manifest.json")
            var manifest = try #require(JSONSerialization.jsonObject(with: Data(base.utf8)) as? [String: Any])
            if stage == "complete" {
                let fragment = try snippet("complete:inspector")
                let additions = try #require(JSONSerialization.jsonObject(
                    with: Data("{\(fragment)}".utf8)
                ) as? [String: Any])
                manifest["inspector"] = additions["inspector"]
            }
            let encoded = try JSONSerialization.data(withJSONObject: manifest)
            let packageURL = try makePackage(
                manifest: String(decoding: encoded, as: UTF8.self), template: snippet("\(stage):part.html"),
                additionalFiles: ["part.css": snippet("\(stage):part.css")]
            )
            defer { try? FileManager.default.removeItem(at: packageURL) }
            let package = try PartPackageLoader.load(from: packageURL)
            try package.preparePayload()
            #expect(package.manifest.identifier == "uk.co.example.callout")
            #expect(package.dropZoneNames.contains("content") == (stage == "complete"))
            #expect(package.manifest.resolvedProperties.count == (stage == "complete" ? 2 : 0))
        }
    }

    @Test @MainActor func structuredAndArrayBreakpointDefaultsUseNormalConversion() throws {
        let controls = """
        {"type" : "number", "id" : "pair", "count" : 2, "responsive" : true,
        "defaults" : {"base" : [1, 2], "large" : [3, 4]}},
        {"type" : "frameworkBorder", "id" : "border", "responsive" : true,
        "defaults" : {"base" : {"width" : "none"}, "large" : {"width" : "sm", "style" : "dashed"}}},
        {"type" : "frameworkFont", "id" : "font", "showsWeight" : true, "responsive" : true,
        "defaults" : {"base" : {"family" : "body", "weight" : 400}, "large" : {"family" : "heading", "weight" : 700}}},
        {"type" : "frameworkColor", "id" : "colour", "responsive" : true,
        "defaults" : {"base" : {"palette" : "accent"}, "large" : {"palette" : "standard.lime", "lightShade" : 8, "darkShade" : 3}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let created = PartNode.make(.init(rawValue: package.manifest.identifier))
        // Developer breakpoint defaults start out pinned, like user pins.
        #expect(created.hasResponsiveOverride(.init(rawValue: "pair"), at: .large))
        #expect(!created.hasResponsiveOverride(.init(rawValue: "pair"), at: .medium))
        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(created))
        let node = restored.resolved(at: .large)
        #expect(node.propertyValue(.init(rawValue: "pair")) == .array([.number(3), .number(4)]))
        #expect(node.propertyValue(.init(rawValue: "border.style")).stringValue == "dashed")
        #expect(node.propertyValue(.init(rawValue: "font")).stringValue == "heading")
        #expect(node.propertyValue(.init(rawValue: "font.weight")) == .number(700))
        guard case .packageColor(let colour) = node.propertyValue(.init(rawValue: "colour")) else { Issue.record("Missing colour"); return }
        #expect(colour.shade.rawValue == 8)
        #expect(colour.darkShade.rawValue == 3)
        let encoded = try JSONEncoder().encode(package.manifest)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: encoded)
        #expect(decoded.resolvedProperties.first?.breakpointDefaults["large"] == .array([.number(3), .number(4)]))
    }

    @Test @MainActor func developerBreakpointDefaultsCascadeAndExport() throws {
        let controls = """
        {"type" : "number", "id" : "gap", "responsive" : true,
        "defaults" : {"base" : 4, "medium" : 12, "large" : 24}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>", additionalFiles: ["part.css": ":instance { gap: {{ control.gap }}px; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode.make(.init(rawValue: package.manifest.identifier))
        let key = PartProperty.Key(rawValue: "gap")
        #expect(node.propertyValue(key, at: .small) == .number(4))
        #expect(node.propertyValue(key, at: .medium) == .number(12))
        #expect(node.propertyValue(key, at: .extraLarge) == .number(24))
        // Each declared breakpoint starts pinned, so its blue dot is already set.
        #expect(node.hasResponsiveOverride(key, at: .medium))
        #expect(node.hasResponsiveOverride(key, at: .large))
        #expect(!node.hasResponsiveOverride(key, at: .small))
        var screens = ScreenTokens.standard
        screens.update(.medium) { $0.isEnabled = false }
        #expect(node.propertyValue(key, at: .medium, screens: screens) == .number(4))
        node.setResponsiveProperty(key, value: .number(18), at: .medium)
        #expect(node.propertyValue(key, at: .medium) == .number(18))
        #expect(node.propertyValue(key, at: .large) == .number(24))
        #expect(node.propertyValue(key, at: .medium, screens: screens) == .number(4))
        node.setResponsiveProperty(key, value: .number(12), at: .medium)
        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(restored.propertyValue(key, at: .medium) == .number(12))
        var site = Site(name: "Defaults", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let exported = StaticSiteRenderer().render(site: site)
        #expect(exported.files.contains { $0.contents.contains("gap: 12px") })
        #expect(exported.files.contains { $0.contents.contains("gap: 24px") })
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains("gap: 24px"))
        site.framework.screens = screens
        let disabledExport = StaticSiteRenderer().render(site: site)
        #expect(!disabledExport.files.contains { $0.contents.contains("gap: 12px") })
        #expect(disabledExport.files.contains { $0.contents.contains("gap: 24px") })

        // Unpinning a developer default is like unpinning any other value:
        // that breakpoint inherits from the one below it again.
        node.removeResponsiveOverride(key, at: .medium)
        #expect(!node.hasResponsiveOverride(key, at: .medium))
        #expect(node.propertyValue(key, at: .medium) == .number(4))
        #expect(node.propertyValue(key, at: .large) == .number(24))
    }

    @Test @MainActor func editsTargetTheGoverningBreakpointNotTheViewedOne() throws {
        let controls = """
        {"type" : "number", "id" : "gap", "responsive" : true,
        "defaults" : {"base" : 4, "medium" : 12}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        var node = PartNode.make(.init(rawValue: package.manifest.identifier))
        let key = PartProperty.Key(rawValue: "gap")

        // The developer's medium default starts pinned: everything below it
        // inherits the base; medium and above are governed by that pin.
        #expect(node.governingBreakpoint(for: key, at: .small) == .mobile)
        #expect(node.governingBreakpoint(for: key, at: .medium) == .medium)
        #expect(node.governingBreakpoint(for: key, at: .extraLarge) == .medium)

        // A pin at large captures the flow from that width up.
        node.setResponsiveProperty(key, value: .number(20), at: .large)
        #expect(node.governingBreakpoint(for: key, at: .extraLarge) == .large)
        #expect(node.governingBreakpoint(for: key, at: .medium) == .medium)
        #expect(node.governingBreakpoint(for: key, at: .small) == .mobile)

        // Disabled screens drop out of the walk entirely.
        node.removeResponsiveOverride(key, at: .large)
        var screens = ScreenTokens.standard
        screens.update(.medium) { $0.isEnabled = false }
        #expect(node.governingBreakpoint(for: key, at: .extraLarge, screens: screens) == .mobile)
        #expect(node.governingBreakpoint(for: key, at: .extraLarge) == .medium)
    }

    @Test func defaultsSchemaRejectsInvalidContracts() throws {
        for fields in [
            "\"default\" : 1",
            "\"defaults\" : {\"large\" : 1}",
            "\"defaults\" : {\"base\" : 1, \"desktop\" : 2}",
            "\"defaults\" : {\"base\" : 1, \"large\" : 2}"
        ] {
            let item = "{\"type\" : \"number\", \"id\" : \"n\", \(fields)}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: item).utf8)).contains { $0.severity == .error })
        }
    }

    @Test @MainActor func edgesAndCornersControlsLoadPersistAndRender() throws {
        let controls = """
        {"type" : "edges", "id" : "inset",
        "units" : ["px", "%"],
        "defaults" : {"base" : {"value" : 10, "unit" : "px"}}},
        {"type" : "corners", "id" : "round",
        "defaults" : {"base" : {
            "topLeft" : {"value" : 2, "unit" : "px"},
            "topRight" : {"value" : 4, "unit" : "px"},
            "bottomLeft" : {"value" : 6, "unit" : "px"},
            "bottomRight" : {"value" : 8, "unit" : "px"}
        }}},
        {"type" : "edges", "id" : "free", "linked" : false,
        "defaults" : {"base" : {"value" : 10, "unit" : "px"}}}
        """
        let url = try makePackage(
            manifest: manifest(withInspectorEntries: controls),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.css": ":instance { inset: {{ control.inset }}; --top: {{ control.inset.top }}; --n: {{ control.inset.values.top }}; border-radius: {{ control.round }}; --tl: {{ control.round.topLeft }}; }"]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        let definitions = PartPackageAdapter.definition(from: package).properties
        guard case .edges(let units)? = definitions.first(where: { $0.key.rawValue == "inset" })?.control else {
            Issue.record("Expected an edges control"); return
        }
        #expect(units == ["px", "%"])
        guard case .corners? = definitions.first(where: { $0.key.rawValue == "round" })?.control else {
            Issue.record("Expected a corners control"); return
        }

        let node = PartNode(type: .init(rawValue: package.manifest.identifier))
        guard case .frameworkMargin(let inset) = node.propertyValue(.init(rawValue: "inset")) else {
            Issue.record("Expected margin-backed storage"); return
        }
        // Uniform defaults fill every edge without activating the links.
        #expect(!inset.verticalLinked && !inset.horizontalLinked)
        #expect(inset.values.allSatisfy { $0.isCustom && $0.amount == 10 && $0.unit == "px" })
        guard case .frameworkRadius(let round) = node.propertyValue(.init(rawValue: "round")) else {
            Issue.record("Expected radius-backed storage"); return
        }
        #expect(!round.verticalLinked && !round.horizontalLinked)
        #expect(round.value(for: .top).amount == 2)
        #expect(round.value(for: .right).amount == 8)
        // linked: false starts equal defaults unlinked.
        guard case .frameworkMargin(let free) = node.propertyValue(.init(rawValue: "free")) else {
            Issue.record("Expected margin-backed storage"); return
        }
        #expect(!free.verticalLinked && !free.horizontalLinked)
        #expect(free.values.allSatisfy { $0.amount == 10 })

        let site = Site(name: "Box", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let exported = StaticSiteRenderer().render(site: site)
        let css = try #require(exported.files.first { $0.contents.contains("inset:") }?.contents)
        #expect(css.contains("inset: 10.0px 10.0px 10.0px 10.0px"))
        #expect(css.contains("--top: 10.0px"))
        #expect(css.contains("--n: 10"))
        #expect(css.contains("border-radius: 2.0px 4.0px 8.0px 6.0px"))
        #expect(css.contains("--tl: 2.0px"))

        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(restored.propertyValue(.init(rawValue: "round")) == node.propertyValue(.init(rawValue: "round")))
    }

    @Test func edgesAndCornersRejectTokensBadUnitsAndCount() throws {
        func load(_ controls: String) throws {
            let url = try makePackage(
                manifest: manifest(withInspectorEntries: controls),
                template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
                additionalFiles: ["part.css": ":instance { }"]
            )
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try PartPackageLoader.load(from: url)
        }
        // Framework tokens are not part of the generic contract.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "edges", "id" : "inset",
        "defaults" : {"base" : "sm"}}
        """) }
        // A default must use a declared unit.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "edges", "id" : "inset",
        "units" : ["px"],
        "defaults" : {"base" : {"value" : 1, "unit" : "rem"}}}
        """) }
        // Corners are nonnegative.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "corners", "id" : "round",
        "defaults" : {"base" : {"value" : -2, "unit" : "px"}}}
        """) }
        // Unknown units are rejected.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "edges", "id" : "inset",
        "units" : ["pt"],
        "defaults" : {"base" : {"value" : 1, "unit" : "px"}}}
        """) }
        // No multi variant.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "edges", "id" : "inset", "count" : 2,
        "defaults" : {"base" : {"value" : 1, "unit" : "px"}}}
        """) }
        // Negative edges are permitted, matching margin semantics.
        #expect(throws: Never.self) { try load("""
        {"type" : "edges", "id" : "inset",
        "defaults" : {"base" : {"value" : -4, "unit" : "px"}}}
        """) }
        // linked: true contradicts differing defaults.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "corners", "id" : "round", "linked" : true,
        "defaults" : {"base" : {
            "topLeft" : {"value" : 2, "unit" : "px"},
            "topRight" : {"value" : 4, "unit" : "px"},
            "bottomLeft" : {"value" : 2, "unit" : "px"},
            "bottomRight" : {"value" : 2, "unit" : "px"}
        }}}
        """) }
        // linked belongs to edges/corners only.
        #expect(throws: (any Error).self) { try load("""
        {"type" : "number", "id" : "n", "linked" : true,
        "defaults" : {"base" : 1}}
        """) }
    }

    @Test @MainActor func frameworkColorChannelsFiltersAndFormatsResolveForBothAppearances() throws {
        let controls = """
        {"type" : "frameworkColor", "id" : "primary",
        "allowsCustom" : true, "customColor" : "#FF0000",
        "defaults" : {"base" : {"palette" : "custom"}}},
        {"type" : "frameworkColor", "id" : "formatted",
        "allowsCustom" : true, "customColor" : "#FF0000", "outputFormat" : "rgb",
        "defaults" : {"base" : {"palette" : "custom"}}}
        """
        let url = try makePackage(
            manifest: manifest(withInspectorEntries: controls),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.css": """
            :instance {
                --main: {{ control.primary }};
                --light-red: {{ control.primary.light.red }};
                --dark-blue: {{ control.primary.dark.blue }};
                --light-rgb: {{ control.primary.light.rgbValues }};
                --contrast: {{ control.primary.contrastColor }};
                --tint: {{ control.primary | lighten(50) }};
                --formatted: {{ control.formatted }};
            }
            """]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        var value = PartPackageColorValue(source: PartFrameworkValueSelection.manualCustom, customColor: "#FF0000", opacity: 1)
        value.darkCustomColor = "#0000FF"
        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        node.setProperty(.init(rawValue: "primary"), value: .packageColor(value))
        var site = Site(name: "Channels", pages: [Page(title: "Home", slug: "index", parts: [node])])
        site.appearanceMode = .both

        let exported = StaticSiteRenderer().render(site: site)
        let css = try #require(exported.files.first { $0.contents.contains("--main:") }?.contents)
        #expect(css.contains("--main: light-dark(#FF0000, #0000FF)"))
        #expect(css.contains("--light-red: 255"))
        #expect(css.contains("--dark-blue: 255"))
        #expect(css.contains("--light-rgb: 255, 0, 0"))
        // White clears 3:1 on both pure red and pure blue, so the appearance
        // pair collapses to a single colour.
        #expect(css.contains("--contrast: #FFFFFF"))
        #expect(css.contains("--tint: light-dark(#FF8080, #8080FF)"))
        #expect(css.contains("--formatted: rgb(255 0 0)"))

        // Single-appearance exports and the canvas resolve concretely for one
        // appearance; the qualified fields stay available and truthful in both.
        site.appearanceMode = .light
        let lightOnly = StaticSiteRenderer().render(site: site)
        let lightCSS = try #require(lightOnly.files.first { $0.contents.contains("--main:") }?.contents)
        #expect(lightCSS.contains("--main: #FF0000"))
        #expect(lightCSS.contains("--contrast: #FFFFFF"))
        #expect(lightCSS.contains("--tint: #FF8080"))
        #expect(lightCSS.contains("--dark-blue: 255"))

        let darkCanvas = HTMLPageRenderer(appearance: .dark).render(page: site.pages[0], framework: site.framework)
        #expect(darkCanvas.contains("--main: #0000FF"))
        #expect(darkCanvas.contains("--contrast: #FFFFFF"))
        #expect(darkCanvas.contains("--tint: #8080FF"))
        #expect(darkCanvas.contains("--light-red: 255"))
    }

    @Test func frameworkColorOutputFormatAcceptsColoursAndRejectsFragments() throws {
        func packageURL(forFormat format: String) throws -> URL {
            let controls = """
            {"type" : "frameworkColor", "id" : "primary",
            "outputFormat" : "\(format)",
            "defaults" : {"base" : {"palette" : "accent"}}}
            """
            return try makePackage(
                manifest: manifest(withInspectorEntries: controls),
                template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
                additionalFiles: ["part.css": ":instance { color: {{ control.primary }}; }"]
            )
        }
        let colourFormatURL = try packageURL(forFormat: "rgba")
        defer { try? FileManager.default.removeItem(at: colourFormatURL) }
        #expect(throws: Never.self) { try PartPackageLoader.load(from: colourFormatURL) }

        let fragmentFormatURL = try packageURL(forFormat: "rgbValues")
        defer { try? FileManager.default.removeItem(at: fragmentFormatURL) }
        #expect(throws: (any Error).self) { try PartPackageLoader.load(from: fragmentFormatURL) }
    }

    @Test @MainActor func frameworkSpacingLoadsPersistsAndRenders() throws {
        let control = """
        {"type" : "frameworkSpacing", "id" : "frameworkSpacing",
        "responsive" : true, "defaults" : {"base" : "sm"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: control), template: "<section {{ part.attributes }} data-spacing=\"{{ control.frameworkSpacing.css }}\" data-top=\"{{ control.frameworkSpacing }}\">{{ childArea(\"content\") }}</section>",
                                  additionalFiles: ["part.css": ":instance { gap: {{ control.frameworkSpacing }}; --numeric-top: {{ control.frameworkSpacing.value }}{{ control.frameworkSpacing.unit }}; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .frameworkSpacing = definition.control else { Issue.record("Expected frameworkSpacing"); return }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        guard case .frameworkSpacing(var spacing) = node.propertyValue(.init(rawValue: "frameworkSpacing")) else {
            Issue.record("Expected typed spacing"); return
        }
        var top = spacing.selection
        top.isCustom = true
        top.amount = 12
        top.unit = "px"
        spacing.selection = top
        node.setResponsiveProperty(.init(rawValue: "frameworkSpacing"), value: .frameworkSpacing(spacing), at: .medium)
        let saved = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(saved.resolved(at: .medium).propertyValue(.init(rawValue: "frameworkSpacing")) == .frameworkSpacing(spacing))
        #expect(saved.propertyValue(.init(rawValue: "frameworkSpacing")) == definition.defaultValue)
        let site = Site(name: "Spacing", pages: [Page(title: "Home", slug: "index", parts: [saved.resolved(at: .medium)])])
        let expected = "12.0px"
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        let responsiveSite = Site(name: "Responsive spacing", pages: [Page(title: "Home", slug: "index", parts: [saved])])
        let responsiveHTML = HTMLPageRenderer(site: responsiveSite).render(page: responsiveSite.pages[0], framework: responsiveSite.framework)
        #expect(responsiveHTML.contains("gap: " + expected))
        #expect(responsiveHTML.contains("--numeric-top: 12px"))
        let exported = StaticSiteRenderer().render(site: responsiveSite)
        #expect(exported.files.contains { $0.contents.contains("gap: " + expected) })
        #expect(exported.files.contains { $0.contents.contains("--numeric-top: 12px") })
    }
    @Test @MainActor func invalidBorderDefaultsAreRejected() throws {
        let invalid = [
            "\"sm\"",
            "{\"width\" : \"auto\"}",
            "{\"width\" : \"sm\", \"style\" : \"invalid\"}",
            "{\"width\" : \"sm\", \"color\" : {\"palette\" : \"bad\"}}",
            "{\"width\" : \"sm\", \"color\" : {\"palette\" : \"accent\", \"darkShade\" : 12}}"
        ]
        for value in invalid {
            let url = try makePackage(manifest: manifest(withInspectorEntries: "{\"type\" : \"frameworkBorder\", \"id\" : \"border\", \"defaults\" : {\"base\" : \(value)}}"), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: (any Error).self) { try PartPackageLoader.load(from: url) }
        }
    }

    @Test @MainActor func frameworkBorderLoadsPersistsAndRenders() throws {
        let control = """
        {"type" : "frameworkBorder", "id" : "border",
        "responsive" : true, "showsStyle" : true, "defaults" : {"base" : {"width" : "sm", "style" : "dashed"}}},
        {"type" : "frameworkColor", "id" : "borderColour", "defaults" : {"base" : {"palette" : "standard.lime", "lightShade" : 8}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: control), template: "<section {{ part.attributes }} data-borderWidth=\"{{ control.border.width.css }}\" data-top=\"{{ control.border.width.top }}\">{{ childArea(\"content\") }}</section>",
                                  additionalFiles: ["part.css": ":instance { border-width: {{ control.border.width }}; border-style: {{ control.border.style }}; border-color: {{ control.borderColour }}; --numeric-top: {{ control.border.width.values.top }}{{ control.border.width.units.top }}; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .frameworkBorderWidth = definition.control else { Issue.record("Expected frameworkBorderWidth"); return }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        guard case .frameworkBorderWidth(var borderWidth) = node.propertyValue(.init(rawValue: "border.width")) else {
            Issue.record("Expected typed borderWidth"); return
        }
        borderWidth.unlinkAll()
        var top = borderWidth.value(for: .top)
        top.isCustom = true
        top.amount = 12
        top.unit = "px"
        borderWidth.set(top, for: .top)
        node.setResponsiveProperty(.init(rawValue: "border.width"), value: .frameworkBorderWidth(borderWidth), at: .medium)
        let saved = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(saved.resolved(at: .medium).propertyValue(.init(rawValue: "border.width")) == .frameworkBorderWidth(borderWidth))
        #expect(saved.propertyValue(.init(rawValue: "border.width")) == definition.defaultValue)
        let site = Site(name: "BorderWidth", pages: [Page(title: "Home", slug: "index", parts: [saved.resolved(at: .medium)])])
        let expected = "12.0px var(--foundry-border-width-sm) var(--foundry-border-width-sm) var(--foundry-border-width-sm)"
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        let responsiveSite = Site(name: "Responsive borderWidth", pages: [Page(title: "Home", slug: "index", parts: [saved])])
        let responsiveHTML = HTMLPageRenderer(site: responsiveSite).render(page: responsiveSite.pages[0], framework: responsiveSite.framework)
        #expect(responsiveHTML.contains("border-width: " + expected))
        #expect(responsiveHTML.contains("--numeric-top: 12px"))
        #expect(responsiveHTML.contains("border-style: dashed"))
        let lime = try #require(ColourPaletteDefaults.standard.first { $0.id == "standard.lime" })
        #expect(responsiveHTML.contains(lime.colour(at: .shade(ColourShade(rawValue: 8)!))))
        let exported = StaticSiteRenderer().render(site: responsiveSite)
        #expect(exported.files.contains { $0.contents.contains("border-width: " + expected) })
        #expect(exported.files.contains { $0.contents.contains("--numeric-top: 12px") })
    }

    @Test @MainActor func frameworkRadiusLoadsPersistsAndRenders() throws {
        let control = """
        {"type" : "frameworkRadius", "id" : "frameworkRadius",
        "responsive" : true, "defaults" : {"base" : "sm"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: control), template: "<section {{ part.attributes }} data-radius=\"{{ control.frameworkRadius.css }}\" data-top=\"{{ control.frameworkRadius.topLeft }}\">{{ childArea(\"content\") }}</section>",
                                  additionalFiles: ["part.css": ":instance { border-radius: {{ control.frameworkRadius }}; --numeric-top: {{ control.frameworkRadius.values.topLeft }}{{ control.frameworkRadius.units.topLeft }}; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .frameworkRadius = definition.control else { Issue.record("Expected frameworkRadius"); return }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        guard case .frameworkRadius(var radius) = node.propertyValue(.init(rawValue: "frameworkRadius")) else {
            Issue.record("Expected typed radius"); return
        }
        radius.unlinkAll()
        var top = radius.value(for: .top)
        top.isCustom = true
        top.amount = 12
        top.unit = "px"
        radius.set(top, for: .top)
        node.setResponsiveProperty(.init(rawValue: "frameworkRadius"), value: .frameworkRadius(radius), at: .medium)
        let saved = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(saved.resolved(at: .medium).propertyValue(.init(rawValue: "frameworkRadius")) == .frameworkRadius(radius))
        #expect(saved.propertyValue(.init(rawValue: "frameworkRadius")) == definition.defaultValue)
        let site = Site(name: "Radius", pages: [Page(title: "Home", slug: "index", parts: [saved.resolved(at: .medium)])])
        let expected = "12.0px var(--foundry-border-radius-sm) var(--foundry-border-radius-sm) var(--foundry-border-radius-sm)"
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        let responsiveSite = Site(name: "Responsive radius", pages: [Page(title: "Home", slug: "index", parts: [saved])])
        let responsiveHTML = HTMLPageRenderer(site: responsiveSite).render(page: responsiveSite.pages[0], framework: responsiveSite.framework)
        #expect(responsiveHTML.contains("border-radius: " + expected))
        #expect(responsiveHTML.contains("--numeric-top: 12px"))
        let exported = StaticSiteRenderer().render(site: responsiveSite)
        #expect(exported.files.contains { $0.contents.contains("border-radius: " + expected) })
        #expect(exported.files.contains { $0.contents.contains("--numeric-top: 12px") })
    }
    @Test @MainActor func standardPaletteDefaultsLoadAndRender() throws {
        for palette in ColourPaletteDefaults.standard {
            let control = """
            {"type" : "frameworkColor", "id" : "colour",
            "defaults" : {"base" : {"palette" : "\(palette.id)",
            "lightShade" : 8, "darkShade" : 3}}}
            """
            let url = try makePackage(manifest: manifest(withInspectorEntries: control),
                template: "<section {{ part.attributes }} style=\"color: {{ control.colour }}\">{{ childArea(\"content\") }}</section>")
            defer { try? FileManager.default.removeItem(at: url) }
            let package = try PartPackageLoader.load(from: url)
            PartRegistry.register(package)
            defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
            let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
            guard case .packageColor(let colour) = definition.defaultValue else { Issue.record("Missing colour"); return }
            #expect(colour.source == palette.id)
            #expect(colour.shade.rawValue == 8)
            #expect(colour.darkShade.rawValue == 3)
            let node = PartNode(type: .init(rawValue: package.manifest.identifier))
            let site = Site(name: "Standard palette", pages: [Page(title: "Home", slug: "index", parts: [node])])
            let expected = palette.colour(at: .shade(.init(rawValue: 8)!))
            #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
            #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        }
        for id in ["lime", "standard.unknown", "custom:missing"] {
            let control = "{\"type\" : \"frameworkColor\", \"id\" : \"colour\", \"defaults\" : {\"base\" : {\"palette\" : \"\(id)\"}}}"
            let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: control).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.severity == .error })
        }
    }
    @Test @MainActor func frameworkMarginLoadsPersistsAndRenders() throws {
        let control = """
        {"type" : "frameworkMargin", "id" : "frameworkMargin",
        "responsive" : true, "defaults" : {"base" : "auto"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: control), template: "<section {{ part.attributes }} data-margin=\"{{ control.frameworkMargin.css }}\" data-top=\"{{ control.frameworkMargin.top }}\">{{ childArea(\"content\") }}</section>",
                                  additionalFiles: ["part.css": ":instance { margin: {{ control.frameworkMargin }}; --numeric-top: {{ control.frameworkMargin.values.top }}{{ control.frameworkMargin.units.top }}; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .frameworkMargin = definition.control else { Issue.record("Expected frameworkMargin"); return }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        guard case .frameworkMargin(var margin) = node.propertyValue(.init(rawValue: "frameworkMargin")) else {
            Issue.record("Expected typed margin"); return
        }
        margin.unlinkAll()
        var top = margin.value(for: .top)
        top.isCustom = true
        top.amount = -12
        top.unit = "px"
        margin.set(top, for: .top)
        node.setResponsiveProperty(.init(rawValue: "frameworkMargin"), value: .frameworkMargin(margin), at: .medium)
        let saved = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(saved.resolved(at: .medium).propertyValue(.init(rawValue: "frameworkMargin")) == .frameworkMargin(margin))
        #expect(saved.propertyValue(.init(rawValue: "frameworkMargin")) == definition.defaultValue)
        let site = Site(name: "Margin", pages: [Page(title: "Home", slug: "index", parts: [saved.resolved(at: .medium)])])
        let expected = "-12.0px auto auto auto"
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        let responsiveSite = Site(name: "Responsive margin", pages: [Page(title: "Home", slug: "index", parts: [saved])])
        let responsiveHTML = HTMLPageRenderer(site: responsiveSite).render(page: responsiveSite.pages[0], framework: responsiveSite.framework)
        #expect(responsiveHTML.contains("margin: " + expected))
        #expect(responsiveHTML.contains("--numeric-top: -12px"))
        let exported = StaticSiteRenderer().render(site: responsiveSite)
        #expect(exported.files.contains { $0.contents.contains("margin: " + expected) })
        #expect(exported.files.contains { $0.contents.contains("--numeric-top: -12px") })
    }
    @Test @MainActor func frameworkPaddingLoadsPersistsAndRenders() throws {
        let control = """
        {"type" : "frameworkPadding", "id" : "frameworkPadding",
        "responsive" : true, "defaults" : {"base" : "sm"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: control), template: "<section {{ part.attributes }} data-padding=\"{{ control.frameworkPadding.css }}\" data-top=\"{{ control.frameworkPadding.top }}\">{{ childArea(\"content\") }}</section>",
                                  additionalFiles: ["part.css": ":instance { padding: {{ control.frameworkPadding }}; --numeric-top: {{ control.frameworkPadding.values.top }}{{ control.frameworkPadding.units.top }}; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .frameworkPadding = definition.control else { Issue.record("Expected frameworkPadding"); return }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        guard case .frameworkPadding(var padding) = node.propertyValue(.init(rawValue: "frameworkPadding")) else {
            Issue.record("Expected typed padding"); return
        }
        padding.unlinkAll()
        var top = padding.value(for: .top)
        top.isCustom = true
        top.amount = 12
        top.unit = "px"
        padding.set(top, for: .top)
        node.setResponsiveProperty(.init(rawValue: "frameworkPadding"), value: .frameworkPadding(padding), at: .medium)
        let saved = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(saved.resolved(at: .medium).propertyValue(.init(rawValue: "frameworkPadding")) == .frameworkPadding(padding))
        #expect(saved.propertyValue(.init(rawValue: "frameworkPadding")) == definition.defaultValue)
        let site = Site(name: "Padding", pages: [Page(title: "Home", slug: "index", parts: [saved.resolved(at: .medium)])])
        let expected = "12.0px var(--foundry-space-sm) var(--foundry-space-sm) var(--foundry-space-sm)"
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains(expected))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains(expected))
        let responsiveSite = Site(name: "Responsive padding", pages: [Page(title: "Home", slug: "index", parts: [saved])])
        let responsiveHTML = HTMLPageRenderer(site: responsiveSite).render(page: responsiveSite.pages[0], framework: responsiveSite.framework)
        #expect(responsiveHTML.contains("padding: " + expected))
        #expect(responsiveHTML.contains("--numeric-top: 12px"))
        let exported = StaticSiteRenderer().render(site: responsiveSite)
        #expect(exported.files.contains { $0.contents.contains("padding: " + expected) })
        #expect(exported.files.contains { $0.contents.contains("--numeric-top: 12px") })
    }

    @Test func frameworkPaddingRejectsUnsupportedManifestKeys() throws {
        for extra in ["\"count\" : 4", "\"allowsCustom\" : true",
                      "\"options\" : []", "\"frameworkValues\" : \"spacing\"",
                      "\"group\" : \"Spacing\""] {
            let control = "{\"type\" : \"frameworkPadding\", \"id\" : \"frameworkPadding\", \"defaults\" : {\"base\" : \"sm\"}, \(extra)}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: control).utf8)).contains { $0.severity == .error })
        }
    }

    @Test func explicitlyRequestedPackTreeLoadsUsingCurrentAPI() throws {
        guard let path = ProcessInfo.processInfo.environment["FOUNDRY_VALIDATE_PACK_TREE"] else { return }
        let urls = FoundryPackLoader.packURLs(in: URL(fileURLWithPath: path), includingRoot: true)
        #expect(!urls.isEmpty)
        for url in urls {
            let pack = try FoundryPackLoader.load(from: url)
            for partURL in pack.partURLs {
                do {
                    _ = try PartPackageLoader.load(from: partURL)
                } catch {
                    Issue.record("\(partURL.path): \(error)")
                }
            }
        }
    }

    @Test(arguments: [0, 1, 2])
    func childPickersKeepTheirDeclaredInspectorPosition(_ position: Int) throws {
        var controls = [
            #"{"type":"text","id":"before","defaults":{"base":""}}"#,
            #"{"type":"frameworkFont","id":"font","defaults":{"base":"body"},"showsWeight":true,"showsStyle":true}"#
        ]
        controls.insert(#"{"type":"childPicker","id":"items","pickerItems":["com.example.child"]}"#, at: position)
        let entries = """
        {"section":"Only Children","controls":[
            {"type":"childPicker","id":"first","pickerItems":["com.example.child"]}
        ]},
        {"section":"Mixed","controls":[\(controls.joined(separator: ","))]}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: entries),
            template: "<div {{ part.attributes }}>{{ childArea(\"first\") }}{{ childArea(\"items\") }}{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        let definition = PartPackageAdapter.definition(from: package)
        let rows = definition.inspectorRows
        var expected = ["property:before", "property:font"]
        expected.insert("slot:items", at: position)
        #expect(rows.filter { $0.section.rawValue == "Mixed" }.map(\.id) == expected)
        #expect(rows.first?.section.rawValue == "Only Children")
        let font = try #require(rows.first { $0.id == "property:font" })
        #expect(font.membershipIDs == ["property:font", "property:font.weight", "property:font.style"])

        // Hidden controls are filtered in place; remaining generated rows
        // still occupy their original place rather than moving below the picker.
        let filtered = rows.compactMap { $0.filtered(
            properties: { $0.key.rawValue != "font" },
            childPickers: { $0.id != "first" }) }
        #expect(filtered.filter { $0.section.rawValue == "Mixed" }.map(\.id)
            == expected.map { $0 == "property:font" ? "property:font.weight" : $0 })
        let noPickers = rows.compactMap { $0.filtered(properties: { _ in true }, childPickers: { _ in false }) }
        #expect(noPickers.map(\.id) == ["property:before", "property:font"])
    }

    @Test func generatedFontRowsShareOneInspectorGrid() throws {
        let item = """
        {"type" : "frameworkFont", "id" : "font",
        "defaults" : {"base" : "body"}, "showsWeight" : true, "showsStyle" : true}
        """
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: item).utf8))
        let property = try #require(decoded.resolvedProperties.first)
        let rows = PartPackageFontControl.properties(property)
        let separate = PartPropertyDefinition(key: .init(rawValue: "other"), label: "Other",
            section: rows[0].section, control: .singleLineText, defaultValue: .string(""))
        let groups = PartInspectorControlGroup.groups(for: [separate] + rows + [separate])
        #expect(groups.map { $0.properties.count } == [1, 3, 1])
        #expect(groups[1].properties.map(\.key.rawValue) == ["font", "font.weight", "font.style"])
        let hiddenFamilyGroups = PartInspectorControlGroup.groups(for: Array(rows.dropFirst()))
        #expect(hiddenFamilyGroups.count == 1)
        #expect(hiddenFamilyGroups.first?.properties.count == 2)
    }

    @Test @MainActor func selectUsesOnlyDeclaredOptions() throws {
        let item = """
        {"type" : "select", "id" : "choice",
        "options" : [{"value" : "body", "title" : "Body"}],
        "defaults" : {"base" : "body"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item),
            template: "<section {{ part.attributes }} data-choice=\"{{ control.choice }}\">{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first)
        #expect(definition.frameworkValueSource == nil)
        guard case .choice(let choices) = definition.control else { Issue.record("Expected ordinary Select"); return }
        #expect(choices.map(\.value) == ["body"])
        let node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        let site = Site(name: "Select", pages: [Page(title: "Home", slug: "index", parts: [node])])
        #expect(HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework).contains("data-choice=\"body\""))
        #expect(try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents).contains("data-choice=\"body\""))

        for extra in ["\"allowsCustom\" : false", "\"allowsCustom\" : true"] +
            ["fontFamilies", "fontSizes", "spacing", "shadows", "colors"].map({ "\"frameworkValues\" : \"\($0)\"" }) {
            let invalid = item.replacingOccurrences(of: "\"type\"", with: extra + ", \"type\"")
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: invalid).utf8))
                .contains { $0.message.contains("Select supports only declared options") })
        }
    }

    @Test func togglePresentationChoosesCheckboxOrSwitch() throws {
        func item(_ extra: String) -> String {
            "{\"type\" : \"toggle\", \"id\" : \"flag\", \"label\" : \"Flag\"\(extra), \"defaults\" : {\"base\" : true}, \"responsive\" : false}"
        }
        for valid in ["checkbox", "switch"] {
            let data = Data(manifest(withInspectorEntries: item(", \"presentation\" : \"\(valid)\"")).utf8)
            #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        }
        let decoded = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: item(", \"presentation\" : \"switch\"")).utf8)
        )
        #expect(decoded.resolvedProperties.first?.control.presentation == .switch)

        let invalid = Data(manifest(withInspectorEntries: item(", \"presentation\" : \"slider\"")).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: invalid).contains {
            $0.message == "A toggle presentation must be checkbox or switch."
        })
        let text = "{\"type\" : \"text\", \"id\" : \"t\", \"label\" : \"T\", \"presentation\" : \"switch\", \"defaults\" : {\"base\" : \"x\"}, \"responsive\" : false}"
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: text).utf8)).contains {
            $0.message == "presentation is available only for select and toggle controls."
        })
    }

    @Test @MainActor func frameworkFontSizeControlResolvesSizeAndLineHeightVariables() throws {
        let item = """
        {"type" : "frameworkFontSize", "id" : "size",
        "label" : "Size", "responsive" : true,
        "defaults" : {"base" : "xl"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item),
            template: "<p {{ part.attributes }} style=\"font-size: {{ control.size }}; line-height: {{ control.size.lineHeight }}\">{{ childArea(\"content\") }}</p>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        let site = Site(name: "Sizes", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(canvas.contains("line-height: var(--foundry-font-size-xl-line-height)"))
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(exported.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(exported.contains("line-height: var(--foundry-font-size-xl-line-height)"))

        // Options-style keys are rejected, and portable defaults accept only
        // the predefined scale — project custom sizes are not portable.
        let withValues = item.replacingOccurrences(of: "\"type\"", with: "\"frameworkValues\" : \"fontSizes\", \"type\"")
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: withValues).utf8))
            .contains { $0.message.contains("does not accept frameworkValues") })
        let badDefault = item.replacingOccurrences(of: "\"xl\"", with: "\"huge\"")
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: badDefault).utf8))
        #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
            .contains { $0.message.contains("frameworkFontSize default must be a predefined size ID") })
    }

    @Test @MainActor func frameworkStackingOrderControlResolvesVariable() throws {
        let item = """
        {"type" : "frameworkStackingOrder", "id" : "layer",
        "label" : "Layer", "responsive" : true,
        "defaults" : {"base" : "modal"}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item),
            template: "<div {{ part.attributes }} style=\"z-index: {{ control.layer }}\">{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        var site = Site(name: "Layers", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("z-index: var(--foundry-z-index-modal)"))
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(exported.contains("z-index: var(--foundry-z-index-modal)"))

        // Custom mode carries a raw integer instead of a token variable.
        var customNode = node
        customNode.setProperty(.init(rawValue: "layer"), value: .packageStackingOrder(.init(
            source: PartFrameworkValueSelection.manualCustom,
            customValue: 750
        )))
        site.pages[0].parts = [customNode]
        let customCanvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(customCanvas.contains("z-index: 750"))
        let customExported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(customExported.contains("z-index: 750"))

        // Options-style keys are rejected, and portable defaults accept only
        // the predefined scale — project custom values are not portable.
        let withValues = item.replacingOccurrences(of: "\"type\"", with: "\"frameworkValues\" : \"zIndexes\", \"type\"")
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: withValues).utf8))
            .contains { $0.message.contains("does not accept frameworkValues") })
        let badDefault = item.replacingOccurrences(of: "\"modal\"", with: "\"everest\"")
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: badDefault).utf8))
        #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
            .contains { $0.message.contains("frameworkStackingOrder default must be a predefined stacking ID") })
    }

    @Test @MainActor func unifiedFontControlHasStructuredOutputAndIndependentOverrides() throws {
        let item = """
        {"type" : "frameworkFont", "id" : "typography",
        "showsWeight" : true, "showsStyle" : true, "responsive" : true,
        "defaults" : {"base" : {"family" : "body", "weight" : 650, "style" : "italic"}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<section {{ part.attributes }} data-face=\"{{ control.typography.family }}|{{ control.typography.weight }}|{{ control.typography.style }}\">{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        let weight = PartPackageFontControl.fieldKey("typography", "weight")
        node.setResponsiveProperty(weight, value: .number(900), at: .medium)
        node.setProperty(.init(rawValue: "typography"), value: .choice("heading"))
        let resolved = node.resolved(at: .medium)
        #expect(resolved.propertyValue(.init(rawValue: "typography")).stringValue == "heading")
        #expect(resolved.propertyValue(weight).numberValue == 900)
        #expect(!node.hasResponsiveOverride(.init(rawValue: "typography"), at: .medium))
        let output = PartPackageFontControl.resolved("typography", node: resolved, framework: .standard)
        guard case .object(let fields) = output else { Issue.record("Expected structured font"); return }
        #expect(fields["family"] == .string(Framework.standard.fontCSSVariable(for: "heading")))
        #expect(fields["weight"] == .number(900))
        #expect(fields["style"] == .string("italic"))
        let site = Site(name: "Fonts", pages: [Page(title: "Home", slug: "index", parts: [resolved])])
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(html.contains("var(--foundry-font-heading)|900|italic"))
    }

    @Test func unifiedFontControlValidatesCapabilities() throws {
        for extra in [
            "\"showsFamily\" : false",
            "\"defaults\" : {\"base\" : {\"family\" : \"body\", \"weight\" : 500}}",
            "\"showsWeight\" : true, \"defaults\" : {\"base\" : {\"family\" : \"body\", \"weight\" : 1001}}",
            "\"showsStyle\" : true, \"defaults\" : {\"base\" : {\"family\" : \"body\", \"style\" : \"bold\"}}",
            "\"defaults\" : {\"base\" : {\"family\" : \"body\", \"size\" : \"xl\"}}",
            "\"showsSize\" : true, \"defaults\" : {\"base\" : {\"family\" : \"body\", \"size\" : \"huge\"}}"
        ] {
            let defaultJSON = extra.contains("\"defaults\"") ? "" : ", \"defaults\" : {\"base\" : \"body\"}"
            let item = "{\"type\" : \"frameworkFont\", \"id\" : \"font\"\(defaultJSON), \(extra)}"
            let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.severity == .error && ($0.message.contains("default.") || $0.message.contains("at least one")) })
        }
        for kind in ["fontWeight", "fontStyle"] {
            let item = "{\"type\" : \"\(kind)\", \"id\" : \"font\", \"defaults\" : {\"base\" : \"normal\"}}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: item).utf8)).contains { $0.message.contains("Use one frameworkFont") })
        }
    }

    @Test @MainActor func fontShowsSizeAddsAThemeFontSizeRow() throws {
        let item = """
        {"type" : "frameworkFont", "id" : "font", "showsSize" : true, "responsive" : true,
        "defaults" : {"base" : {"family" : "body", "size" : "xl"}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item),
            template: "<p {{ part.attributes }} style=\"font-size: {{ control.font.size }}; line-height: {{ control.font.size.lineHeight }}\">{{ childArea(\"content\") }}</p>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        let definitions = PartPackageAdapter.definition(from: package).properties
        #expect(definitions.contains { $0.key.rawValue == "font.size" && $0.isInspectorVisible && $0.isResponsive })
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        let site = Site(name: "Font Sizes", pages: [Page(title: "Home", slug: "index", parts: [node])])
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(canvas.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(canvas.contains("line-height: var(--foundry-font-size-xl-line-height)"))
        let exported = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        #expect(exported.contains("font-size: var(--foundry-font-size-xl)"))
        #expect(exported.contains("line-height: var(--foundry-font-size-xl-line-height)"))
    }

    @Test @MainActor func fixedFamilyCanExposeOnlyWeight() throws {
        let item = "{\"type\" : \"frameworkFont\", \"id\" : \"font\", \"showsFamily\" : false, \"showsWeight\" : true, \"responsive\" : true, \"defaults\" : {\"base\" : \"body\"}}"
        let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        let definitions = PartPackageAdapter.definition(from: package).properties
        let family = try #require(definitions.first { $0.key.rawValue == "font" })
        #expect(!family.isInspectorVisible)
        #expect(!family.isResponsive)
        #expect(definitions.contains { $0.key.rawValue == "font.weight" && $0.isInspectorVisible && $0.isResponsive })
        #expect(!definitions.contains { $0.key.rawValue == "font.style" })
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode(type: PartType(rawValue: package.manifest.identifier))
        node.setProperty(.init(rawValue: "font"), value: .choice("heading"))
        #expect(PartPackageFontControl.familyReference("font", node: node) == "body")
        guard case .object(let fields) = PartPackageFontControl.resolved("font", node: node, framework: .standard) else { Issue.record("Expected font object"); return }
        #expect(fields["style"] == nil)
    }

    @Test @MainActor
    func standaloneFrameworkFontLoadsAndRenders() throws {
        for role in ["body", "heading", "monospaced"] {
            let item = "{\"type\" : \"frameworkFont\", \"id\" : \"family\", \"defaults\" : {\"base\" : \"\(role)\"}, \"responsive\" : true}"
            let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<section {{ part.attributes }} style=\"font-family: {{ control.family.family }}\">{{ childArea(\"content\") }}</section>")
            defer { try? FileManager.default.removeItem(at: url) }
            let package = try PartPackageLoader.load(from: url)
            let definition = try #require(PartPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "family" })
            guard case .frameworkFont = definition.control else { Issue.record("Expected standalone frameworkFont"); return }
            #expect(definition.frameworkValueSource == nil)
            #expect(definition.isResponsive)
            PartRegistry.register(package)
            defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
            let node = PartNode(type: PartType(rawValue: package.manifest.identifier))
            let site = Site(name: "Fonts", pages: [Page(title: "Home", slug: "index", parts: [node])])
            let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
            #expect(html.contains("font-family: \(site.framework.fontCSSVariable(for: role))"))
        }
    }

    @Test func standaloneFrameworkFontRejectsInvalidContracts() throws {
        for value in ["accent", "custom:anything", "Arial"] {
            let item = "{\"type\" : \"frameworkFont\", \"id\" : \"family\", \"defaults\" : {\"base\" : \"\(value)\"}}"
            let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.message.contains("frameworkFont default") })
        }
        for extra in ["\"count\" : 2", "\"frameworkValues\" : \"fontFamilies\"", "\"options\" : []", "\"allowsCustom\" : false"] {
            let item = "{\"type\" : \"frameworkFont\", \"id\" : \"family\", \"defaults\" : {\"base\" : \"body\"}, \(extra)}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: item).utf8)).contains { $0.message.contains("frameworkFont control does not accept") })
        }
    }

    @Test(arguments: [0.0, 0.2, 1.0])
    func frameworkColourAcceptsInitialOpacity(alpha: Double) throws {
        let item = """
        {"type":"frameworkColor","id":"colour","opacity":true,
        "defaults":{"base":{"palette":"standard.black","opacity":\(alpha)}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "colour" })
        guard case .packageColor(let value) = definition.defaultValue else { Issue.record("Missing colour"); return }
        #expect(value.opacity == alpha)
        #expect(value.darkOpacity == alpha)
        #expect(PartPackageColorResolver.channels(value, framework: .standard, opacity: true, appearance: .light)?.alpha == alpha)
    }

    @Test func frameworkColourOpacityIsOptIn() throws {
        let item = """
        {"type":"frameworkColor","id":"colour",
        "defaults":{"base":{"palette":"standard.black"}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        let definition = try #require(PartPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "colour" })
        guard case .packageColor(_, let opacity, _, _) = definition.control,
              case .packageColor(let value) = definition.defaultValue else { Issue.record("Missing colour"); return }
        #expect(opacity == false)
        #expect(value.opacity == 1)
        let invalid = item.replacingOccurrences(of: "\"standard.black\"", with: "\"standard.black\",\"opacity\":0.2")
        let invalidURL = try makePackage(manifest: manifest(withInspectorEntries: invalid), template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: PartPackageLoadingError.self) { try PartPackageLoader.load(from: invalidURL) }
    }

    @Test(arguments: ["-0.1", "1.1", "\"0.2\"", "true"])
    func frameworkColourRejectsInvalidOpacity(alpha: String) throws {
        let item = """
        {"type":"frameworkColor","id":"colour","opacity":true,
        "defaults":{"base":{"palette":"standard.black","opacity":\(alpha)}}}
        """
        let url = try makePackage(manifest: manifest(withInspectorEntries: item), template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PartPackageLoadingError.self) { try PartPackageLoader.load(from: url) }
    }

    @Test
    func frameworkColourAcceptsAnOptionalInitialShade() throws {
        for key in ["lightShade", "darkShade"] {
        for shade in [nil, 1, 8, 11] as [Int?] {
            let item = """
            {"id" : "colour",
            "type" : "frameworkColor",
            "defaults" : {"base" : {"palette" : "accent"
            \(shade.map { ", \"\(key)\" : \($0)" } ?? "")}}}
            """
            let url = try makePackage(manifest: manifest(withInspectorEntries: item),
                                      template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>")
            defer { try? FileManager.default.removeItem(at: url) }
            let package = try PartPackageLoader.load(from: url)
            let definition = try #require(PartPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "colour" })
            guard case .packageColor(_, _, let light, let dark) = definition.control,
                  case .packageColor(let value) = definition.defaultValue else {
                Issue.record("Expected framework colour control"); continue
            }
            #expect((key == "lightShade" ? light : dark)?.rawValue == shade)
            if let shade { #expect((key == "lightShade" ? value.shade : value.darkShade).rawValue == shade) }
        }
        }
        for (type, value, initial) in [("frameworkColor", "accent", 0), ("frameworkColor", "accent", 12),
                                       ("frameworkColor", "custom", 3)] {
            let item = """
            {"id" : "colour", "type" : "\(type)",
            "defaults" : {"base" : {"palette" : "\(value)", "lightShade" : \(initial)}}}
            """
            let decoded = try JSONDecoder().decode(PartPackageManifest.self,
                from: Data(manifest(withInspectorEntries: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
                .contains { $0.location.hasSuffix(".lightShade") && $0.severity == .error })
        }
        for invalid in ["\"8\"", "true", "2.5"] {
            let item = "{\"id\" : \"colour\", \"type\" : \"frameworkColor\", \"defaults\" : {\"base\" : {\"palette\" : \"accent\", \"lightShade\" : \(invalid)}}}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: item).utf8))
                .contains { $0.message == "lightShade must be an integer." })
        }
    }

    @Test func frameworkColourRejectsOldDefaultsAndUnknownNestedKeys() throws {
        for value in ["\"accent\"", "[\"accent\"]",
                      "{\"palette\" : \"accent\", \"shade\" : 3}"] {
            let item = "{\"id\" : \"colour\", \"type\" : \"frameworkColor\", \"defaults\" : {\"base\" : \(value)}}"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: item).utf8)).contains { $0.severity == .error })
        }
        let oldKeys = "{\"id\" : \"colour\", \"type\" : \"frameworkColor\", \"defaults\" : {\"base\" : {\"palette\" : \"accent\"}}, \"lightShade\" : 8}"
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: oldKeys).utf8)).contains { $0.message.contains("Unknown key 'lightShade'") })
    }

    @Test
    func partValidationModesSelectTheIntendedPackKinds() {
        let releasePart = URL(filePath: "/Packs/Example.foundrypack/Parts/Card.foundrypart")
        let developmentPart = URL(filePath: "/Packs/Example.foundrydevpack/Parts/Card.foundrypart")

        #expect(!PartValidationMode.off.validates(releasePart))
        #expect(!PartValidationMode.off.validates(developmentPart))
        #expect(!PartValidationMode.developmentPacks.validates(releasePart))
        #expect(PartValidationMode.developmentPacks.validates(developmentPart))
        #expect(PartValidationMode.allPacks.validates(releasePart))
        #expect(PartValidationMode.allPacks.validates(developmentPart))
    }

    @Test
    func successfulValidationIsCachedButTemplateChangesAreStillValidated() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let first = try PartPackageLoader.loadForCatalog(from: packageURL, validates: true)
        #expect(first.timings.semanticValidation > .zero)

        let second = try PartPackageLoader.loadForCatalog(from: packageURL, validates: true)
        #expect(second.timings.semanticValidation == .zero)

        let templateURL = packageURL.appending(
            path: "Resources/\(first.package.manifest.render.html)"
        )
        try "<section {{ part.attributes }}>{{ control.missing }}</section>"
            .write(to: templateURL, atomically: true, encoding: .utf8)

        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.loadForCatalog(from: packageURL, validates: true)
        }
    }

    @Test
    func oldRootMacroIsRejectedWithoutAnAlias() throws {
        let url = try makePackage(
            manifest: validManifest,
            template: "<section class=\"{{ block.class }}\" {{ block.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try PartPackageLoader.load(from: url)
            Issue.record("Expected the removed block namespace to fail validation")
        } catch PartPackageLoadingError.invalid(let diagnostics) {
            #expect(diagnostics.contains {
                $0.message == "The block template namespace has been removed. Use part.class and part.attributes."
            })
        } catch {
            Issue.record("Expected validation diagnostics, received \(error)")
        }
    }

    @Test
    func partIdentifiersAllowInternalHyphensButRejectInvalidDNSLabels() throws {
        let validURL = try makePackage(
            manifest: validManifest.replacingOccurrences(
                of: "com.example.card",
                with: "com.example.focal-point-hero"
            ),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        #expect(try PartPackageLoader.load(from: validURL).manifest.identifier == "com.example.focal-point-hero")

        for identifier in ["com.example.focal_point", "com.example.-hero", "com.example.hero-", "Com.example.hero"] {
            let invalidURL = try makePackage(
                manifest: validManifest.replacingOccurrences(of: "com.example.card", with: identifier),
                template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
            )
            defer { try? FileManager.default.removeItem(at: invalidURL) }
            #expect(throws: PartPackageLoadingError.self) {
                try PartPackageLoader.load(from: invalidURL)
            }
        }
    }

    @Test
    func removedControlTypesAreRejected() {
        for type in ["fontFamily", "info", "margin", "padding"] {
            let json = """
            {
            "type" : "\(type)"
            }
            """

            do {
                _ = try JSONDecoder().decode(
                    PartPackageControl.self,
                    from: Data(json.utf8)
                )
                Issue.record("The removed \(type) control unexpectedly decoded.")
            } catch {
                // Unknown control types must fail package decoding.
            }
        }
    }

    @Test @MainActor
    func developmentFixturesValidateExpectedContracts() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appearancePackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/AppearanceToggle.foundrydevpack/Parts/AppearanceToggle"))
        try appearancePackage.preparePayload()
        #expect(appearancePackage.manifest.identifier == "dev.foundry.appearance-toggle")
        #expect(PartPackageValidator.validate(
            appearancePackage.manifest,
            rootURL: appearancePackage.resourceRootURL
        ).filter { $0.severity == .error }.isEmpty)
        let fixtureURL = repositoryURL.appending(
            path: "DevelopmentFixtures/BrokenPart.foundrydevpack",
            directoryHint: .isDirectory
        )

        let header = try FoundryPackLoader.load(from: fixtureURL)
        #expect(header.partURLs.count == 1)

        do {
            _ = try PartPackageLoader.load(from: try #require(header.partURLs.first))
            Issue.record("The intentionally broken part unexpectedly loaded.")
        } catch PartPackageLoadingError.invalid(let diagnostics) {
            #expect(diagnostics.contains { $0.message.contains("reverse-DNS") })
            #expect(diagnostics.contains { $0.message.contains("does not exist") })
        } catch {
            Issue.record("Expected part validation diagnostics, but received: \(error)")
        }

        let enablePackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/EnableConditions.foundrydevpack/Parts/EnableConditions")
        )
        #expect(enablePackage.manifest.identifier == "dev.foundry.enable-conditions")
        #expect(enablePackage.manifest.resolvedProperties.contains { $0.visibleWhen?.id == "titles[2]" })

        let frameworkPackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/FrameworkValues.foundrydevpack/Parts/FrameworkValues")
        )
        #expect(frameworkPackage.manifest.identifier == "dev.foundry.framework-values")
        #expect(!frameworkPackage.manifest.resolvedProperties.contains { $0.control.type == .select && $0.control.frameworkValues != nil })
        #expect(frameworkPackage.manifest.resolvedProperties.contains {
            $0.id == "topBorder" && $0.control.type == .frameworkColor && $0.control.allowsCustom == true
        })
        #expect(frameworkPackage.manifest.resolvedProperties.contains {
            $0.id == "bottomBorder" && $0.control.type == .frameworkColor && $0.control.allowsCustom == true
        })

        let scopedAssetsPackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ScopedAssets.foundrydevpack/Parts/ScopedAssets")
        )
        #expect(scopedAssetsPackage.manifest.identifier == "dev.foundry.scoped-assets")
        #expect(scopedAssetsPackage.manifest.assets.count == 3)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .page }.count == 2)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .site }.count == 1)

        let expressionPackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ExpressionEngine.foundrydevpack/Parts/ExpressionEngine")
        )
        #expect(expressionPackage.manifest.identifier == "dev.foundry.expression-engine")
        let expressionHTML = PartTemplateRenderer.render(
            expressionPackage.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: expressionPackage.manifest.identifier,
                properties: [
                    "status": .string("featured"),
                    "enabled": .boolean(true),
                    "score": .number(72),
                    "threshold": .number(60),
                    "base": .number(10),
                    "offset": .number(6),
                    "multiplier": .number(3),
                    "labels": .array([.string("Alpha"), .string("Beta")])
                ],
                slots: [:],
                environment: .canvas
            )
        )
        #expect(expressionHTML.contains("<strong>28</strong>"))
        #expect(expressionHTML.contains("Featured and above threshold"))
        #expect(expressionHTML.contains("Alpha · Beta"))
        #expect(expressionHTML.contains("editor-only"))
    }

    @Test
    func linkControlResolvesPagesResourcesAnchorsTargetsAndAttributes() {
        let page = Page(title: "Profile", slug: "profile")
        let asset = ProjectAsset(filename: "guide.pdf", mediaType: "application/pdf", byteCount: 10, contentDigest: "test-digest")
        let link = PartLink(
            destination: .page(page.id),
            anchor: "bio",
            opensInNewWindow: true,
            attributes: [.init(name: "title", value: "Read & learn")]
        )
        let resolved = PartLinkResolver.resolve(
            link, pages: [page], folders: [], assets: [asset],
            publicURL: "https://example.com/", absoluteURL: true
        )
        #expect(resolved.href == "https://example.com/profile/#bio")
        #expect(resolved.target == "_blank")
        #expect(resolved.attributes == "title=\"Read &amp; learn\" rel=\"noopener noreferrer\"")

        let parentPage = Page(title: "Services", slug: "services")
        let childPage = Page(
            title: "Design",
            slug: "design",
            parentPageID: parentPage.id
        )
        let nestedPageLink = PartLinkResolver.resolve(
            .init(destination: .page(childPage.id)),
            pages: [parentPage, childPage],
            folders: [],
            assets: [],
            publicURL: "",
            absoluteURL: false
        )
        #expect(nestedPageLink.href == "/services/design/")

        let resource = PartLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [], assets: [asset],
            publicURL: "", absoluteURL: true
        )
        #expect(resource.href == "/\(asset.exportPath)")

        let resourceFolder = ProjectAssetFolder(name: "Test Folder", children: [.asset(asset)])
        let nestedResource = PartLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [], assets: [asset],
            assetLibrary: [.folder(resourceFolder)], publicURL: "", absoluteURL: true
        )
        #expect(nestedResource.href == "/assets/test-folder/guide.pdf")

        let folder = PageFolder(name: "Downloads", slug: "downloads")
        var placedAsset = asset
        placedAsset.exportDirectory = .folder(folder.id)
        let placedResource = PartLinkResolver.resolve(
            .init(destination: .resource(asset.id)), pages: [page], folders: [folder], assets: [placedAsset],
            publicURL: "", absoluteURL: true
        )
        #expect(placedResource.href == "/downloads/guide.pdf")
    }

    @Test
    func linkAnchorDiscoveryIncludesOnlyPartRootAnchors() {
        let html = """
        <section data-foundry-id="ONE" id="hero"><span id="internal-label"></span></section>
        <div id="developer-id"></div>
        <article data-foundry-id="TWO" id="contact"></article>
        """

        #expect(PartAnchorDiscovery.identifiers(in: html) == ["hero", "contact"])
    }

    @Test
    func backgroundVideoRequiresExplicitOptIn() throws {
        let data = Data(manifest(withInspectorEntries: #"{"type":"background","id":"background"}"#).utf8)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        let group = try #require(decoded.controlGroups.first)
        #expect(group.backgroundTypes == [.colour, .image, .gradient])
        #expect(group == PartPackageControlGroup(type: .background, id: "background"))
        #expect(group.properties.contains { $0.control.type == .video } == false)
        #expect(group.properties.first { $0.id == "background.backgroundStyle" }?.control.options?.map(\.value) == ["color", "image", "gradient"])
        let invalid = Data(manifest(withInspectorEntries: #"{"type":"background","id":"background","allowedOptions":{"backgroundStyle":["video"]}}"#).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: invalid).contains { $0.severity == .error })
        let explicit = Data(manifest(withInspectorEntries: #"{"type":"background","id":"background","backgroundTypes":["video"],"defaults":{"backgroundStyle":"video"}}"#).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: explicit).contains { $0.severity == .error } == false)
        let optedIn = try JSONDecoder().decode(PartPackageManifest.self, from: explicit)
        #expect(optedIn.resolvedProperties.contains { $0.control.type == .video })
    }

    @Test
    func backgroundControlGroupExpandsIntoFoundryOwnedControls() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.background-group",
        "title" : "Background Group",
        "version" : "1.0.0",
        "inspector" : [{"type" : "background", "id": "background", "backgroundTypes": ["colour", "image", "gradient", "video"]}],
        "templates" : {"html" : "part.html"}
        }
        """

        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups == [.init(type: .background, id: "background", backgroundTypes: PartPackageControlGroup.BackgroundStyle.allCases)])
        #expect(manifest.resolvedProperties.first?.id == "background.backgroundMode")
        #expect(manifest.resolvedProperties.first?.defaultValue == .string("none"))
        #expect(manifest.resolvedProperties.contains { $0.id == "background.backgroundImage" && $0.control.type == .image })
        #expect(manifest.resolvedProperties.contains { $0.id == "background.backgroundGradientFrom" && $0.control.type == .frameworkColor })
        #expect(manifest.resolvedProperties.contains { $0.id == "background.backgroundVideo" && $0.control.type == .video })
        let videoLoop = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundVideoLoop" })
        #expect(videoLoop.defaultValue == .boolean(true))
        #expect(manifest.resolvedProperties.contains { $0.id == "background.backgroundVideoPingPong" } == false)
        let staticStyle = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundStyle" })
        #expect(staticStyle.control.options?.map(\.value) == ["color", "image", "gradient", "video"])
        let hoverStyle = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundHoverStyle" })
        #expect(hoverStyle.control.options?.map(\.value) == ["color", "image", "gradient"])
        #expect(hoverStyle.defaultValue == .string("color"))
        #expect(!manifest.resolvedProperties.contains { $0.id.hasPrefix("backgroundHoverVideo") })
        #expect(!manifest.resolvedProperties.contains { $0.id == "backgroundVideoAspectRatio" })
        let video = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundVideo" })
        #expect(video.visibleWhen == .init(all: [
            .init(id: "background.backgroundMode", value: .string("static")),
            .init(id: "background.backgroundStyle", value: .string("video"))
        ]))
        #expect(manifest.controlGroupCSS.isEmpty)
        #expect(manifest.htmlContributions.isEmpty)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func backgroundControlGroupCanSelectTypesAndDisableHover() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.selective-background-group",
        "title" : "Selective Background Group",
        "version" : "1.0.0",
        "inspector" : [{
            "type" : "background", "id": "background",
            "backgroundTypes" : ["colour", "image"],
            "supportsHover": false
        }],
        "templates" : {"html" : "part.html"}
        }
        """

        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups == [
            .init(type: .background, id: "background", backgroundTypes: [.colour, .image], supportsHover: false)
        ])
        let identifiers = Set(manifest.resolvedProperties.map(\.id))
        #expect(identifiers.contains("background.backgroundColor"))
        #expect(identifiers.contains("background.backgroundImage"))
        #expect(!identifiers.contains("background.backgroundGradientType"))
        #expect(!identifiers.contains("background.backgroundVideo"))
        #expect(!identifiers.contains("background.backgroundVideoLoop"))
        #expect(!identifiers.contains("background.backgroundVideoPingPong"))
        #expect(!identifiers.contains("background.backgroundHoverStyle"))
        let mode = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundMode" })
        #expect(mode.control.options?.map(\.value) == ["none", "static"])
        let style = try #require(manifest.resolvedProperties.first { $0.id == "background.backgroundStyle" })
        #expect(style.control.options?.map(\.value) == ["color", "image"])
        #expect(style.defaultValue == .string("color"))
        #expect(!manifest.controlGroupCSS.contains(#"[data-foundry-control-group-background="{{ instance.id }}"]:hover"#))
        #expect(!manifest.controlGroupCSS.contains("backgroundGradient"))
        #expect(!manifest.controlGroupCSS.contains("background.backgroundVideo"))
        #expect(manifest.htmlContributions.isEmpty)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func backgroundControlGroupValidatesTypesAndHoverSupport() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.invalid-background-group",
        "title" : "Invalid Background Group",
        "version" : "1.0.0",
        "inspector" : [{
            "type" : "background", "id": "background",
            "backgroundTypes" : [],
            "supportsHover" : "yes"
        }],
        "templates" : {"html" : "part.html"}
        }
        """

        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(json.utf8))
        let messages = diagnostics.map(\.message)
        #expect(messages.contains("backgroundTypes must contain at least one value."))
        #expect(diagnostics.contains { $0.message == "supportsHover must be a Boolean." && $0.severity == .error })
    }

    @Test(arguments: [
        #""states":["static"]"#, #""styles":["colour"]"#,
        #""defaultOverrides":{}"#, #""optionOverrides":{}"#,
        #""omit":["backgroundRepeat"]"#, #""target":".content""#
    ])
    func controlGroupsRejectOldConfigurationNames(_ setting: String) throws {
        let entry = #"{"type":"background","id":"surface",\#(setting)}"#
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entry).utf8))
        #expect(diagnostics.contains { $0.severity == .error && $0.message.contains("Unknown key") })
    }

    @Test(arguments: [#""supportsHover":false"#, #""backgroundTypes":["colour"]"#])
    func backgroundCapabilitiesAreRejectedOnOtherGroups(_ setting: String) throws {
        let entry = #"{"type":"sizing","id":"size",\#(setting)}"#
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entry).utf8))
        #expect(diagnostics.contains { $0.severity == .error && $0.message.contains("only on Background") })
    }

    @Test
    func simpleGroupConfigurationRoundTrips() throws {
        let data = Data(#"{"type":"background","id":"surface","backgroundTypes":["colour","image"],"supportsHover":false,"defaults":{"backgroundMode":"static"},"excludeControls":["backgroundRepeat"],"allowedOptions":{"backgroundSize":["cover","contain"]}}"#.utf8)
        let group = try JSONDecoder().decode(PartPackageControlGroup.self, from: data)
        let encoded = try JSONEncoder().encode(group)
        #expect(try JSONDecoder().decode(PartPackageControlGroup.self, from: encoded) == group)
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(keys.keys) == ["type", "id", "backgroundTypes", "supportsHover", "defaults", "excludeControls", "allowedOptions"])
        #expect(group.supportsHover == false)
        #expect(group.properties.first { $0.id == "surface.backgroundMode" }?.defaultValue == .string("static"))
        #expect(group.properties.contains { $0.id == "surface.backgroundRepeat" } == false)
        #expect(group.properties.first { $0.id == "surface.backgroundSize" }?.control.options?.map(\.value) == ["cover", "contain"])
    }

    @Test
    func backgroundGroupResolvesFinishedValuesForEveryLayer() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.background-values",
        "title" : "Background Values",
        "version" : "1.0.0",
        "inspector" : [{"type" : "background", "id": "background", "backgroundTypes": ["colour", "image", "gradient", "video"]}],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))

        func resolved(
            _ values: [String: PartPackageValue],
            enablesEditorMarkup: Bool = false
        ) -> [String: PartPackageValue] {
            var values = values
            PartPackageBackgroundResolver.resolve(
                &values,
                properties: manifest.resolvedProperties,
                enablesEditorMarkup: enablesEditorMarkup
            )
            return values
        }

        // An untouched background contributes nothing, and hover mirrors it so
        // a template's :hover block is a safe no-op.
        let untouched = resolved(["background.backgroundMode": .string("none")])
        #expect(untouched["background.color"] == .string("transparent"))
        #expect(untouched["background.image"] == .string("none"))
        #expect(untouched["background.video"] == .string(""))
        #expect(untouched["background.hover.color"] == .string("transparent"))

        let colour = resolved([
            "background.backgroundMode": .string("static"),
            "background.backgroundStyle": .string("color"),
            "background.backgroundColor": .string("#112233")
        ])
        #expect(colour["background.color"] == .string("#112233"))
        #expect(colour["background.hover.color"] == .string("#112233"))

        for (type, expected) in [
            ("linear", "linear-gradient(to bottom, #112233 0%, #AABBCC 100%)"),
            ("radial", "radial-gradient(#112233 0%, #AABBCC 100%)"),
            ("conic", "conic-gradient(#112233 0%, #AABBCC 100%)")
        ] {
            let gradient = resolved([
                "background.backgroundMode": .string("static"),
                "background.backgroundStyle": .string("gradient"),
                "background.backgroundGradientType": .string(type),
                "background.backgroundGradientDirection": .string("to bottom"),
                "background.backgroundGradientFrom": .string("#112233"),
                "background.backgroundGradientFromPosition": .number(0),
                "background.backgroundGradientTo": .string("#AABBCC"),
                "background.backgroundGradientToPosition": .number(100)
            ])
            #expect(gradient["background.image"] == .string(expected))
            #expect(gradient["background.color"] == .string("transparent"))
        }

        let image = resolved([
            "background.backgroundMode": .string("static"),
            "background.backgroundStyle": .string("image"),
            "background.backgroundImage": .string("assets/hero.jpg"),
            PartPackageAdapter.imageFocalPointKey(for: "background.backgroundImage").rawValue: .array([.number(50), .number(0)]),
            "background.backgroundSize": .string("contain"),
            "background.backgroundRepeat": .string("repeat-x")
        ])
        #expect(image["background.image"] == .string(#"url("assets/hero.jpg")"#))
        #expect(image["background.position"] == .string("50% 0%"))
        #expect(image["background.size"] == .string("contain"))
        #expect(image["background.repeat"] == .string("repeat-x"))
        // One value carries the whole layer so a part needs a single
        // interpolation to adopt the group.
        #expect(image["background.css"] == .string(
            #"background-color: transparent; background-image: url("assets/hero.jpg"); "#
                + "background-position: 50% 0%; background-size: contain; background-repeat: repeat-x;"
        ))

        // A static video supplies its element; the canvas shows the poster
        // rather than loading the movie. Video is deliberately unavailable as
        // a hover style.
        let videoValues: [String: PartPackageValue] = [
            "background.backgroundMode": .string("static"),
            "background.backgroundStyle": .string("video"),
            "background.backgroundVideo.href": .string(#"assets/film&trailer.mp4"#),
            "background.backgroundVideo.poster": .string("data:image/jpeg;base64,poster-frame")
        ]
        let published = resolved(videoValues)
        let publishedVideo = published["background.video"]?.stringValue ?? ""
        #expect(publishedVideo.contains(#"class="foundry-background-video""#))
        #expect(publishedVideo.contains(#"src="assets/film&amp;trailer.mp4""#))
        #expect(publishedVideo.contains(#"poster="data:image/jpeg;base64,poster-frame""#))
        #expect(publishedVideo.contains("autoplay muted loop playsinline"))
        #expect(published["background.videoCSS"] == nil)
        #expect(publishedVideo.hasPrefix(#"<div class="foundry-background-layer" aria-hidden="true">"#))
        #expect(publishedVideo.hasSuffix("</video></div>"))
        let publishedCSS = published["background.css"]?.stringValue ?? ""
        #expect(publishedCSS.contains("position: relative") == false)
        #expect(publishedCSS.contains("isolation:") == false)
        #expect(publishedCSS.contains("overflow:") == false)
        #expect(published["background.hover.video"] == .string(""))
        #expect(published["background.hover.videoCSS"] == nil)

        #expect(publishedVideo.contains("<script") == false)
        #expect(publishedVideo.contains("data-foundry-ping-pong") == false)
        let singlePlay = resolved(videoValues.merging([
            "background.backgroundVideoLoop": .boolean(false)
        ]) { _, replacement in replacement })
        let singlePlayVideo = singlePlay["background.video"]?.stringValue ?? ""
        #expect(singlePlayVideo.contains(" loop ") == false)
        #expect(singlePlayVideo.contains("<script") == false)

        let canvas = resolved(videoValues, enablesEditorMarkup: true)
        let canvasVideo = canvas["background.video"]?.stringValue ?? ""
        #expect(canvasVideo.contains(#"<img class="foundry-background-video""#))
        #expect(canvasVideo.contains(#"src="data:image/jpeg;base64,poster-frame""#))
        #expect(!canvasVideo.contains("<video"))
        #expect(!canvasVideo.contains("autoplay"))
    }

    @Test
    func flexboxGroupComposesItsContainerDeclarations() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.flexbox-values",
        "title" : "Flexbox Values",
        "version" : "1.0.0",
        "inspector" : [{"type" : "flexbox", "id": "flexbox"}],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))

        // Untouched values fall back to the group's own defaults, so a
        // template needs no conditionals.
        var untouched: [String: PartPackageValue] = [:]
        PartPackageControlGroupCSSResolver.resolve(&untouched, properties: manifest.resolvedProperties)
        #expect(untouched["flexbox.css"] == .string(
            "display: flex; flex-direction: column; flex-wrap: nowrap; "
                + "column-gap: 0; row-gap: 0; align-items: flex-start; "
                + "align-content: flex-start; justify-content: flex-start;"
        ))

        var values: [String: PartPackageValue] = [
            "flexbox.direction": .string("row"),
            "flexbox.wrap": .string("wrap"),
            "flexbox.columnGap": .string("var(--foundry-space-md)"),
            "flexbox.rowGap": .string("24px"),
            "flexbox.alignItems": .string("stretch"),
            "flexbox.alignContent": .string("space-between"),
            "flexbox.justifyContent": .string("center")
        ]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
        #expect(values["flexbox.css"] == .string(
            "display: flex; flex-direction: row; flex-wrap: wrap; "
                + "column-gap: var(--foundry-space-md); row-gap: 24px; align-items: stretch; "
                + "align-content: space-between; justify-content: center;"
        ))

        let rendered = PartTemplateRenderer.render(
            ":instance { {{ control.flexbox.css }} }",
            context: PartTemplateContext(
                instanceID: UUID(),
                packageIdentifier: manifest.identifier,
                properties: values,
                slots: [:]
            )
        )
        let composed = values["flexbox.css"]?.stringValue ?? ""
        #expect(rendered == ":instance { \(composed) }")

        // A part without the group keeps the namespace clear.
        var unrelated: [String: PartPackageValue] = ["flexbox.direction": .string("row")]
        PartPackageControlGroupCSSResolver.resolve(&unrelated, properties: [])
        #expect(unrelated["flexbox.css"] == nil)
    }

    /// Every group that maps onto a set of declarations composes them, so the
    /// details a part would otherwise hand-write — the enabled toggles'
    /// explicit resets and Layout's
    /// "emit nothing" sentinels — live in one place.
    @Test
    func everyStylingGroupComposesItsDeclarations() throws {
        func composed(_ kind: String, values: [String: PartPackageValue]) throws -> String? {
            let json = """
            {
            "minimumAPIVersion" : 1,
            "id" : "com.example.\(kind)-css",
            "title" : "\(kind) CSS",
            "version" : "1.0.0",
            "inspector" : [{"type" : "\(kind)", "id" : "\(kind)"}],
            "templates" : {"html" : "part.html"}
            }
            """
            let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
            var values = Dictionary(uniqueKeysWithValues: values.map { (kind + "." + $0.key, $0.value) })
            PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
            return values["\(kind).css"]?.stringValue
        }

        // Disabled spacing writes explicit zeros, so switching it off at one
        // breakpoint resets what a narrower one set.
        #expect(try composed("spacing", values: [
            "spacingEnabled": .boolean(true),
            "frameworkPadding": .string("var(--foundry-space-md)"),
            "frameworkMargin": .string("0 auto")
        ]) == "padding: var(--foundry-space-md); margin: 0 auto;")
        #expect(try composed("spacing", values: [
            "spacingEnabled": .boolean(false),
            "frameworkPadding": .string("var(--foundry-space-md)"),
            "frameworkMargin": .string("0 auto")
        ]) == "padding: 0; margin: 0;")

        // Style and colour survive being disabled; a zero width is what stops
        // the border drawing.
        #expect(try composed("borders", values: [
            "borderEnabled": .boolean(true),
            "frameworkBorder.width": .string("var(--foundry-border-width-sm)"),
            "frameworkBorder.style": .string("dashed"),
            "frameworkBorderColour": .string("#112233"),
            "frameworkRadius": .string("var(--foundry-border-radius-md)")
        ]) == "border-width: var(--foundry-border-width-sm); border-style: dashed; "
            + "border-color: #112233; border-radius: var(--foundry-border-radius-md);")
        #expect(try composed("borders", values: [
            "borderEnabled": .boolean(false),
            "frameworkBorder.width": .string("var(--foundry-border-width-sm)"),
            "frameworkBorder.style": .string("dashed"),
            "frameworkBorderColour": .string("#112233"),
            "frameworkRadius": .string("var(--foundry-border-radius-md)")
        ]) == "border-width: 0; border-style: dashed; border-color: #112233; border-radius: 0;")

        // Shadow emits its selected value while enabled and an explicit reset
        // while disabled.
        #expect(try composed("effects", values: [
            "effectsEnabled": .boolean(true),
            "frameworkShadow": .string("var(--foundry-shadow-lg)")
        ]) == "box-shadow: var(--foundry-shadow-lg);")
        #expect(try composed("effects", values: [
            "effectsEnabled": .boolean(false),
            "frameworkShadow": .string("var(--foundry-shadow-lg)")
        ]) == "box-shadow: none;")

        // An untouched Layout group contributes nothing at all.
        // Isolation belongs to the part stylesheet, never Layout output.
        #expect(try composed("layout", values: ["isolation": .string("isolate")]) == "")
        #expect(try composed("layout", values: [
            "position": .string("none"), "zIndexMode": .string("none"),
            "offsets": .string("none"), "hidden": .boolean(false),
            "visibility": .string("default"), "overflow": .string("none")
        ]) == "")
        #expect(try composed("layout", values: [
            "position": .string("sticky"), "zIndexMode": .string("custom"), "zIndex": .number(3),
            "offsets": .string("uniform"), "offset": .string("var(--foundry-space-sm)"),
            "hidden": .boolean(true), "visibility": .string("hidden"),
            "overflow": .string("auto")
        ]) == "position: sticky; z-index: 3; inset: var(--foundry-space-sm); "
            + "display: none; visibility: hidden; overflow: auto;")

        // Reveal and Advanced style nothing, so they compose nothing.
        #expect(try composed("reveal", values: ["revealEnabled": .boolean(true)]) == nil)
        #expect(try composed("advanced", values: [:]) == nil)

        // Sizing's filling modes use the `stretch` family rather than a
        // percentage, so a part carrying horizontal margins cannot overflow
        // its parent. The rail leads and each cap overrides it in turn.
        let fills = "width: -webkit-fill-available; width: -moz-available; width: stretch;"
        #expect(try composed("sizing", values: [
            "widthMode": .string("auto"), "heightMode": .string("auto"),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; width: auto; flex-grow: 0; height: auto; aspect-ratio: auto; min-width: 0; min-height: 0; max-height: none;")
        #expect(try composed("sizing", values: [
            "widthMode": .string("full"), "heightMode": .string("fill"),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; \(fills) flex-grow: 1; height: auto; aspect-ratio: auto; min-width: 0; min-height: 0; max-height: none;")
        #expect(try composed("sizing", values: [
            "widthMode": .string("custom"), "customWidth": .number(640),
            "heightMode": .string("custom"), "customHeight": .number(400),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; \(fills) max-width: min(100%, 640px); flex-grow: 0; height: 400px; "
            + "aspect-ratio: auto; min-width: 0; min-height: 0; max-height: none;")
        #expect(try composed("sizing", values: [
            "widthMode": .string("breakpoint"), "heightMode": .string("viewport"),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("var(--foundry-space-xl)"), "maxHeight": .string("none")
        ]) == "max-width: 100%; \(fills) max-width: min(100%, var(--foundry-container-width)); "
            + "flex-grow: 0; height: auto; min-height: max(100svh, var(--foundry-space-xl)); aspect-ratio: auto; min-width: 0; max-height: none;")
        // Screen escapes the rail; an author's maximum still caps it, and
        // wins over both because it is written last.
        #expect(try composed("sizing", values: [
            "widthMode": .string("screen"), "heightMode": .string("auto"),
            "minWidth": .string("0"), "maxWidth": .string("var(--foundry-space-4xl)"),
            "minHeight": .string("0"), "maxHeight": .string("48rem")
        ]) == "max-width: 100%; width: 100svw; max-width: none; flex-grow: 0; height: auto; aspect-ratio: auto; min-width: 0; "
            + "max-width: min(100%, var(--foundry-space-4xl)); min-height: 0; max-height: 48rem;")
        // A ratio shapes the part only while its height follows the content;
        // a custom ratio composes its two numbers.
        #expect(try composed("sizing", values: [
            "widthMode": .string("auto"), "heightMode": .string("auto"), "aspectRatio": .string("16 / 9"),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; width: auto; flex-grow: 0; height: auto; aspect-ratio: 16 / 9; min-width: 0; min-height: 0; max-height: none;")
        #expect(try composed("sizing", values: [
            "widthMode": .string("auto"), "heightMode": .string("auto"), "aspectRatio": .string("custom"),
            "aspectRatioWidth": .number(5), "aspectRatioHeight": .number(2),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; width: auto; flex-grow: 0; height: auto; aspect-ratio: 5 / 2; min-width: 0; min-height: 0; max-height: none;")
        #expect(try composed("sizing", values: [
            "widthMode": .string("auto"), "heightMode": .string("custom"), "customHeight": .number(300), "aspectRatio": .string("16 / 9"),
            "minWidth": .string("0"), "maxWidth": .string("none"),
            "minHeight": .string("0"), "maxHeight": .string("none")
        ]) == "max-width: 100%; width: auto; flex-grow: 0; height: 300px; aspect-ratio: auto; min-width: 0; min-height: 0; max-height: none;")
    }

    /// Custom controls with familiar IDs must not implicitly acquire group output.
    @Test
    func handDeclaredControlsDoNotComposeGroupCSS() throws {
        let controls = """
        {"type":"select","id":"direction","label":"Direction","responsive":true,
         "options":[{"value":"column","title":"Column"},{"value":"row","title":"Row"}],
         "defaults":{"base":"column"}},
        {"type":"select","id":"wrap","label":"Wrap","responsive":true,
         "options":[{"value":"nowrap","title":"No wrap"},{"value":"wrap","title":"Wrap"}],
         "defaults":{"base":"nowrap"}},
        {"type":"frameworkSpacing","id":"columnGap","label":"H gap","responsive":true,"defaults":{"base":"md"}},
        {"type":"frameworkSpacing","id":"rowGap","label":"V gap","responsive":true,"defaults":{"base":"md"}},
        {"type":"select","id":"alignItems","label":"Align","responsive":true,
         "options":[{"value":"stretch","title":"Stretch"},{"value":"center","title":"Centre"}],
         "defaults":{"base":"stretch"}},
        {"type":"select","id":"alignContent","label":"Align content","responsive":true,
         "options":[{"value":"flex-start","title":"Start"}],"defaults":{"base":"flex-start"}},
        {"type":"select","id":"justifyContent","label":"Justify","responsive":true,
         "options":[{"value":"center","title":"Centre"}],"defaults":{"base":"center"}}
        """
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.hand-declared-flexbox",
        "title" : "Hand Declared",
        "version" : "1.0.0",
        "inspector" : [{"section" : "Layout", "controls" : [\(controls)]}],
        "templates" : {"html" : "part.html", "files" : [{"path" : "part.css", "scope" : "instance"}]}
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        // No group was referenced, so none of the group-owned CSS is generated.
        #expect(manifest.controlGroups.isEmpty)
        #expect(manifest.controlGroupCSS.isEmpty)

        // No explicit group identity means no composed namespace.
        #expect(PartPackageControlGroupCSSResolver.composedNamespaces(for: manifest.resolvedProperties)
            .isEmpty)
        var values: [String: PartPackageValue] = [
            "direction": .string("row"), "wrap": .string("wrap"),
            "columnGap": .string("16px"), "rowGap": .string("8px"),
            "alignItems": .string("stretch"), "alignContent": .string("flex-start"),
            "justifyContent": .string("center")
        ]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
        #expect(values["flexbox.css"] == nil)

        // Template validation rejects the undeclared group's output.
        let packageURL = try makePackage(
            manifest: json,
            template: #"<div class="{{ part.class }}" {{ part.attributes }}>{{ dropZone("content") }}</div>"#,
            additionalFiles: ["part.css": ":instance { {{ control.flexbox.css }} }"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        #expect(throws: PartPackageLoadingError.self) {
            let package = try PartPackageLoader.load(from: packageURL)
            try package.preparePayload()
        }

        // A group the part has none of composes nothing, so its namespace
        // stays unknown and a template referencing it is still an error.
        #expect(!PartPackageControlGroupCSSResolver
            .composedNamespaces(for: manifest.resolvedProperties).contains("spacing"))
    }

    @Test @MainActor
    func namedSizingGroupsRemainIndependentThroughSaveAndRender() throws {
        let entries = #"{"type":"sizing","id":"sectionSize","excludeControls":["widthMode","minWidth","maxWidth"],"defaults":{"customHeight":500}}, {"type":"sizing","id":"contentSize","allowedOptions":{"widthMode":["full","custom"]},"defaults":{"widthMode":"custom","customWidth":400}}"#
        let url = try makePackage(manifest: manifest(withInspectorEntries: entries),
            template: #"<section class="{{ part.class }}" {{ part.attributes }}><div class="content">{{ childArea("content") }}</div></section>"#,
            additionalFiles: ["part.css": ":instance { {{ control.sectionSize.css }} } :instance > .content { {{ control.contentSize.css }} }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        try package.preparePayload()
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let roundTrip = try JSONDecoder().decode(PartPackageManifest.self, from: JSONEncoder().encode(package.manifest))
        #expect(roundTrip.resolvedProperties == package.manifest.resolvedProperties)
        #expect(roundTrip.resolvedProperties.contains { $0.id == "sectionSize.widthMode" } == false)
        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        let contentWidth = PartProperty.Key(rawValue: "contentSize.customWidth")
        node.setResponsiveProperty(contentWidth, value: .number(640), at: .medium)
        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(node))
        #expect(restored.propertyValue(contentWidth, at: .medium) == .number(640))
        let custom = try #require(roundTrip.resolvedProperties.first { $0.id == "contentSize.customWidth" })
        #expect(PartPackageVisibilityEvaluator.isVisible(custom.visibleWhen, for: restored, at: .mobile))
        let site = Site(name: "Named sizing", pages: [Page(title: "Home", slug: "index", parts: [restored])])
        let export = StaticSiteRenderer().render(site: site)
        #expect(export.files.contains { $0.contents.contains("max-width: min(100%, 400px)") })
        #expect(export.files.contains { $0.contents.contains("max-width: min(100%, 640px)") })
        let canvas = HTMLPageRenderer(site: site)
        #expect(canvas.render(page: site.pages[0], language: "en", framework: site.framework, assets: [:], breakpoint: .mobile).contains("max-width: min(100%, 400px)"))
        #expect(canvas.render(page: site.pages[0], language: "en", framework: site.framework, assets: [:], breakpoint: .medium).contains("max-width: min(100%, 640px)"))
    }

    @Test(arguments: PartPackageControlGroup.Kind.allCases)
    func groupsDoNotExposeStyleStateAndRejectRemovedOption(_ kind: PartPackageControlGroup.Kind) throws {
        let entry = kind == .advanced ? "{\"type\":\"advanced\"}" : "{\"type\":\"\(kind.rawValue)\",\"id\":\"panel\"}";
        let data = Data(manifest(withInspectorEntries: entry).utf8)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(decoded.resolvedProperties.contains { $0.id == "panel.state" } == false)
        let removed = entry.dropLast() + ",\"stateControl\":true}"
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: String(removed)).utf8))
        #expect(diagnostics.contains { $0.location.contains("stateControl") || $0.message.contains("stateControl") })
    }

    @Test
    func namedBackgroundOutputIsComposedAndEscapedOnce() throws {
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: #"{"type":"background","id":"surface","backgroundTypes":["colour","image","gradient","video"]},{"type":"background","id":"other"}"#).utf8))
        var values: [String: PartPackageValue] = ["surface.backgroundMode": .string("static"), "surface.backgroundStyle": .string("video"), "surface.backgroundVideo.href": .string("movie&clip.mp4"), "other.backgroundMode": .string("none")]
        PartPackageBackgroundResolver.resolve(&values, properties: decoded.resolvedProperties, enablesEditorMarkup: false)
        let output = PartTemplateRenderer.render("{{ control.surface.video }}", context: .init(instanceID: UUID(), packageIdentifier: decoded.identifier, properties: values, slots: [:]))
        #expect(output.contains("<video"))
        #expect(output.contains("movie&amp;clip.mp4"))
        #expect(output.contains("&amp;amp;") == false)
        #expect(values["other.video"] == .string(""))
        #expect(values["background.video"] == nil)
    }

    @Test(arguments: [
        #"{"type":"sizing","id":"same"},{"type":"spacing","id":"same"}"#,
        #"{"type":"sizing","id":"bad.id"}"#,
        #"{"type":"advanced","id":"identity"}"#,
        #"{"type":"reveal", "id": "reveal","stateControl":true}"#,
        #"{"type":"sizing","id":"panel","defaults":{"panel.customWidth":400}}"#
    ])
    func invalidGroupNamespacesAndStatesAreRejected(entries: String) throws {
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entries).utf8)).isEmpty == false)
    }

    @Test
    func namedGroupRejectsOmittedTemplateControlAndNamespaceCollision() throws {
        for (entries, template) in [
            (#"{"type":"sizing","id":"panel","excludeControls":["widthMode"]}"#, "{{ control.panel.widthMode }}"),
            (#"{"type":"sizing","id":"panel"},{"type":"number","id":"panel","defaults":{"base":1}}"#, "")
        ] {
            let url = try makePackage(manifest: manifest(withInspectorEntries: entries), template: "<section class=\"{{ part.class }}\" {{ part.attributes }}>\(template){{ childArea(\"content\") }}</section>")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let package = try PartPackageLoader.load(from: url)
                try package.preparePayload()
                Issue.record("Expected a namespace or omitted-control validation error")
            } catch PartPackageLoadingError.invalid(let diagnostics) {
                #expect(diagnostics.contains { $0.message.contains("Unknown property 'panel.widthMode'") || $0.message.contains("conflicts with a control group namespace") })
            }
        }
    }

    /// `omit` narrows the composed block too, rather than leaving it
    /// referencing controls the part removed.
    @Test
    func composedGroupCSSFollowsOmittedControls() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.omitted-css",
        "title" : "Omitted CSS",
        "version" : "1.0.0",
        "inspector" : [
            {"type" : "spacing", "id": "spacing", "excludeControls" : ["frameworkMargin"]},
            {"type" : "effects", "id": "effects", "excludeControls" : ["frameworkShadow"]}
        ],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        var values: [String: PartPackageValue] = [
            "spacing.spacingEnabled": .boolean(true),
            "spacing.frameworkPadding": .string("12px"),
            "effects.effectsEnabled": .boolean(true)
        ]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
        #expect(values["spacing.css"] == .string("padding: 12px;"))
        #expect(values["effects.css"] == .string(""))
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    /// The group's values are finished CSS and markup, so they reach a
    /// template verbatim: HTML-escaping them turned `url("…")` into
    /// `url(&quot;…&quot;)` and the video element into visible text.
    @Test
    func backgroundGroupValuesReachTemplatesUnescaped() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.background-escaping",
        "title" : "Background Escaping",
        "version" : "1.0.0",
        "inspector" : [{"type" : "background", "id": "background", "backgroundTypes": ["colour", "image", "gradient", "video"]}],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))

        func rendered(_ template: String, values: [String: PartPackageValue]) -> String {
            var values = values
            PartPackageBackgroundResolver.resolve(
                &values,
                properties: manifest.resolvedProperties,
                enablesEditorMarkup: false
            )
            return PartTemplateRenderer.render(template, context: PartTemplateContext(
                instanceID: UUID(),
                packageIdentifier: manifest.identifier,
                properties: values,
                slots: [:]
            ))
        }

        let css = rendered(":instance { {{ control.background.css }} }", values: [
            "background.backgroundMode": .string("static"),
            "background.backgroundStyle": .string("image"),
            "background.backgroundImage": .string("foundry-asset:B0A1C2D3")
        ])
        #expect(css.contains(#"background-image: url("foundry-asset:B0A1C2D3");"#))
        #expect(!css.contains("&quot;"))

        let html = rendered("<div>{{ control.background.video }}</div>", values: [
            "background.backgroundMode": .string("static"),
            "background.backgroundStyle": .string("video"),
            "background.backgroundVideo.href": .string("assets/film.mp4"),
            "background.backgroundVideo.poster": .string("assets/film.jpg")
        ])
        #expect(html.contains(#"<video class="foundry-background-video" src="assets/film.mp4""#))
        #expect(!html.contains("&lt;"))
    }

    @Test
    func sharedPropertyControlGroupsInjectPropertiesWithoutCSSOrHTML() throws {
        for (kind, expectedIDs) in [
            ("spacing", ["spacingEnabled", "frameworkMargin", "frameworkPadding"]),
            ("sizing", ["widthMode", "customWidth", "heightMode", "customHeight", "aspectRatio", "aspectRatioWidth", "aspectRatioHeight", "minWidth", "maxWidth", "minHeight", "maxHeight"]),
            ("borders", ["borderEnabled", "frameworkBorder", "frameworkBorderColour", "frameworkRadius"]),
            ("effects", ["effectsEnabled", "frameworkShadow"]),
            ("layout", ["position", "zIndexMode", "zIndex", "offsets", "offset", "offsetEdges", "hidden", "visibility", "overflow"]),
            ("flexbox", ["direction", "wrap", "columnGap", "rowGap", "alignItems", "alignContent", "justifyContent"])
        ] {
            let json = """
            {
            "minimumAPIVersion" : 1,
            "id" : "com.example.\(kind)-group",
            "title" : "\(kind) Group",
            "version" : "1.0.0",
            "inspector" : [{"type" : "\(kind)", "id": "\(kind)"}],
            "templates" : {"html" : "part.html"}
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
            #expect(manifest.resolvedProperties.map(\.id) == expectedIDs.map { kind + "." + $0 })
            #expect(manifest.controlGroupCSS.isEmpty)
            #expect(manifest.htmlContributions.isEmpty)
            #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        }
    }

    @Test
    func flexboxChildCSSCanTargetAnInnerContainer() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.flexbox-child-rule",
        "title" : "Flexbox Child Rule",
        "version" : "1.0.0",
        "inspector" : [{"type" : "flexbox", "id": "flexbox"}],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
        let instanceID = UUID()
        var values: [String: PartPackageValue] = [:]
        PartPackageControlGroupCSSResolver.resolve(&values, properties: manifest.resolvedProperties)
        #expect(manifest.controlGroupCSS.isEmpty)
        #expect(values["flexbox.childCSS"] == .string("min-width: 0;"))
        let css = PartTemplateRenderer.render(
            ":instance > .content > * { {{ control.flexbox.childCSS }} }",
            context: .init(instanceID: instanceID, packageIdentifier: manifest.identifier, properties: values, slots: [:])
        )
        let scoped = PartTemplateRenderer.scopedCSS(
            css,
            packageIdentifier: manifest.identifier,
            instanceID: instanceID
        )
        #expect(scoped == "[data-foundry-id=\"\(instanceID.uuidString)\"] > .content > * { min-width: 0; }")
        let url = try makePackage(manifest: json, template: "<section {{ part.attributes }}><div class=\"content\"></div></section>", additionalFiles: ["part.css": ":instance > .content > * { {{ control.flexbox.childCSS }} }"])
        defer { try? FileManager.default.removeItem(at: url) }
        try PartPackageLoader.load(from: url).preparePayload()
    }

    @Test
    func groupReferenceVisibleWhenGatesEveryExpandedControl() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.gated-groups",
        "title" : "Gated Groups",
        "version" : "1.0.0",
        "inspector" : [
            {"type" : "select", "id" : "layout", "label" : "Layout",
             "options" : [{"value" : "block", "title" : "Block"}, {"value" : "flex", "title" : "Flex"}],
             "defaults" : {"base" : "block"}},
            {"type" : "flexbox", "id": "flexbox", "visibleWhen" : {"id" : "layout", "value" : "flex"},
             "defaults" : {"wrap" : "wrap"}},
            {"type" : "spacing", "id": "spacing", "visibleWhen" : {"id" : "layout", "value" : "flex"}}
        ],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)

        // Every flexbox control inherits the reference's gate verbatim…
        let direction = try #require(manifest.resolvedProperties.first { $0.id == "flexbox.direction" })
        #expect(direction.visibleWhen == .init(id: "layout", value: .string("flex")))
        let wrap = try #require(manifest.resolvedProperties.first { $0.id == "flexbox.wrap" })
        #expect(wrap.defaultValue == .string("wrap"))
        #expect(wrap.visibleWhen == .init(id: "layout", value: .string("flex")))

        // …and a control with its own condition combines both: the padding
        // field needs the gate AND its group's enable toggle.
        let padding = try #require(manifest.resolvedProperties.first { $0.id == "spacing.frameworkPadding" })
        #expect(padding.visibleWhen == .init(all: [
            .init(id: "layout", value: .string("flex")),
            .init(id: "spacing.spacingEnabled", value: .boolean(true))
        ]))
    }

    @Test
    func builtInControlGroupResourcesDecodeToRealControls() {
        // The advanced kind carries native identity fields, not a controls
        // resource, so it has no registry definition.
        for kind in PartPackageControlGroup.Kind.allCases where kind != .advanced {
            let definition = BuiltInControlGroupRegistry.definition(for: kind)
            #expect(definition.type == kind)
            #expect(!definition.name.isEmpty)
            #expect(!definition.systemImage.isEmpty)
            #expect(!definition.controls.isEmpty)
            #expect(Set(definition.controls.map(\.id)).count == definition.controls.count)
            // Sectioning is the manifest's job: expanded controls stay in
            // Settings until a section wrapper claims them.
            #expect(definition.controls.allSatisfy { $0.group == "Settings" })
        }
        let advanced = try? JSONDecoder().decode(
            PartPackageControlGroup.self,
            from: Data(#"{"type" : "advanced"}"#.utf8)
        )
        #expect(advanced?.properties.isEmpty == true)
    }

    @Test
    func sharedControlGroupDefaultOverridesReplaceOnlyTheNamedProperty() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.spacing-override-group",
        "title" : "Spacing Override Group",
        "version" : "1.0.0",
        "inspector" : [{
            "type" : "spacing", "id": "spacing",
            "defaults" : {
                "frameworkPadding" : {"left" : "sm"}
            }
        }],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.resolvedProperties.first { $0.id == "spacing.frameworkPadding" }?.defaultValue == .object(["left": .string("sm")]))
        #expect(manifest.resolvedProperties.first { $0.id == "spacing.frameworkMargin" }?.defaultValue == .string("none"))
        #expect(manifest.resolvedProperties.first { $0.id == "spacing.spacingEnabled" }?.defaultValue == .boolean(false))
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func controlGroupsCanOmitControlsAndNarrowTheirOptions() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.narrowed-layout-group",
        "title" : "Narrowed Layout Group",
        "version" : "1.0.0",
        "inspector" : [{
            "type" : "layout", "id": "layout",
            "excludeControls" : ["offsets"],
            "allowedOptions" : {
                "position" : ["relative", "sticky", "absolute"]
            }
        }],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        let identifiers = Set(manifest.resolvedProperties.map(\.id))
        #expect(identifiers.contains("layout.isolation") == false)
        // `offset` and `offsetEdges` exist only to configure `offsets`.
        #expect(!identifiers.contains("layout.offsets"))
        #expect(!identifiers.contains("layout.offset"))
        #expect(!identifiers.contains("layout.offsetEdges"))
        #expect(identifiers.contains("layout.position"))
        #expect(identifiers.contains("layout.overflow"))

        let position = try #require(manifest.resolvedProperties.first { $0.id == "layout.position" })
        #expect(position.control.options?.map(\.value) == ["relative", "sticky", "absolute"])
        // `none` was the default and the narrowing removed it, so the first
        // listed value takes over.
        #expect(position.defaultValue == .string("relative"))
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        // A narrowing that keeps the original default leaves it alone.
        let keepsDefault = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.kept-default-group",
        "title" : "Kept Default Group",
        "version" : "1.0.0",
        "inspector" : [{
            "type" : "layout", "id": "layout",
            "allowedOptions" : {"position" : ["sticky", "none"]}
        }],
        "templates" : {"html" : "part.html"}
        }
        """
        let kept = try JSONDecoder().decode(PartPackageManifest.self, from: Data(keepsDefault.utf8))
        #expect(kept.resolvedProperties.first { $0.id == "layout.position" }?.defaultValue == .string("none"))
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(keepsDefault.utf8)).isEmpty)

        // Omitting a control whose visibility nothing depends on removes just it.
        let omitsOne = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.omit-one-group",
        "title" : "Omit One Group",
        "version" : "1.0.0",
        "inspector" : [{"type" : "flexbox", "id": "flexbox", "excludeControls" : ["alignContent"]}],
        "templates" : {"html" : "part.html"}
        }
        """
        let flexbox = try JSONDecoder().decode(PartPackageManifest.self, from: Data(omitsOne.utf8))
        let flexboxIDs = Set(flexbox.resolvedProperties.map(\.id))
        #expect(!flexboxIDs.contains("flexbox.alignContent"))
        #expect(flexboxIDs.isSuperset(of: ["flexbox.direction", "flexbox.wrap", "flexbox.columnGap", "flexbox.rowGap", "flexbox.alignItems", "flexbox.justifyContent"]))
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(omitsOne.utf8)).isEmpty)
    }

    @Test
    func controlGroupSubsettingIsValidatedAgainstTheGroupsVocabulary() throws {
        func messages(_ entry: String) throws -> [String] {
            let json = """
            {
            "minimumAPIVersion" : 1,
            "id" : "com.example.invalid-subset-group",
            "title" : "Invalid Subset Group",
            "version" : "1.0.0",
            "inspector" : [\(entry)],
            "templates" : {"html" : "part.html"}
            }
            """
            return try PartPackageManifestSchema.diagnostics(for: Data(json.utf8)).map(\.message)
        }

        #expect(try messages(#"{"type" : "layout", "id": "layout", "excludeControls" : ["positon"]}"#)
            .contains("The layout group generates no control called 'positon'."))
        #expect(try messages(#"{"type" : "layout", "id": "layout", "excludeControls" : ["position", "position"]}"#)
            .contains("Duplicate excludeControls value 'position'."))
        #expect(try messages(#"{"type" : "layout", "id": "layout", "excludeControls" : []}"#)
            .contains("excludeControls must name at least one control, or be removed."))
        #expect(try messages(#"{"type" : "effects", "id": "effects", "excludeControls" : ["effectsEnabled", "frameworkShadow"]}"#)
            .contains("excludeControls removes every control the effects group generates; remove the group instead."))
        #expect(try messages(#"{"type" : "layout", "id": "layout", "allowedOptions" : {"position" : ["relative", "statik"]}}"#)
            .contains { $0.hasPrefix("'statik' is not an option of 'position'.") })
        #expect(try messages(#"{"type" : "layout", "id": "layout", "allowedOptions" : {"zIndex" : ["1"]}}"#)
            .contains("'zIndex' has no options to narrow; allowedOptions applies to selects only."))
        #expect(try messages(#"{"type" : "layout", "id": "layout", "allowedOptions" : {"position" : []}}"#)
            .contains("allowedOptions must list at least one value."))
        #expect(try messages(#"""
            {"type" : "layout", "id": "layout", "excludeControls" : ["position"], "allowedOptions" : {"position" : ["relative"]}}
            """#).contains("'position' is omitted; narrowing its options has no effect."))
        #expect(try messages(#"""
            {
                "type" : "layout", "id": "layout",
                "allowedOptions" : {"position" : ["relative", "sticky"]},
                "defaults" : {"position" : "absolute"}
            }
            """#).contains("The default 'absolute' is not one of the narrowed options for 'position'."))
        // Background's own filters compose with the generic ones.
        #expect(try messages(#"{"type" : "background", "id": "background", "backgroundTypes" : ["colour"], "excludeControls" : ["backgroundImage"]}"#)
            .contains("The background group generates no control called 'backgroundImage'."))
        #expect(try messages(#"{"type" : "advanced", "excludeControls" : ["position"]}"#)
            .contains("The advanced group has no options; remove excludeControls."))
    }

    @Test
    func unknownControlGroupTypeIsRejected() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.unknown-group",
        "title" : "Unknown Group",
        "version" : "1.0.0",
        "inspector" : [{"id" : "gradientField", "type" : "gradient"}],
        "templates" : {"html" : "part.html"}
        }
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(json.utf8))
        // "gradient" isn't a recognised Grouped-control kind, so it falls
        // through to standard property validation, which rejects it as an
        // unrecognised control type instead.
        #expect(diagnostics.contains { $0.message.contains("Unknown control type 'gradient'") })
    }

    @Test
    func duplicateControlGroupIDIsRejected() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.duplicate-group",
        "title" : "Duplicate Group",
        "version" : "1.0.0",
        "inspector" : [
            {"type" : "spacing", "id": "spacing"},
            {"type" : "spacing", "id": "spacing"}
        ],
        "templates" : {"html" : "part.html"}
        }
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(json.utf8))
        #expect(diagnostics.contains { $0.message.contains("declared more than once") })
    }

    @Test
    func controlGroupsRequireExplicitIDsExceptAdvanced() throws {
        for kind in PartPackageControlGroup.Kind.allCases where kind != .advanced {
            let json = manifest(withInspectorEntries: "{\"type\":\"\(kind.rawValue)\"}")
            let data = Data(json.utf8)
            #expect(try !PartPackageManifestSchema.diagnostics(for: data).isEmpty)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PartPackageManifest.self, from: data)
            }
        }
        let advanced = Data(manifest(withInspectorEntries: #"{"type":"advanced"}"#).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: advanced).isEmpty)
        _ = try JSONDecoder().decode(PartPackageManifest.self, from: advanced)
    }

    @Test
    func groupedControlReferencesExpandInlineAtTheAuthorsDeclaredPosition() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.inline-ordering",
        "title" : "Inline Ordering",
        "version" : "1.0.0",
        "inspector" : [
            {
                "id" : "before",
                "label" : "Before",
                "type" : "toggle",
                "defaults" : {"base" : true}
            },
            {"type" : "borders", "id": "borders"},
            {
                "id" : "after",
                "label" : "After",
                "type" : "toggle",
                "defaults" : {"base" : false}
            }
        ],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)

        #expect(manifest.resolvedProperties.map(\.id) == [
            "before", "borders.borderEnabled", "borders.frameworkBorder", "borders.frameworkBorderColour", "borders.frameworkRadius", "after"
        ])
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func theOldSeparateControlGroupsKeyIsNoLongerRecognised() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.legacy-control-groups-key",
        "title" : "Legacy Control Groups Key",
        "version" : "1.0.0",
        "controlGroups" : [{"type" : "background", "id": "background"}],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: data)

        #expect(diagnostics.contains { $0.message.contains("Unknown key 'controlGroups'") })
        // Grouped controls declared this way are also silently absent from
        // decode, since the separate key is no longer read at all.
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups.isEmpty)
    }

    @Test @MainActor
    func backgroundVideoUsesGeneratedPosterInCanvasAndExport() throws {
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: #"{"type":"background","id":"surface","backgroundTypes":["video"]}"#),
            template: #"<section class="{{ part.class }}" {{ part.attributes }}>{{ control.surface.video }}{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(package.renderDefinition.properties.first { $0.control.type == .video })
        #expect(property.usesAutomaticVideoPoster)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let data = Data("generated background still".utf8)
        var asset = ProjectAsset(filename: "background.mp4", mediaType: "video/mp4", byteCount: 0, contentDigest: "background-test",
                                 videoMetadata: .init(duration: 4, posterJPEG: data))
        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        node.setProperty(.init(rawValue: "surface.backgroundMode"), value: .string("static"))
        node.setProperty(.init(rawValue: "surface.backgroundStyle"), value: .string("video"))
        node.setProperty(.init(rawValue: property.id), value: .url(asset.reference))
        node.setProperty(PartVideoTemplateValues.posterPropertyKey(for: property.id), value: .url("https://example.com/legacy-poster.jpg"))
        var site = Site.starter()
        site.pages = [Page(title: "Home", slug: "index", parts: [node]),
                      Page(title: "Nested", slug: "nested", parts: [node])]
        site.assetLibrary = [.asset(asset)]
        let assets: ProjectAssetContents = [asset.id: .init(asset: asset, data: Data())]
        let canvas = HTMLPageRenderer(site: site).render(page: site.pages[0], language: "en", framework: site.framework, assets: assets, breakpoint: .extraLarge)
        let metadata = try #require(asset.videoMetadata)
        #expect(canvas.contains(metadata.posterDataURL))
        #expect(canvas.contains("legacy-poster.jpg") == false)
        let export = StaticSiteRenderer().render(site: site, assets: assets)
        #expect(export.errors.isEmpty)
        let path = try #require(PartVideoTemplateValues.generatedPosterPath(for: asset))
        #expect(export.files.filter { $0.path == path }.count == 1)
        #expect(export.file(at: path)?.data == data)
        #expect(export.file(at: "index.html")?.contents.contains("poster=\"\(path)\"") == true)
        #expect(export.file(at: "nested/index.html")?.contents.contains("poster=\"../\(path)\"") == true)
        #expect(export.file(at: "index.html")?.contents.contains("legacy-poster.jpg") == false)
        asset.videoMetadata = nil
        let missing = StaticSiteRenderer().render(site: site, assets: [asset.id: .init(asset: asset, data: Data())])
        #expect(missing.file(at: path) == nil)
        #expect(missing.file(at: "index.html")?.contents.contains(" poster=") == false)
    }

    @Test @MainActor
    func videoControlProvidesStructuredTemplateValues() throws {
        let control = """
        {
            "id" : "film",
            "label" : "Film",
            "type" : "video",
            "defaults" : {"base" : ""}
        }
        """
        let data = Data(manifest(withInspectorEntries: control).utf8)
        let decodedManifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        let property = try #require(decodedManifest.resolvedProperties.first)
        #expect(property.control.type == .video)
        #expect(!property.responsive)
        let responsiveControl = control.replacingOccurrences(
            of: "\"defaults\" : {\"base\" : \"\"}",
            with: "\"defaults\" : {\"base\" : \"\"}, \"responsive\" : true"
        )
        let responsiveDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: responsiveControl).utf8)
        )
        #expect(responsiveDiagnostics.contains { $0.message == "A video control does not support responsive." })
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: control),
            template: #"<section class="sample {{ part.class }}" {{ part.attributes }}><video class="fd-video" src="{{ control.film }}" poster="{{ control.film.poster }}" {{ control.film.attributes }}></video>{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        guard case .video = PartPackageAdapter.definition(from: package).properties.first?.control else {
            Issue.record("Expected a video property control")
            return
        }
        let definitions = PartPackageAdapter.definition(from: package).properties
        #expect(definitions.count == 8)
        #expect(definitions.first?.isResponsive == false)
        let posterDefinition = try #require(definitions.first {
            $0.key == PartVideoTemplateValues.posterPropertyKey(for: "film")
        })
        #expect(posterDefinition.key == PartVideoTemplateValues.posterPropertyKey(for: "film"))
        guard case .derived = posterDefinition.control else {
            Issue.record("Expected the poster companion to be a derived property")
            return
        }
        #expect(!posterDefinition.isResponsive)
        #expect(!posterDefinition.isInspectorVisible)
        #expect(definitions.dropFirst().allSatisfy { !$0.isResponsive && !$0.isInspectorVisible })

        var values: [String: PartPackageValue] = ["film": .string("assets/demo.mp4")]
        let posterData = Data("frame".utf8)
        let asset = ProjectAsset(
            filename: "Demo Film.mp4",
            mediaType: "video/mp4",
            byteCount: 42_000,
            contentDigest: "test-digest-film",
            pixelWidth: 1920,
            pixelHeight: 1080,
            videoMetadata: .init(duration: 12.5, posterJPEG: posterData)
        )
        let decodedAsset = try JSONDecoder().decode(
            ProjectAsset.self,
            from: JSONEncoder().encode(asset)
        )
        #expect(decodedAsset == asset)
        PartVideoTemplateValues.insert(
            propertyID: "film",
            href: "assets/demo.mp4",
            poster: "data:image/jpeg;base64,frame",
            asset: asset,
            into: &values
        )
        let rendered = PartTemplateRenderer.render(
            #"{{ control.film.source }}|{{ control.film.attributes }}|{{ control.film.href }}|{{ control.film.poster }}|{{ control.film.autoplay }}|{{ control.film.muted }}|{{ control.film.controls }}|{{ control.film.loop }}|{{ control.film.startAt }}|{{ control.film.filename }}|{{ control.film.extension }}|{{ control.film.mimeType }}|{{ control.film.byteCount }}|{{ control.film.width }}|{{ control.film.height }}|{{ control.film.duration }}"#,
            context: .init(instanceID: UUID(), packageIdentifier: decodedManifest.identifier, properties: values, slots: [:])
        )
        #expect(rendered == #"assets/demo.mp4|controls playsinline|assets/demo.mp4|data:image/jpeg;base64,frame|never|false|true|false|0|Demo Film.mp4|mp4|video/mp4|42000|1920|1080|12.5"#)

        PartVideoTemplateValues.insert(
            propertyID: "film",
            href: "assets/demo.mp4",
            poster: "poster.jpg",
            asset: asset,
            playback: .init(autoplay: "onLoad", muted: true, showsControls: false, loops: true, startAt: 4.5),
            into: &values
        )
        let configured = PartTemplateRenderer.render(
            "{{ control.film.source }}|{{ control.film.attributes }}",
            context: .init(instanceID: UUID(), packageIdentifier: decodedManifest.identifier, properties: values, slots: [:])
        )
        // Start At rides on the source as a media fragment.
        #expect(configured == #"assets/demo.mp4#t=4.5|autoplay muted loop playsinline"#)

        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        node.setProperty(.init(rawValue: "film"), value: .url(asset.reference))
        let page = Page(title: "Video", slug: "index", parts: [node])
        let assets: ProjectAssetContents = [asset.id: ProjectAssetContent(asset: asset, data: Data())]
        let canvasHTML = HTMLPageRenderer().render(
            page: page,
            language: "en",
            framework: .standard,
            assets: assets,
            breakpoint: .extraLarge
        )
        // The canvas keeps the poster and the drop target but never a source,
        // so the editor never streams the movie.
        #expect(canvasHTML.contains(#"poster="data:image/jpeg;base64,ZnJhbWU=""#))
        #expect(canvasHTML.contains(#"data-foundry-video-property="film""#))
        #expect(!canvasHTML.contains(#"<video class="fd-video" src="#))
        #expect(!canvasHTML.contains(asset.id.uuidString))

        var site = Site.starter()
        site.pages = [page]
        site.assetLibrary = [.asset(asset)]
        let exported = StaticSiteRenderer().render(site: site, assets: assets)
        let posterPath = "assets/foundry-video-posters/\(asset.id.uuidString.lowercased()).jpg"
        #expect(exported.file(at: posterPath) == nil)
        #expect(exported.file(at: "index.html")?.contents.contains(#"<video class="fd-video" src="assets/"#) == true)
        #expect(exported.file(at: "index.html")?.contents.contains("data-foundry-video-drop-zone") == false)
        #expect(exported.file(at: "index.html")?.contents.contains("data:image/jpeg") == false)

        let posterAsset = ProjectAsset(
            filename: "Cover.jpg",
            mediaType: "image/jpeg",
            byteCount: 10,
            contentDigest: "test-digest-cover",
            pixelWidth: 8,
            pixelHeight: 8
        )
        var posterNode = node
        posterNode.setProperty(
            PartVideoTemplateValues.posterPropertyKey(for: "film"),
            value: .url(posterAsset.reference)
        )
        var posterSite = Site.starter()
        posterSite.pages = [Page(title: "Video", slug: "index", parts: [posterNode])]
        posterSite.assetLibrary = [.asset(asset), .asset(posterAsset)]
        let posterExported = StaticSiteRenderer().render(
            site: posterSite,
            assets: [
                asset.id: ProjectAssetContent(asset: asset, data: Data()),
                posterAsset.id: ProjectAssetContent(asset: posterAsset, data: Data())
            ]
        )
        #expect(posterExported.file(at: "index.html")?.contents.contains(#"poster="assets/"#) == true)
    }

    @Test
    func controlGroupsUseCurrentPartAPI() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.background-group",
        "title" : "Background Group",
        "version" : "1.0.0",
        "inspector" : [{"type" : "background", "id": "background"}],
        "templates" : {"html" : "part.html"}
        }
        """

        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(json.utf8))
        #expect(diagnostics.isEmpty)
    }

    @Test
    func controlArraysDecodePersistAndRenderIndexedValues() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.arrays",
        "title" : "Arrays", "description" : "Array controls",
        "author" : "Foundry", "version" : "1.0.0", "group" : "Other",
        "tags" : [], "assets" : [],
        "inspector" : [{
        "id" : "palette", "label" : "Palette",
        "subtitle" : ["First", "Second", "Third", "Fourth"],
        "tooltip" : "Four colours",
        "type" : "color", "count" : 4,
        "defaults" : {"base" : ["#111111", "#222222", "#333333", "#444444"]},
        "responsive" : true        }],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
        let property = try #require(manifest.resolvedProperties.first)
        #expect(property.control.count == 4)
        #expect(property.label == "Palette")
        #expect(property.subtitles == ["First", "Second", "Third", "Fourth"])
        #expect(property.tooltip == "Four colours")

        let value = PartPackageValue.array([.string("red"), .string("green"), .string("blue")])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(PartPackageValue.self, from: data) == value)

        let context = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.arrays",
            properties: ["palette": value], slots: [:]
        )
        #expect(PartTemplateRenderer.render("{{ control.palette[1] }}", context: context) == "green")
        #expect(PartTemplateRenderer.render("{{ property.palette[1] }}", context: context).isEmpty)
    }

    @Test
    func selectRejectsFrameworkValuesAndFrameworkDefaults() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.framework-values",
        "title" : "Framework Values", "description" : "Named framework sources",
        "author" : "Foundry", "version" : "1.0.0", "group" : "Other",
        "tags" : [], "assets" : [],
        "inspector" : [{
        "id" : "tone", "label" : "Tone",
        "type" : "select", "frameworkValues" : "spacing",
        "allowsCustom" : true,
        "options" : [{"value" : "inherit", "title" : "Inherit"}],
        "defaults" : {"base" : "md"}, "responsive" : false
        }],
        "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
        let property = try #require(manifest.resolvedProperties.first)

        #expect(property.control.frameworkValues == .source(.spacing))
        #expect(property.control.frameworkValueSource == nil)
        #expect(property.control.allowsCustom == true)
        let diagnostics = PartPackageValidator.validate(manifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.location.contains("frameworkValues") })
        #expect(diagnostics.contains { $0.message.contains("select default") })
        #expect(PartPackageFrameworkValueResolver.choices(for: .spacing, framework: .standard).contains { $0.value == "md" })
        #expect(PartPackageFrameworkValueResolver.resolve("md", from: .spacing, framework: .standard) == "var(--foundry-space-md)")
        for source in PartPackageFrameworkValueSource.allCases {
            #expect(PartPackageFrameworkValueResolver.choices(for: source, framework: .standard).allSatisfy {
                !$0.label.contains("—")
            })
        }

        var framework = Framework.standard
        framework.typography.customFontSizes.append(.init(id: "display", title: "Display", size: 5, lineHeight: 1.5))
        let sizeChoices = PartPackageFrameworkValueResolver.choices(for: .fontSizes, framework: framework)
        #expect(sizeChoices.first?.value == "xs")
        #expect(sizeChoices.last?.value == "display")
        #expect(sizeChoices.last?.separatorBefore == true)

        let countedFrameworkSelect = json
            .replacingOccurrences(
                of: "\"frameworkValues\" : \"spacing\"",
                with: "\"frameworkValues\" : \"fontSizes\""
            )
            .replacingOccurrences(
                of: "\"defaults\" : {\"base\" : \"md\"}, \"responsive\" : false",
                with: "\"defaults\" : {\"base\" : \"base\"}, \"responsive\" : false, \"count\" : 2"
            )
        let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(countedFrameworkSelect.utf8)
        )
        #expect(schemaDiagnostics.contains {
            $0.location.hasSuffix(".frameworkValues")
                && $0.message == "Select supports only declared options; remove frameworkValues."
        })

        let countedFrameworkColor = countedFrameworkSelect
            .replacingOccurrences(
                of: "\"type\" : \"select\"",
                with: "\"type\" : \"frameworkColor\""
            )
        let colorSchemaDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(countedFrameworkColor.utf8)
        )
        #expect(colorSchemaDiagnostics.contains {
            $0.location.hasSuffix(".count")
                && $0.message == "A frameworkColor control cannot be a multi control; remove count."
        })

        let booleanFrameworkValues = Data(
            json.replacingOccurrences(
                of: "\"frameworkValues\" : \"spacing\"",
                with: "\"frameworkValues\" : true"
            ).utf8
        )
        #expect(try PartPackageManifestSchema.diagnostics(for: booleanFrameworkValues).contains {
            $0.location.hasSuffix(".frameworkValues") && $0.message == "frameworkValues must be a string."
        })

        do {
            _ = try JSONDecoder().decode(
                PartPackageControl.self,
                from: Data("{\"type\" : \"color\", \"frameworkValues\" : true}".utf8)
            )
            Issue.record("Boolean frameworkValues should be rejected")
        } catch {
            // String-only decoding intentionally rejects the removed API.
        }
    }

    @Test
    func fontFamilyFrameworkSelectRejectsCustomValues() throws {
        let item = """
        {
            "id" : "typeface",
            "label" : "Typeface",
            "type" : "select",
            "frameworkValues" : "fontFamilies",
            "allowsCustom" : true,
            "defaults" : {"base" : "body"},
            "responsive" : true
        }
        """
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: item).utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(diagnostics.contains {
            $0.location.hasSuffix("allowsCustom")
                && $0.message.contains("requires a framework-aware control")
        })
    }

    @Test
    func shadowIsAStandaloneFrameworkAwareControl() throws {
        let item = """
        {
            "id" : "cardShadow",
            "label" : "Shadow",
            "type" : "frameworkShadow",
            "allowsCustom" : true,
            "defaults" : {"base" : "md"},
            "responsive" : false
        }
        """
        let decodedManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: item).utf8)
        )
        let property = try #require(decodedManifest.resolvedProperties.first)
        #expect(property.control.type == .frameworkShadow)
        #expect(property.control.frameworkValues == nil)
        #expect(property.control.frameworkValueSource == .shadows)
        #expect(property.control.allowsCustom == true)
        let diagnostics = PartPackageValidator.validate(
            decodedManifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(!diagnostics.contains {
            $0.location.contains("cardShadow") || $0.location.contains("inspector")
        })

        let legacyItem = item
            .replacingOccurrences(
                of: "\"type\" : \"frameworkShadow\"",
                with: "\"type\" : \"select\", \"frameworkValues\" : \"shadows\""
            )
        let legacyDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: legacyItem).utf8)
        )
        #expect(legacyDiagnostics.contains {
            $0.location.hasSuffix(".frameworkValues")
                && $0.message == "Select supports only declared options; remove frameworkValues."
        })

        // The pre-rename spelling is gone for good: bare `shadow` is an unknown type.
        let renamedItem = item.replacingOccurrences(
            of: "\"type\" : \"frameworkShadow\"",
            with: "\"type\" : \"shadow\""
        )
        let renamedDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: renamedItem).utf8)
        )
        #expect(renamedDiagnostics.contains { $0.message == "Unknown control type 'shadow'." })
    }

    @Test
    func malformedControlFieldsProduceActionableSchemaDiagnostics() throws {
        let validItem = """
        {
            "id" : "example",
            "label" : "Example",
            "type" : "text",
            "defaults" : {"base" : "Hello"},
            "responsive" : false
        }
        """
        let cases: [(replacement: String, locationSuffix: String, message: String)] = [
            (
                validItem
                    .replacingOccurrences(of: "\"text\"", with: "\"frameworkColor\"")
                    .replacingOccurrences(of: "\"label\"", with: "\"colorMath\" : true, \"label\""),
                ":colorMath", "Unknown key 'colorMath'. Check the spelling or remove it."
            ),
            (
                validItem.replacingOccurrences(of: "\"type\" : \"text\"", with: "\"type\" : 1"),
                ":type", "type must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "\"text\"", with: "\"fontFamily\""),
                ":type", "Unknown control type 'fontFamily'."
            ),
            (
                validItem.replacingOccurrences(of: "\"label\" : \"Example\"", with: "\"label\" : [\"Example\"]"),
                ":label", "label must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "\"label\"", with: "\"labels\""),
                ":labels", "Unknown key 'labels'. Check the spelling or remove it."
            ),
            (
                validItem.replacingOccurrences(of: "\"responsive\" : false", with: "\"responsive\" : \"false\""),
                ":responsive", "responsive must be a Boolean."
            ),
            (
                validItem.replacingOccurrences(of: "\"defaults\" : {\"base\" : \"Hello\"}", with: "\"defaults\" : {\"base\" : {}}"),
                ":defaults.base", "defaults.base must be a string, number, Boolean, or array of those values."
            ),
            (
                validItem.replacingOccurrences(of: "\"responsive\" : false", with: "\"responsive\" : false, \"minimum\" : \"zero\""),
                ":minimum", "minimum must be a number."
            ),
            (
                validItem.replacingOccurrences(of: "\"responsive\" : false", with: "\"responsive\" : false, \"count\" : \"two\""),
                ":count", "count must be an integer."
            )
        ]

        for testCase in cases {
            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: testCase.replacement).utf8)
            )
            #expect(diagnostics.contains {
                $0.location.hasSuffix(testCase.locationSuffix) && $0.message == testCase.message
            })
        }

        let malformedOptions = validItem.replacingOccurrences(
            of: "\"responsive\" : false",
            with: "\"responsive\" : false, \"options\" : [\"bad\"]"
        )
        #expect(try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: malformedOptions).utf8)
        ).contains {
            $0.location.hasSuffix(":options[0]") && $0.message == "Each options entry must be a dictionary."
        })

        let withoutResponsive = validItem.replacingOccurrences(
            of: ",\n    \"responsive\" : false",
            with: ""
        )
        let withoutResponsiveData = Data(manifest(withInspectorEntries: withoutResponsive).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: withoutResponsiveData).isEmpty)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: withoutResponsiveData)
        #expect(decoded.resolvedProperties.first?.responsive == false)
    }

    @Test
    func visibilityConditionsDecodeAndEvaluateScalarAndIndexedValues() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.visibleWhen",
        "title" : "Visibility", "description" : "Conditional controls",
        "version" : "1.0.0", "group" : "Other",
        "assets" : [],
        "inspector" : [
        {"id" : "mode", "label" : "Mode", "type" : "select", "options" : [{"value" : "featured", "title" : "Featured"}], "defaults" : {"base" : "featured"}, "responsive" : false},
        {"id" : "titles", "label" : "Titles", "type" : "text", "count" : 3, "defaults" : {"base" : ["One", "Two", "Featured story"]}, "responsive" : false},
        {"id" : "detail", "label" : "Detail", "type" : "text", "defaults" : {"base" : "Visible"}, "responsive" : false, "visibleWhen" : {"id" : "titles[2]", "operation" : "containsInsensitive", "value" : "featured"}, "valueAvailability" : "whenVisible"},
        {"id" : "compoundDetail", "label" : "Compound detail", "type" : "text", "defaults" : {"base" : "Visible"}, "responsive" : false, "visibleWhen" : {"all" : [{"id" : "mode", "value" : "featured"}, {"any" : [{"id" : "titles[0]", "value" : "One"}, {"id" : "titles[1]", "value" : "Other"}]}]}}
        ], "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
        let enabledProperty = try #require(manifest.resolvedProperties.first { $0.id == "detail" })
        #expect(enabledProperty.visibleWhen?.id == "titles[2]")
        #expect(enabledProperty.visibleWhen?.operation == "containsInsensitive")
        #expect(enabledProperty.valueAvailability == .whenVisible)
        #expect(manifest.resolvedProperties.first { $0.id == "compoundDetail" }?.valueAvailability == .always)

        #expect(PartPackageVisibilityEvaluator.evaluate(
            .string("Featured story"),
            operation: enabledProperty.visibleWhen?.operation ?? "",
            expected: enabledProperty.visibleWhen?.value
        ))
        #expect(!PartPackageVisibilityEvaluator.evaluate(
            .string("Ordinary story"),
            operation: enabledProperty.visibleWhen?.operation ?? "",
            expected: enabledProperty.visibleWhen?.value
        ))
        #expect(PartPackageVisibilityEvaluator.evaluate(.string(""), operation: "isEmpty", expected: nil))
        #expect(PartPackageVisibilityEvaluator.evaluate(.number(10), operation: ">=", expected: .number(10)))
        let compound = try #require(manifest.resolvedProperties.first { $0.id == "compoundDetail" }?.visibleWhen)
        #expect(compound.all?.count == 2)
        #expect(compound.all?.last?.any?.count == 2)
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(json.utf8)).isEmpty)
    }

    @Test @MainActor
    func templateValuesCanBeAvailableOnlyWhileTheirControlsAreVisible() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.value-availability",
        "title" : "Value availability",
        "version" : "1.0.0",
        "inspector" : [
        {"id" : "mode", "label" : "Mode", "type" : "select", "options" : [{"value" : "preset", "title" : "Preset"}, {"value" : "custom", "title" : "Custom"}], "defaults" : {"base" : "preset"}, "responsive" : false},
        {"id" : "presetSize", "label" : "Preset size", "type" : "text", "defaults" : {"base" : "1rem"}, "responsive" : false, "visibleWhen" : {"id" : "mode", "value" : "preset"}, "valueAvailability" : "whenVisible"},
        {"id" : "customSize", "label" : "Custom size", "type" : "text", "defaults" : {"base" : "24px"}, "responsive" : false, "visibleWhen" : {"id" : "mode", "value" : "custom"}, "valueAvailability" : "whenVisible"}
        ],
        "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        let package = LoadedPartPackage(
            manifest: manifest,
            rootURL: FileManager.default.temporaryDirectory,
            htmlTemplate: #"<p {{ part.attributes }} style="font-size: {{ control.presetSize }}{{ control.customSize }}">Size</p>"#,
            css: "", pageCSS: "", siteCSS: "", placedHTML: [], instanceJavaScript: "",
            pageJavaScript: "", instancePHP: "", pagePHP: "", editorCSS: "",
            updateSourceURL: nil, imageMetadata: [:]
        )
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: manifest.identifier) }

        var node = PartNode.make(.init(rawValue: manifest.identifier))
        let presetPage = Page(title: "Preset", slug: "preset", parts: [node])
        let presetCanvas = HTMLPageRenderer().render(page: presetPage, framework: .standard)
        #expect(presetCanvas.contains(#"style="font-size: 1rem""#))
        #expect(!presetCanvas.contains("1rem24px"))

        node.setProperty(.init(rawValue: "mode"), value: .choice("custom"))
        let filtered = PartPackageVisibilityEvaluator.availableTemplateValues(
            [
                "presetSize": .string("1rem"),
                "presetSize.lineHeight": .string("1.5"),
                "presetSize2": .string("unrelated"),
                "customSize": .string("24px")
            ],
            properties: manifest.resolvedProperties,
            for: node
        )
        #expect(filtered["presetSize"] == nil)
        #expect(filtered["presetSize.lineHeight"] == nil)
        #expect(filtered["presetSize2"] == .string("unrelated"))
        #expect(filtered["customSize"] == .string("24px"))
        let customPage = Page(title: "Custom", slug: "custom", parts: [node])
        let customCanvas = HTMLPageRenderer().render(page: customPage, framework: .standard)
        #expect(customCanvas.contains(#"style="font-size: 24px""#))
        #expect(node.propertyValue(.init(rawValue: "presetSize")) == .string("1rem"))

        var site = Site.starter()
        site.pages = [customPage]
        let exported = StaticSiteRenderer().render(site: site)
        #expect(exported.files.contains { $0.contents.contains(#"style="font-size: 24px""#) })
    }

    @Test
    func whenVisibleValueAvailabilityRequiresAVisibilityCondition() throws {
        let control = """
        {"id" : "detail", "label" : "Detail", "type" : "text", "defaults" : {"base" : "Value"}, "responsive" : false, "valueAvailability" : "whenVisible"}
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: control).utf8)
        )
        #expect(diagnostics.contains {
            $0.location.hasSuffix(".valueAvailability") &&
                $0.message == "valueAvailability 'whenVisible' requires visibleWhen."
        })
    }

    @Test
    func virtualControlsAndButtonOutputsResolveFromManifestValues() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.derived",
        "title" : "Derived", "description" : "Derived controls",
        "version" : "1.0.0",
        "group" : "Other", "assets" : [],
        "inspector" : [
        {"id" : "amount", "label" : "Amount", "type" : "number", "defaults" : {"base" : 21}, "responsive" : false},
        {"id" : "action", "label" : "Action", "type" : "button", "trueValue" : "active", "falseValue" : "ready", "defaults" : {"base" : false}, "responsive" : false},
        {"id" : "doubled", "type" : "math", "argument1" : "amount", "argument2" : 2, "operation" : "*", "round" : false}
        ], "templates" : {"html" : "part.html"}
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(json.utf8))
        let resolved = PartPackageDerivedValueResolver.resolve(
            ["amount": .number(21), "action": .boolean(true)],
            properties: manifest.resolvedProperties
        )
        #expect(resolved["doubled"] == .number(42))
        #expect(resolved["action"] == .string("active"))
    }

    @Test
    func buttonContractSupportsOptionalLabelsSubtitlesAndValidatedMappings() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.buttons",
        "title" : "Buttons", "description" : "Button contract",
        "version" : "1.0.0",
        "group" : "Other", "assets" : [],
        "inspector" : [
        {"id" : "plain", "subtitle" : "Optional help", "type" : "button", "defaults" : {"base" : false}},
        {"id" : "mapped", "type" : "button", "buttonText" : "Apply", "buttonIcon" : "bolt.fill", "trueValue" : "active", "falseValue" : "idle", "defaults" : {"base" : true}},
        {"id" : "multiple", "type" : "button", "count" : 2, "subtitle" : ["First", "Second"], "buttonText" : ["Previous", "Next"], "buttonIcon" : ["arrow.left", "arrow.right"], "activeButtonText" : ["Selected previous", "Selected next"], "activeButtonIcon" : ["checkmark", "checkmark"], "trueValue" : ["one", "two"], "falseValue" : "off", "defaults" : {"base" : [true, false]}},
        {"id" : "singleChoice", "type" : "button", "count" : 2, "selectionMode" : "single", "trueValue" : ["first", "second"], "defaults" : {"base" : [false, true]}},
        {"id" : "wrongDefault", "type" : "button", "defaults" : {"base" : "no"}},
        {"id" : "wrongMapping", "type" : "button", "count" : 2, "selectionMode" : "single", "trueValue" : ["only-one"], "defaults" : {"base" : [true, true]}}
        ], "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.resolvedProperties[0].label.isEmpty)
        #expect(manifest.resolvedProperties[0].subtitles == ["Optional help"])
        #expect(manifest.resolvedProperties[1].buttonTexts == ["Apply"])
        #expect(manifest.resolvedProperties[1].buttonIcons == ["bolt.fill"])
        #expect(manifest.resolvedProperties[2].subtitles == ["First", "Second"])
        #expect(manifest.resolvedProperties[2].buttonTexts == ["Previous", "Next"])
        #expect(manifest.resolvedProperties[2].buttonIcons == ["arrow.left", "arrow.right"])
        #expect(manifest.resolvedProperties[2].activeButtonTexts == ["Selected previous", "Selected next"])
        #expect(manifest.resolvedProperties[2].activeButtonIcons == ["checkmark", "checkmark"])
        #expect(manifest.resolvedProperties[2].control.selectionMode == nil)
        #expect(manifest.resolvedProperties[3].control.selectionMode == .single)
        #expect(manifest.resolvedProperties[5].control.selectionMode == .single)

        let resolved = PartPackageDerivedValueResolver.resolve(
            [
                "plain": .boolean(false),
                "mapped": .boolean(true),
                "multiple": .array([.boolean(true), .boolean(false)]),
                "singleChoice": .array([.boolean(false), .boolean(true)])
            ],
            properties: manifest.resolvedProperties
        )
        #expect(resolved["plain"] == .boolean(false))
        #expect(resolved["mapped"] == .string("active"))
        #expect(resolved["multiple"] == .array([.string("one"), .string("off")]))
        #expect(resolved["singleChoice"] == .string("second"))

        let diagnostics = PartPackageValidator.validate(manifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.message == "A button control requires a Boolean default value." })
        #expect(diagnostics.contains { $0.message == "A button control array requires exactly 2 trueValue values." })
        #expect(diagnostics.contains { $0.message == "A button control using single selectionMode requires exactly one true default value." })
    }

    @Test
    func colorOutputFormatsRespectOpacityAndArrays() throws {
        let formats = [
            "hex", "hexValue", "rgb", "rgba", "rgbValues", "rgbaValues",
            "hsl", "hsla", "hslValues", "hslaValues"
        ]
        let declarations = formats.map { format in
            """
            {"id" : "\(format)", "type" : "color", "opacity" : true, "outputFormat" : "\(format)", "defaults" : {"base" : "#FF336680"}}
            """
        }.joined(separator: ",\n")
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.color-formats",
        "title" : "Colour formats", "description" : "Colour output contract",
        "version" : "1.0.0",
        "group" : "Other", "assets" : [],
        "inspector" : [
        \(declarations),
        {"id" : "defaultHex", "type" : "color", "defaults" : {"base" : "#FF3366"}},
        {"id" : "opaqueRGBA", "type" : "color", "outputFormat" : "rgba", "defaults" : {"base" : "#FF3366"}},
        {"id" : "array", "type" : "color", "count" : 2, "outputFormat" : "rgbValues", "defaults" : {"base" : ["#FF3366", "#3366CC"]}}
        ], "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        let values = Dictionary(uniqueKeysWithValues: manifest.resolvedProperties.map {
            ($0.id, $0.defaultValue)
        })
        let resolved = PartPackageDerivedValueResolver.resolve(values, properties: manifest.resolvedProperties)

        #expect(resolved["hex"] == .string("#FF336680"))
        #expect(resolved["hexValue"] == .string("FF336680"))
        #expect(resolved["rgb"] == .string("rgb(255 51 102 / 0.502)"))
        #expect(resolved["rgba"] == .string("rgba(255, 51, 102, 0.502)"))
        #expect(resolved["rgbValues"] == .string("255, 51, 102"))
        #expect(resolved["rgbaValues"] == .string("255, 51, 102, 0.502"))
        #expect(resolved["hsl"] == .string("hsl(345 100% 60% / 0.502)"))
        #expect(resolved["hsla"] == .string("hsla(345, 100%, 60%, 0.502)"))
        #expect(resolved["hslValues"] == .string("345, 100%, 60%"))
        #expect(resolved["hslaValues"] == .string("345, 100%, 60%, 0.502"))
        #expect(resolved["defaultHex"] == .string("#FF3366"))
        #expect(resolved["opaqueRGBA"] == .string("rgba(255, 51, 102, 1)"))
        #expect(resolved["array"] == .array([
            .string("255, 51, 102"),
            .string("51, 102, 204")
        ]))
        #expect(resolved["hex.red"] == .number(255))
        #expect(resolved["hex.green"] == .number(51))
        #expect(resolved["hex.blue"] == .number(102))
        #expect(resolved["hex.alpha"] == .number(128.0 / 255.0))
        #expect(resolved["hex.hue"] == .number(345))
        #expect(resolved["hex.saturation"] == .number(100))
        #expect(resolved["hex.lightness"] == .number(60))
        // White clears the 3:1 bar against #FF3366 (3.55:1), so it wins even
        // though black's raw ratio is higher — matching designer expectation.
        #expect(resolved["hex.contrastColor"] == .string("#FFFFFF"))
        #expect(resolved["hex.relativeLuminance"] == .number(0.24586962186768263))
        #expect(resolved["hex.contrastRatioWithBlack"] == .number(5.917392437353652))
        #expect(resolved["hex.contrastRatioWithWhite"] == .number(3.5488604520188827))
        #expect(resolved["array[1].red"] == .number(51))
        #expect(resolved["array[1].blue"] == .number(204))

        let channelExpression = try PartTemplateExpression.parse("control.array[1].blue")
        #expect(try PartTemplateExpression.evaluate(
            channelExpression,
            properties: resolved,
            environment: .published
        ) == .number(204))

        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: manifest.identifier,
            properties: resolved.merging([
                "filterAmount": .number(25),
                "filterAlpha": .number(0.5),
                "mixTarget": .string("#3366CC")
            ]) { current, _ in current },
            slots: [:]
        )
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | lighten(50) }}", context: context) == "#FF99B3")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | darken(50) }}", context: context) == "#801A33")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | withAlpha(0.5) }}", context: context) == "#FF336680")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | mix('#3366CC', 25) }}", context: context) == "#CC4080")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | lighten(control.filterAmount) }}", context: context) == "#FF668C")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | withAlpha(control.filterAlpha) }}", context: context) == "#FF336680")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | mix(control.mixTarget, control.filterAmount) }}", context: context) == "#CC4080")
        #expect(PartTemplateRenderer.render("{{ control.defaultHex | mix(control.rgba, control.filterAmount) }}", context: context) == "#FF3366")
        #expect(PartTemplateRenderer.render("{{ control.rgba | darken(25) }}", context: context) == "rgba(191, 38, 77, 0.502)")
    }

    @Test
    func dateControlsUseDateOnlyValuesPartsAndFormatting() throws {
        let json = """
        {
        "minimumAPIVersion" : 1,
        "id" : "com.example.dates",
        "title" : "Dates", "description" : "Date contract",
        "version" : "1.0.0",
        "group" : "Other", "assets" : [],
        "inspector" : [
        {"id" : "published", "type" : "date", "minimum" : "2026-01-01", "maximum" : "2026-12-31", "defaults" : {"base" : "2026-09-08"}},
        {"id" : "schedule", "type" : "date", "count" : 2, "defaults" : {"base" : ["2026-10-01", "2026-10-20"]}}
        ], "templates" : {"html" : "part.html"}
        }
        """
        let data = Data(json.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.resolvedProperties.first?.control.minimumDate == "2026-01-01")
        #expect(manifest.resolvedProperties.first?.control.maximumDate == "2026-12-31")
        let values = Dictionary(uniqueKeysWithValues: manifest.resolvedProperties.map { ($0.id, $0.defaultValue) })
        let resolved = PartPackageDerivedValueResolver.resolve(values, properties: manifest.resolvedProperties)

        #expect(resolved["published"] == .string("2026-09-08"))
        #expect(resolved["published.year"] == .number(2026))
        #expect(resolved["published.month"] == .number(9))
        #expect(resolved["published.day"] == .number(8))
        #expect(resolved["published.monthName"] == .string("September"))
        #expect(resolved["published.weekday"] == .string("Tuesday"))
        #expect(resolved["schedule[1].day"] == .number(20))

        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: manifest.identifier,
            properties: resolved.merging([
                "offsetDays": .number(7),
                "datePattern": .string("d MMMM yyyy")
            ]) { current, _ in current },
            slots: [:]
        )
        #expect(PartTemplateRenderer.render(
            "{{ control.published | formatDate(\"d MMMM yyyy\") }}",
            context: context
        ) == "8 September 2026")
        #expect(PartTemplateRenderer.render(
            "{{ control.schedule[1] | formatDate('EEE d MMM') }}",
            context: context
        ) == "Tue 20 Oct")
        #expect(PartTemplateRenderer.render(
            "{{ control.published | addDays(7) }}",
            context: context
        ) == "2026-09-15")
        #expect(PartTemplateRenderer.render(
            "{{ control.published | addDays(control.offsetDays) }}",
            context: context
        ) == "2026-09-15")
        #expect(PartTemplateRenderer.render(
            "{{ control.published | formatDate(control.datePattern) }}",
            context: context
        ) == "8 September 2026")
        #expect(PartTemplateRenderer.render(
            "{{ control.published | addMonths(1) | formatDate('d MMMM yyyy') }}",
            context: context
        ) == "8 October 2026")

        let invalid = json.replacingOccurrences(of: "2026-09-08", with: "2026-02-30")
        let invalidManifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(invalid.utf8))
        let diagnostics = PartPackageValidator.validate(invalidManifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.message == "A date control requires a real calendar date using YYYY-MM-DD." })

        let outOfRange = json.replacingOccurrences(of: "2026-09-08", with: "2027-01-01")
        let outOfRangeManifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(outOfRange.utf8))
        let rangeDiagnostics = PartPackageValidator.validate(outOfRangeManifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(rangeDiagnostics.contains { $0.message == "The default date is after maximum." })
    }

    @Test
    func controlValuesSupportContextualOutputEncodingFilters() {
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.encoding",
            properties: [
                "title": .string("Gary's \"<Card>\" & more"),
                "query": .string("shoes & boots/large?"),
                "website": .string("https://example.com/my products?q=red shoes&sort=new"),
                "unsafeWebsite": .string("javascript:alert(1)"),
                "enabled": .boolean(true),
                "duration": .number(300),
                "items": .array([.string("one"), .number(2), .boolean(false)])
            ],
            slots: [:]
        )

        #expect(PartTemplateRenderer.render(
            "{{ control.title | escapeHTML }}",
            context: context
        ) == "Gary&#39;s &quot;&lt;Card&gt;&quot; &amp; more")
        #expect(PartTemplateRenderer.render(
            "{{ control.title | escapeHTMLAttribute }}",
            context: context
        ) == "Gary&#39;s &quot;&lt;Card&gt;&quot; &amp; more")
        #expect(PartTemplateRenderer.render(
            "{{ control.query | encodeURIComponent }}",
            context: context
        ) == "shoes%20%26%20boots%2Flarge%3F")
        #expect(PartTemplateRenderer.render(
            "{{ control.website | encodeURL }}",
            context: context
        ) == "https://example.com/my%20products?q=red%20shoes&sort=new")
        #expect(PartTemplateRenderer.render("{{ control.unsafeWebsite | encodeURL }}", context: context).isEmpty)
        #expect(PartTemplateRenderer.render("{{ control.enabled | encodeJSON }}", context: context) == "true")
        #expect(PartTemplateRenderer.render("{{ control.duration | encodeJSON }}", context: context) == "300")
        #expect(PartTemplateRenderer.render(
            "{{ control.items | encodeJSON }}",
            context: context
        ) == "[\"one\",2,false]")
        #expect(PartTemplateRenderer.render(
            "{{ control.title | encodeJSON }}",
            context: context
        ) == #""Gary's \"\u003CCard\u003E\" \u0026 more""#)
        #expect(PartTemplateRenderer.render(
            "{{ control.title | encodeJSON | escapeHTMLAttribute }}",
            context: context
        ) == #"&quot;Gary&#39;s \&quot;\u003CCard\u003E\&quot; \u0026 more&quot;"#)
    }

    @Test
    func partLibraryVisibilityDefaultsToShownAndCanBeHidden() throws {
        let defaultManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(defaultManifest.showsInPartLibrary)

        let hiddenManifestText = validManifest.replacingOccurrences(
            of: "\"templates\"",
            with: "\"showsInPartLibrary\" : false,\n            \"templates\""
        )
        let hiddenManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(hiddenManifestText.utf8)
        )
        #expect(!hiddenManifest.showsInPartLibrary)
    }

    @Test
    func phpCapabilityForcesPageExtensionWithoutAnInlinePHPTemplate() throws {
        let defaultManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(!defaultManifest.requiresPHP)

        let identifier = "com.example.php\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "\"assets\" : [{\"path\" : \"images/icon.svg\"}]",
                with: "\"assets\" : [{\"path\" : \"images/icon.svg\"}, {\"path\" : \"server/endpoint.php\"}]"
            )
            .replacingOccurrences(
                of: "\"templates\"",
                with: "\"requiresPHP\" : true,\n            \"templates\""
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["server/endpoint.php": "<?php echo 'ready'; ?>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        let part = PartNode(type: PartType(rawValue: identifier))
        let site = Site(name: "PHP", pages: [Page(title: "Home", slug: "index", parts: [part])])
        let bundle = StaticSiteRenderer().render(site: site)

        #expect(package.manifest.requiresPHP)
        #expect(bundle.file(at: "index.html") == nil)
        #expect(bundle.file(at: "index.php") != nil)
        #expect(bundle.file(at: "files/endpoint.php") != nil)
    }

    @Test
    func scopedAssetsPublishOnceAtTheirPageAndSiteDestinations() throws {
        let identifier = "com.example.scoped\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "\"assets\" : [{\"path\" : \"images/icon.svg\"}]",
                with: """
                "assets" : [
                    {"path" : "images/icon.svg"},
                    {"path" : "shared/icons", "scope" : "site"}
                ]
                """
            )
        let template = """
        <div {{ part.attributes }}>{{ asset("images/icon.svg") }}|{{ asset("shared/icons/star.svg") }}|{{ path.siteAssets }}|{{ site.baseURL }}|{{ page.url }}|{{ if preview }}preview{{ elseif published }}published{{ endif }}{{ childArea("content") }}</div>
        """
        let packageURL = try makePackage(
            manifest: manifest,
            template: template,
            additionalFiles: ["shared/icons/star.svg": "<svg>star</svg>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        let homePart = PartNode(type: PartType(rawValue: identifier))
        let aboutPart = PartNode(type: PartType(rawValue: identifier))
        var site = Site(name: "Scoped", pages: [
            Page(title: "Home", slug: "index", parts: [homePart]),
            Page(title: "About", slug: "about", parts: [aboutPart])
        ])
        site.publicURL = "https://example.com"
        let bundle = StaticSiteRenderer().render(site: site)
        let previewBundle = StaticSiteRenderer(environment: .preview).render(site: site)

        #expect(bundle.errors.isEmpty)
        #expect(bundle.file(at: "files/icon.svg") != nil)
        #expect(bundle.file(at: "about/files/icon.svg") != nil)
        #expect(bundle.files.filter { $0.path == "assets/shared/icons/star.svg" }.count == 1)
        #expect(bundle.file(at: "index.html")?.contents.contains("files/icon.svg|assets/shared/icons/star.svg|assets|https://example.com|https://example.com/|published") == true)
        #expect(bundle.file(at: "about/index.html")?.contents.contains("files/icon.svg|../assets/shared/icons/star.svg|../assets|https://example.com|https://example.com/about/|published") == true)
        #expect(previewBundle.file(at: "index.html")?.contents.contains("|preview") == true)
    }

    @Test @MainActor
    func canvasResolvesAndServesDeclaredPackageAssetsAtEitherScope() throws {
        let identifier = "com.example.canvasassets\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "\"assets\" : [{\"path\" : \"images/icon.svg\"}]",
                with: """
                "assets" : [
                    {"path" : "images/icon.svg"},
                    {"path" : "shared/icons", "scope" : "site"}
                ]
                """
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<div {{ part.attributes }}><img src=\"{{ asset(\"images/icon.svg\") }}\"><img src=\"{{ asset(\"shared/icons/star.svg\") }}\">{{ childArea(\"content\") }}</div>",
            additionalFiles: ["shared/icons/star.svg": "<svg>star</svg>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        let part = PartNode(type: PartType(rawValue: identifier))
        let page = Page(title: "Canvas assets", slug: "index", parts: [part])

        let html = HTMLPageRenderer().render(page: page, framework: .standard)
        let pageAssetReference = "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/images/icon.svg"
        let siteAssetReference = "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/shared/icons/star.svg"
        #expect(html.contains(pageAssetReference))
        #expect(html.contains(siteAssetReference))

        let handler = CanvasAssetSchemeHandler(assets: [:], packages: [identifier: package])
        let pageAssetURL = try #require(URL(string: pageAssetReference))
        let siteAssetURL = try #require(URL(string: siteAssetReference))
        #expect(handler.resource(for: pageAssetURL)?.mediaType == "image/svg+xml")
        #expect(handler.resource(for: siteAssetURL)?.data == Data("<svg>star</svg>".utf8))

        let undeclaredURL = try #require(URL(string: "\(CanvasAssetSchemeHandler.packageScheme)://\(identifier)/private.txt"))
        #expect(handler.resource(for: undeclaredURL) == nil)
    }

    @Test
    func loopRendersArbitraryMarkupAndPositionMetadata() {
        let template = """
        {{ loop 3 }}
        <span data-index="{{ loop.index }}">{{ loop.position }}/{{ loop.count }} {{ if loop.first }}first{{ elseif loop.last }}last{{ endif }}</span>
        {{ endloop }}
        """
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
            properties: [:],
            slots: [:]
        )

        let rendered = PartTemplateRenderer.render(template, context: context)

        #expect(rendered.contains("data-index=\"0\">1/3 first"))
        #expect(rendered.contains("data-index=\"1\">2/3 "))
        #expect(rendered.contains("data-index=\"2\">3/3 last"))
        #expect(rendered.components(separatedBy: "<span").count - 1 == 3)
    }

    @Test
    func nestedLoopExposesParentMetadata() {
        let template = "{{ loop 2 }}{{ loop 2 }}{{ loop.parent.position }}.{{ loop.position }};{{ endloop }}{{ endloop }}"
        let rendered = PartTemplateRenderer.render(
            template,
            context: .init(instanceID: UUID(), packageIdentifier: "com.example.loop", properties: [:], slots: [:])
        )

        #expect(rendered == "1.1;1.2;2.1;2.2;")
    }

    @Test
    func collectionLoopSupportsAliasesNestedCollectionsAndFiltering() {
        let template = """
        {{ loop navigation.items as item where item.visible }}
        {{ item.title }}:{{ loop item.children as child }}{{ child.title }}{{ if !loop.last }},{{ endif }}{{ endloop }};
        {{ endloop }}
        """
        let values: [PartPackageValue] = [
            .object([
                "title": .string("Home"),
                "visible": .boolean(true),
                "children": .array([.object(["title": .string("News")]), .object(["title": .string("About")])])
            ]),
            .object(["title": .string("Hidden"), "visible": .boolean(false), "children": .array([])])
        ]
        let rendered = PartTemplateRenderer.render(
            template,
            context: .init(
                instanceID: UUID(), packageIdentifier: "com.example.loop", properties: [:],
                templateValues: ["navigation.items": .array(values)], slots: [:]
            )
        )

        #expect(rendered.trimmingCharacters(in: .whitespacesAndNewlines) == "Home:News,About;")
    }

    @Test
    func reversedLoopsWorkWithCountsCollectionsAndFilters() {
        let values: [PartPackageValue] = [
            .object(["title": .string("First"), "visible": .boolean(true)]),
            .object(["title": .string("Hidden"), "visible": .boolean(false)]),
            .object(["title": .string("Last"), "visible": .boolean(true)])
        ]
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
            properties: [:],
            templateValues: ["pages.all": .array(values)],
            slots: [:]
        )

        let collection = PartTemplateRenderer.render(
            "{{ loop pages.all as page where page.visible reversed }}{{ page.title }}:{{ loop.position }}:{{ loop.first }}:{{ loop.last }};{{ endloop }}",
            context: context
        )
        let counted = PartTemplateRenderer.render(
            "{{ loop 4 reversed }}{{ loop.position }}{{ if !loop.last }},{{ endif }}{{ endloop }}",
            context: context
        )
        let sourcePositions = PartTemplateRenderer.render(
            "{{ loop 4 reversed }}{{ loop.sourcePosition }}{{ endloop }}",
            context: context
        )

        #expect(collection == "Last:1:true:false;First:2:false:true;")
        #expect(counted == "1,2,3,4")
        #expect(sourcePositions == "4321")
    }

    @Test
    func navigationLoopUsesPageHierarchyVisibilityAndCurrentState() throws {
        let identifier = "com.example.navigation\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: "").replacingOccurrences(of: "com.example.card", with: identifier),
            template: """
            <nav {{ part.attributes }}>{{ loop navigation.items as item }}
            <a href="{{ item.href }}">{{ item.title }}</a>
            {{ loop item.children as child }}<a href="{{ child.href }}"{{ if child.current }} aria-current="page"{{ endif }}>{{ child.title }}</a>{{ endloop }}
            {{ endloop }}{{ childArea("content") }}</nav>
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        let home = Page(title: "Home", slug: "index")
        let hidden = Page(title: "Hidden", slug: "hidden", parentPageID: home.id, includeInNavigation: false)
        let about = Page(title: "About", slug: "about", order: 2)
        let contact = Page(title: "Contact", slug: "contact", order: 1)
        let childPart = PartNode(type: .init(rawValue: identifier))
        var part = PartNode(type: .init(rawValue: identifier))
        part.children = [childPart]
        let current = Page(
            title: "Current & Selected", slug: "current", parts: [part], parentPageID: hidden.id
        )
        let site = Site(
            name: "Navigation",
            pages: [
                about,
                hidden,
                current,
                contact,
                home
            ]
        )
        let direct = PartTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: part.id,
                packageIdentifier: identifier,
                properties: [:],
                templateValues: PartNavigationTemplateValues.values(site: site, currentPage: current),
                slots: ["content": ""]
            )
        )
        #expect(direct.contains(">Home</a>"))
        let homeRange = try #require(direct.range(of: ">Home</a>"))
        let contactRange = try #require(direct.range(of: ">Contact</a>"))
        let aboutRange = try #require(direct.range(of: ">About</a>"))
        #expect(homeRange.lowerBound < contactRange.lowerBound)
        #expect(contactRange.lowerBound < aboutRange.lowerBound)
        PartRegistry.register(package)
        let html = try #require(
            StaticSiteRenderer(environment: .preview).render(site: site, assets: [:])
                .file(at: "hidden/current/index.html")?.contents
        )

        #expect(html.contains("href=\"/\">Home</a>"))
        #expect(html.contains("href=\"/hidden/current/\" aria-current=\"page\">Current &amp; Selected</a>"))
        #expect(!html.contains(">Hidden</a>"))
        #expect(html.contains("data-foundry-part"))
        #expect(html.contains("data-foundry-package=\"\(identifier)\""))
        #expect(html.contains("data-foundry-parent=\"\(part.id.uuidString)\""))

        let decodedHidden = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(hidden))
        #expect(decodedHidden.includeInNavigation == false)
    }

    @Test
    func breakpointTemplateValuesExposeEnabledStateAndMinimumWidth() {
        var site = Site(name: "Breakpoints", pages: [Page(title: "Home", slug: "index")])
        site.framework.screens.update(.medium) { $0.minimumWidth = 850 }
        site.framework.screens.update(.large) { $0.isEnabled = false }
        let page = site.pages[0]
        let template = """
        {{ if breakpoints.medium.enabled }}@media (min-width: {{ breakpoints.medium.minimumWidth }}px) { .card { display: grid; } }{{ endif }}
        {{ if breakpoints.large.enabled }}disabled breakpoint rendered{{ endif }}
        """

        let rendered = PartTemplateRenderer.render(
            template,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: "com.example.breakpoints",
                properties: [:],
                templateValues: PartNavigationTemplateValues.values(site: site, currentPage: page),
                slots: [:]
            )
        )

        #expect(rendered.contains("@media (min-width: 850px)"))
        #expect(!rendered.contains("disabled breakpoint rendered"))
    }

    @Test
    func controlLoopKeepsPrimitiveKeysStableAcrossCountChanges() {
        let template = """
        {{ loop control.itemCount }}<article>{{ text("card", default: "Card") }}{{ image("photo") }}</article>{{ endloop }}
        <footer>{{ text("footer", default: "Footer") }}</footer>
        """
        let maximums = ["itemCount": 4]
        let textPrimitives = PartTemplateRenderer.textPrimitives(in: template, loopMaximums: maximums)
        #expect(textPrimitives.map(\.key) == ["card", "footer"])
        #expect(textPrimitives.first?.isRepeated == true)
        #expect(PartTemplateRenderer.imagePrimitives(in: template).first?.isRepeated == true)

        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.loop",
            properties: [
                "itemCount": .number(2),
                "card": .array([.string("One"), .string("Two")]),
                "footer": .string("Footer value"),
                "photo": .array([.string("one.jpg"), .string("two.jpg")])
            ],
            slots: [:],
            loopMaximums: maximums
        )
        let rendered = PartTemplateRenderer.render(template, context: context)

        #expect(rendered.components(separatedBy: "<article>").count - 1 == 2)
        #expect(rendered.contains("One<img class=\"fd-image\" src=\"one.jpg\""))
        #expect(rendered.contains("Two<img class=\"fd-image\" src=\"two.jpg\""))
        #expect(rendered.contains("<footer>Footer value</footer>"))
        #expect(!rendered.contains("content3"))

        let editorContext = PartTemplateContext(
            instanceID: context.instanceID,
            packageIdentifier: context.packageIdentifier,
            properties: context.properties,
            slots: [:],
            enablesEditorMarkup: true,
            loopMaximums: maximums
        )
        let editorHTML = PartTemplateRenderer.render(template, context: editorContext)
        #expect(editorHTML.contains("data-foundry-primitive-property=\"card\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"photo\""))
        #expect(editorHTML.contains("data-foundry-property-path=\"0\""))

        let empty: PartProperty.Value = .array([])
        let edited = empty.settingValue(
            .url("asset://chosen"),
            at: [2, 4],
            defaultLeafValue: .url("")
        )

        #expect(edited.value(at: [2, 4]) == .url("asset://chosen"))
        #expect(edited.value(at: [0, 0]) == nil)
        #expect(edited.arrayValue?.count == 3)
        #expect(edited.arrayValue?[2].arrayValue?.count == 5)
    }

    @Test
    func loopValidationRequiresBalancedBlocksAndBoundedNumericControls() throws {
        let item = """
        {
            "id" : "itemCount",
            "label" : "Items",
            "type" : "number",
            "minimum" : 0,
            "maximum" : 12,
            "defaults" : {"base" : 4},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ loop control.itemCount reversed }}<b>{{ loop.position }}</b>{{ endloop }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        let package = try PartPackageLoader.load(from: validURL)
        #expect(package.loopMaximums == ["itemCount": 12])

        let invalidURL = try makePackage(
            manifest: manifestText.replacingOccurrences(of: "\"maximum\" : 12,", with: ""),
            template: "<section {{ part.attributes }}>{{ loop control.itemCount }}<b></b>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: invalidURL)
        }

        let legacyURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ repeat 2 }}<b></b>{{ endrepeat }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: legacyURL)
        }

        let invalidFilterURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ loop navigation.items as item where item.current && }}<b></b>{{ endloop }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidFilterURL) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: invalidFilterURL)
        }
    }

    @Test
    func loopAcceptsDirectiveWhitespaceAndLimitsNestedExpansion() throws {
        let whitespaceTemplate = "{{\n loop\t2 }}item{{ endloop }}"
        let expanded = try PartTemplateLoop.expand(
            whitespaceTemplate,
            properties: [:],
            maximums: [:]
        )
        #expect(expanded.template == "itemitem")

        let excessiveTemplate = "{{ loop 100 }}{{ loop 100 }}{{ loop 2 }}item{{ endloop }}{{ endloop }}{{ endloop }}"
        #expect(throws: PartTemplateLoop.LoopError.self) {
            try PartTemplateLoop.expand(
                excessiveTemplate,
                properties: [:],
                maximums: [:]
            )
        }
    }

    @Test
    func textPrimitivesUseDeclaredUniqueNamesAndStoredValues() throws {
        let template = #"<h2>{{ text("heading", default: "Start here") }}</h2><p>{{ text("body") }}</p><small>{{ text("note", default: "Note") }}</small>"#
        let defaultContext = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )
        let editedContext = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [
                "heading": .string("Edited & ready"),
                "body": .string("A shorter paragraph."),
                "note": .string("Updated note")
            ],
            slots: [:]
        )
        let editorContext = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:],
            partAttributes: "data-foundry-id=\"test-part\"",
            enablesEditorMarkup: true
        )

        let primitives = PartTemplateRenderer.textPrimitives(in: template)
        #expect(primitives.map(\.key) == ["heading", "body", "note"])
        let first = try #require(primitives.first)
        let paragraph = try #require(primitives.dropFirst().first)
        #expect(first.defaultValue == "Start here")
        #expect(paragraph.defaultValue.components(separatedBy: ".").count >= 3)
        #expect(PartTemplateRenderer.render(template, context: defaultContext).contains("Start here"))
        let edited = PartTemplateRenderer.render(template, context: editedContext)
        #expect(edited.contains("Edited &amp; ready"))
        #expect(edited.contains("A shorter paragraph."))
        #expect(edited.contains("Updated note"))
        let editorHTML = PartTemplateRenderer.render(template, context: editorContext)
        #expect(editorHTML.components(separatedBy: "data-foundry-inline-property=").count - 1 == 3)
        #expect(editorHTML.contains("data-foundry-inline-property=\"heading\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"body\""))
        #expect(editorHTML.contains("data-foundry-inline-property=\"note\""))
        #expect(editorHTML.components(separatedBy: "data-foundry-primitive-property=").count - 1 == 3)
        #expect(editorHTML.contains("data-foundry-primitive-property=\"heading\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"body\""))
        #expect(editorHTML.contains("data-foundry-primitive-property=\"note\""))
    }

    @Test
    func namedTextPrimitiveWithoutDefaultUsesOneLoremParagraphWithoutAnExportedWrapper() {
        let template = "<p>{{ text(\"body\") }}</p>"
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: [:],
            slots: [:]
        )

        let primitive = PartTemplateRenderer.textPrimitives(in: template)[0]
        #expect(primitive.key == "body")
        #expect(primitive.defaultValue.components(separatedBy: ".").count >= 6)
        let rendered = PartTemplateRenderer.render(template, context: context)
        #expect(rendered.hasPrefix("<p>Lorem ipsum"))
        #expect(!rendered.contains("<span"))
    }

    @Test
    func textPrimitivesRenderVersionedRichTextWithoutChangingPlainTextEscaping() {
        let template = #"<p>{{ text("body", default: "Start here") }}</p>"#
        let fragment = #"<strong>Hello</strong> <a href="https://example.com">world</a>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let richContext = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string(richValue)],
            slots: [:],
            partAttributes: "data-foundry-id=\"test-part\"",
            enablesEditorMarkup: true
        )
        let plainContext = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string("<script>alert('no')</script>")],
            slots: [:]
        )

        let richHTML = PartTemplateRenderer.render(template, context: richContext)
        #expect(richHTML.contains(fragment))
        #expect(richHTML.contains("data-foundry-inline-property=\"body\""))
        #expect(richHTML.contains("data-foundry-inline-source=\"\(Data(richValue.utf8).base64EncodedString())\""))

        let plainHTML = PartTemplateRenderer.render(template, context: plainContext)
        #expect(plainHTML.contains("&lt;script&gt;alert(&#39;no&#39;)&lt;/script&gt;"))
        #expect(!plainHTML.contains("<script>"))
    }

    @Test
    func richTextLinksPreserveStructureAndResolveAtRenderTime() throws {
        let pageID = UUID()
        let link = PartLink(
            destination: .page(pageID),
            anchor: "details",
            opensInNewWindow: true,
            attributes: [.init(name: "data-source", value: "rich text")]
        )
        let linkURL = try #require(FoundryRichTextCodec.URL(for: link))
        #expect(FoundryRichTextCodec.partLink(from: linkURL) == link)

        let fragment = #"<a href="\#(linkURL.absoluteString)">Learn more</a>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let page = Page(id: pageID, title: "About", slug: "about")
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.rich-link",
            properties: ["body": .string(richValue)],
            slots: [:],
            richTextLinkContext: .init(
                pages: [page],
                folders: [],
                assets: [],
                assetLibrary: [],
                publicURL: "",
                absoluteURL: false
            )
        )

        let rendered = PartTemplateRenderer.render(#"<p>{{ text("body") }}</p>"#, context: context)
        #expect(rendered.contains(#"href="/about/#details""#))
        #expect(rendered.contains(#"target="_blank""#))
        #expect(rendered.contains(#"data-source="rich text""#))
        #expect(rendered.contains(#"rel="noopener noreferrer""#))
        #expect(!rendered.contains("foundry-rich-link-v1:"))
    }

    @Test
    func richTextColoursResolveFromPalettesAtRenderTime() throws {
        let palettes = Framework.standard.colourPalettes
        let reference = RichTextColourReference(source: "accent", lightShade: .three, darkShade: .nine)
        #expect(RichTextColourReference(marker: reference.marker) == reference)

        let fragment = #"<span data-foundry-color="\#(reference.marker)">Highlight</span>"#
        let richValue = FoundryRichTextCodec.storageValue(forHTMLFragment: fragment)
        let light = try #require(reference.resolve(in: palettes, appearance: .light))
        let dark = try #require(reference.resolve(in: palettes, appearance: .dark))

        func rendered(mode: SiteAppearanceMode) -> String {
            let context = PartTemplateContext(
                instanceID: UUID(),
                packageIdentifier: "com.example.rich-colour",
                properties: ["body": .string(richValue)],
                slots: [:],
                richTextColourContext: .init(palettes: palettes, mode: mode)
            )
            return PartTemplateRenderer.render(#"<p>{{ text("body") }}</p>"#, context: context)
        }

        #expect(rendered(mode: .light).contains("<span style=\"color:\(light)\">"))
        #expect(rendered(mode: .dark).contains("<span style=\"color:\(dark)\">"))
        let both = rendered(mode: .both)
        #expect(both.contains("<span style=\"color:light-dark(\(light), \(dark))\">"))
        #expect(!both.contains("data-foundry-color"))

        // A deleted palette inherits the surrounding colour but keeps rendering,
        // and the reference survives in storage untouched for re-editing.
        let missing = FoundryRichTextCodec.resolvingColours(
            in: #"<span data-foundry-color="custom.gone:3:9">Text</span>"#,
            context: .init(palettes: palettes, mode: .both)
        )
        #expect(missing == "<span>Text</span>")
    }

    @Test
    func htmlPrimitivePreservesMarkupAndSupportsCanvasEditing() throws {
        let template = #"<div {{ part.attributes }}>{{ html("content", default: "<strong>Start here</strong>") }}</div>"#
        let editorContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.html",
            properties: ["content": .string("<em>Edited & ready</em>")], slots: [:],
            partAttributes: "data-foundry-id=\"test-part\"",
            enablesEditorMarkup: true
        )

        let primitive = try #require(PartTemplateRenderer.htmlPrimitives(in: template).first)
        #expect(primitive.key == "content")
        #expect(primitive.defaultValue == "<strong>Start here</strong>")
        let rendered = PartTemplateRenderer.render(template, context: editorContext)
        #expect(rendered.contains("<em>Edited & ready</em>"))
        #expect(rendered.contains("data-foundry-inline-property=\"content\""))
        #expect(rendered.contains("data-foundry-inline-html"))
        let encodedSource = Data("<em>Edited & ready</em>".utf8).base64EncodedString()
        #expect(rendered.contains("data-foundry-inline-source=\"\(encodedSource)\""))
    }

    @Test
    func namedHTMLPrimitiveWithoutDefaultUsesAnEditableListDefault() throws {
        let primitive = try #require(PartTemplateRenderer.htmlPrimitives(in: "<div>{{ html(\"content\") }}</div>").first)

        #expect(primitive.defaultValue.contains("<ul>"))
        #expect(primitive.defaultValue.components(separatedBy: "<li>").count - 1 == 3)
    }

    @Test
    func namedImagePrimitiveRendersItsDeclaredProperty() {
        let template = "<figure {{ part.attributes }}>{{ image(\"hero\") }}</figure>"
        let editorContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: [:], slots: [:], partAttributes: "data-editor=\"true\"",
            enablesEditorMarkup: true
        )
        let exportContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.image",
            properties: ["hero": .string("assets/hero & wide.jpg")], slots: [:]
        )

        #expect(PartTemplateRenderer.hasImagePrimitive(in: template))
        #expect(PartTemplateRenderer.render(template, context: editorContext).contains("data-foundry-image-drop-zone"))
        let exported = PartTemplateRenderer.render(template, context: exportContext)
        #expect(exported.contains("class=\"fd-image\""))
        #expect(exported.contains("src=\"assets/hero &amp; wide.jpg\""))
    }

    @Test
    func namedVideoPrimitiveRendersItsDeclaredProperty() {
        let template = "<figure {{ part.attributes }}>{{ video(\"film\") }}</figure>"
        let emptyEditorContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.video",
            properties: [:], slots: [:], partAttributes: "data-editor=\"true\"",
            enablesEditorMarkup: true
        )
        let filledEditorContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.video",
            properties: [
                "film": .string("foundry-asset:00000000-0000-0000-0000-000000000000"),
                "film.poster": .string("data:image/jpeg;base64,abc")
            ],
            slots: [:], enablesEditorMarkup: true
        )
        let exportContext = PartTemplateContext(
            instanceID: UUID(), packageIdentifier: "com.example.video",
            properties: ["film": .string("assets/launch & day.mp4")], slots: [:]
        )

        #expect(PartTemplateRenderer.hasVideoPrimitive(in: template))
        #expect(PartTemplateRenderer.videoPrimitives(in: template) == [.init(key: "film", isRepeated: false)])
        let emptyEditor = PartTemplateRenderer.render(template, context: emptyEditorContext)
        #expect(emptyEditor.contains("data-foundry-video-drop-zone"))
        #expect(emptyEditor.contains("data-foundry-video-property=\"film\""))
        let filledEditor = PartTemplateRenderer.render(template, context: filledEditorContext)
        #expect(filledEditor.contains("<video class=\"fd-video\""))
        #expect(filledEditor.contains("poster=\"data:image/jpeg;base64,abc\""))
        #expect(!filledEditor.contains("src="))
        let exported = PartTemplateRenderer.render(template, context: exportContext)
        #expect(exported.contains("<video class=\"fd-video\""))
        #expect(exported.contains("src=\"assets/launch &amp; day.mp4\""))
        #expect(exported.contains(" controls playsinline"))
        #expect(!exported.contains("data-foundry-video-drop-zone"))
    }

    @Test
    func imageControlMayOmitItsDefaultAndResponsiveKeys() throws {
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: """
                {
                    "id" : "source",
                    "label" : "Image",
                    "type" : "image"
                }
                """).utf8)
        )
        let image = try #require(manifest.resolvedProperties.first)

        #expect(image.defaultValue == .string(""))
        #expect(!image.responsive)
        #expect(image.alt.isEmpty)
        #expect(!image.focalPoint)
        #expect(image.renditions.isEmpty)
    }

    @Test
    func imageControlSupportsStaticClampedRenditions() throws {
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: """
                {
                    "id" : "source",
                    "label" : "Image",
                    "type" : "image",
                    "renditions" : [
                        {"id" : "thumbnail", "maximumDimension" : 480},
                        {"id" : "hero", "maximumDimension" : 5000}
                    ]
                }
                """).utf8)
        )
        let image = try #require(manifest.resolvedProperties.first)
        #expect(image.renditions.map(\.id) == ["thumbnail", "hero"])
        #expect(image.renditions.map(\.effectiveMaximumDimension) == [480, 3_840])

        let rendered = PartTemplateRenderer.render(
            #"<img src="{{ control.source.rendition.thumbnail.href }}">"#,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: "com.example.image",
                properties: [
                    "source": .string("assets/original.png"),
                    "source.rendition.thumbnail": .string("assets/renditions/thumb.png")
                ],
                slots: [:]
            )
        )
        #expect(rendered.contains(#"src="assets/renditions/thumb.png""#))
    }

    @Test
    func imageControlHrefResolvesDeclaredPackageAssetPaths() {
        let rendered = PartTemplateRenderer.render(
            #"<section style="background-image: url('{{ control.background.href }}')"></section>"#,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: "com.example.hero",
                properties: [
                    "background.href": .string("images/default.svg")
                ],
                slots: [:],
                assetPaths: [
                    "images/default.svg": "foundry-package-asset://com.example.hero/images/default.svg"
                ]
            )
        )
        #expect(rendered.contains("foundry-package-asset://com.example.hero/images/default.svg"))
    }

    @Test
    func staticExportPublishesOneSharedRenditionForRepeatedPartUse() throws {
        let identifier = "com.example.rendition\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: """
                {
                    "id" : "source",
                    "label" : "Image",
                    "type" : "image",
                    "renditions" : [
                        {"id" : "thumbnail", "maximumDimension" : 20}
                    ]
                }
                """).replacingOccurrences(of: "com.example.card", with: identifier),
            template: #"<figure {{ part.attributes }}><img src="{{ control.source.rendition.thumbnail.href }}">{{ childArea("content") }}</figure>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        let data = try testPNG(width: 100, height: 50)
        let asset = ProjectAsset(
            filename: "hero.png",
            mediaType: "image/png",
            byteCount: data.count,
            contentDigest: FoundryDocumentSnapshot.digest(for: data),
            pixelWidth: 100,
            pixelHeight: 50
        )
        var first = PartNode(type: .init(rawValue: identifier))
        first.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        var second = PartNode(type: .init(rawValue: identifier))
        second.setProperty(.init(rawValue: "source"), value: .url(asset.reference))
        let site = Site(
            name: "Renditions",
            pages: [
                Page(title: "Home", slug: "index", parts: [first]),
                Page(title: "About", slug: "about", parts: [second])
            ],
            assets: [asset]
        )
        let bundle = StaticSiteRenderer().render(
            site: site,
            assets: [asset.id: .init(asset: asset, data: data)]
        )
        let renditionPath = "assets/renditions/\(asset.id.uuidString.lowercased())-20.png"
        let rendition = try #require(bundle.file(at: renditionPath))
        #expect(PartImageMetadata.inspect(data: rendition.data, filename: "hero.png", mimeType: "image/png").width == 20)
        #expect(bundle.files.filter { $0.path == renditionPath }.count == 1)
        #expect(bundle.file(at: "index.html")?.contents.contains(renditionPath) == true)
        #expect(bundle.file(at: "about/index.html")?.contents.contains("../" + renditionPath) == true)
    }

    @Test
    func staticPreviewResolvesManagedAssetsInLoopImagePrimitives() throws {
        let identifier = "com.example.repeatedimages\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: "").replacingOccurrences(of: "com.example.card", with: identifier),
            template: "<section {{ part.attributes }}>{{ loop 2 }}{{ image(\"photo\") }}{{ endloop }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        PartRegistry.register(try PartPackageLoader.load(from: packageURL))

        let first = ProjectAsset(filename: "first.png", mediaType: "image/png", byteCount: 1, contentDigest: "test-digest-first")
        let second = ProjectAsset(filename: "second.png", mediaType: "image/png", byteCount: 1, contentDigest: "test-digest-second")
        var part = PartNode(type: .init(rawValue: identifier))
        part.setProperty(
            .init(rawValue: "photo"),
            value: .array([.url(first.reference), .url(second.reference)])
        )
        let site = Site(
            name: "Repeated Images",
            pages: [Page(title: "Home", slug: "index", parts: [part])],
            assets: [first, second]
        )
        let bundle = StaticSiteRenderer(environment: .preview).render(
            site: site,
            assets: [
                first.id: .init(asset: first, data: Data([0])),
                second.id: .init(asset: second, data: Data([1]))
            ]
        )
        let html = try #require(bundle.file(at: "index.html")?.contents)

        #expect(html.contains("src=\"assets/\(first.readableExportFilename)\""))
        #expect(html.contains("src=\"assets/\(second.readableExportFilename)\""))
        #expect(!html.contains("foundry-asset:"))
    }

    @Test
    func imageControlProvidesAltAndStructuredTemplateValues() throws {
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: """
                {
                    "id" : "source",
                    "label" : "Image",
                    "type" : "image",
                    "alt" : "Default description",
                    "focalPoint" : true
                }
                """),
            template: """
                <figure {{ part.attributes }}><img src="{{ control.source.href }}" width="{{ control.source.width }}" height="{{ control.source.height }}" data-type="{{ control.source.mimeType }}" data-bytes="{{ control.source.byteCount }}" data-name="{{ control.source.filename }}" data-extension="{{ control.source.extension }}" data-ratio="{{ control.source.aspectRatio }}" data-x="{{ control.source.focalPointX }}" data-y="{{ control.source.focalPointY }}" style="object-position: {{ control.source.position }}" alt="{{ control.source.alt }}">{{ childArea("content") }}</figure>
                """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        #expect(package.manifest.resolvedProperties.first?.responsive == true)
        let definitions = PartPackageAdapter.definition(from: package).properties
        let altDefinition = try #require(definitions.first {
            $0.key == PartPackageAdapter.imageAltKey(for: "source")
        })
        #expect(altDefinition.label == "Alt")
        #expect(altDefinition.defaultValue == .string("Default description"))
        #expect(!altDefinition.isResponsive)
        #expect(!altDefinition.isInspectorVisible)
        let imageDefinition = try #require(definitions.first { $0.key.rawValue == "source" })
        #expect(imageDefinition.supportsImageFocalPoint)
        #expect(imageDefinition.isResponsive)
        let focalPointDefinition = try #require(definitions.first {
            $0.key == PartPackageAdapter.imageFocalPointKey(for: "source")
        })
        #expect(!focalPointDefinition.isInspectorVisible)
        #expect(focalPointDefinition.defaultValue == .array([.number(50), .number(50)]))
        #expect(focalPointDefinition.isResponsive)

        var values: [String: PartPackageValue] = ["source": .string("files/photo.png")]
        PartImageTemplateValues.insert(
            propertyID: "source",
            href: "files/photo.png",
            alt: "A <bright> photograph",
            focalPointX: 37.5,
            focalPointY: 62,
            metadata: .init(
                width: 1600,
                height: 900,
                mimeType: "image/png",
                byteCount: 42_000,
                filename: "Holiday Photo.png"
            ),
            into: &values
        )
        let rendered = PartTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: package.manifest.identifier,
                properties: values,
                slots: [:]
            )
        )
        #expect(rendered.contains("src=\"files/photo.png\""))
        #expect(rendered.contains("width=\"1600\""))
        #expect(rendered.contains("height=\"900\""))
        #expect(rendered.contains("data-type=\"image/png\""))
        #expect(rendered.contains("data-bytes=\"42000\""))
        #expect(rendered.contains("data-name=\"Holiday Photo.png\""))
        #expect(rendered.contains("data-extension=\"png\""))
        #expect(rendered.contains("data-ratio=\"1.777778\""))
        #expect(rendered.contains("data-x=\"37.5\""))
        #expect(rendered.contains("data-y=\"62\""))
        #expect(rendered.contains("object-position: 37.5% 62%"))
        #expect(rendered.contains("alt=\"A &lt;bright&gt; photograph\""))
    }

    @Test
    func imageMacroRequiresADeclaredPersistentName() throws {
        let manifestText = manifest(withInspectorEntries: """
            {
                "id" : "title",
                "label" : "Title",
                "type" : "text",
                "defaults" : {"base" : "Hello"},
                "responsive" : false
            }
            """)
        let barePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ part.attributes }}>{{ image }}{{ childArea(\"content\") }}</figure>"
        )
        let wrongTypePackage = try makePackage(
            manifest: manifestText,
            template: "<figure {{ part.attributes }}>{{ image title }}{{ childArea(\"content\") }}</figure>"
        )
        defer {
            try? FileManager.default.removeItem(at: barePackage)
            try? FileManager.default.removeItem(at: wrongTypePackage)
        }

        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: barePackage)
        }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: wrongTypePackage)
        }
    }

    @Test
    func imageDefaultMustBeDeclaredAndResolvesThroughAssetPaths() throws {
        let validImageManifest = manifest(withInspectorEntries: """
            {
                "id" : "source",
                "label" : "Image",
                "type" : "image",
                "defaults" : {"base" : "images/icon.svg"}
            }
            """)
        let packageURL = try makePackage(
            manifest: validImageManifest,
            template: "<figure {{ part.attributes }}><img src=\"{{ control.source }}\" alt=\"\">{{ childArea(\"content\") }}</figure>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        #expect(package.manifest.resolvedProperties.first?.defaultValue == .string("images/icon.svg"))

        let rendered = PartTemplateRenderer.render(
            package.htmlTemplate,
            context: .init(
                instanceID: UUID(),
                packageIdentifier: package.manifest.identifier,
                properties: ["source": .string("images/icon.svg")],
                slots: [:],
                assetPaths: ["images/icon.svg": "files/icon.svg"]
            )
        )
        #expect(rendered.contains("src=\"files/icon.svg\""))

        let invalidManifest = validImageManifest.replacingOccurrences(
            of: "\"defaults\" : {\"base\" : \"images/icon.svg\"}",
            with: "\"defaults\" : {\"base\" : \"images/missing.svg\"}"
        )
        let invalidPackage = try makePackage(
            manifest: invalidManifest,
            template: "<figure {{ part.attributes }}><img src=\"{{ control.source }}\" alt=\"\">{{ childArea(\"content\") }}</figure>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackage) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: invalidPackage)
        }
    }

    @Test
    func textPrimitivePreservesEditedLineBreaks() {
        let template = "<p>{{ text(\"body\") }}</p>"
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.text",
            properties: ["body": .string("First line\nSecond & final line")],
            slots: [:]
        )

        #expect(
            PartTemplateRenderer.render(template, context: context)
                == "<p>First line<br>Second &amp; final line</p>"
        )
    }

    @Test
    func removedSlotSyntaxIsRejectedAndNotRendered() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ part.attributes }}>{{ slot.content }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        let context = PartTemplateContext(
            instanceID: UUID(),
            packageIdentifier: "com.example.card",
            properties: [:],
            slots: ["content": "<strong>Child</strong>"]
        )

        #expect(diagnostics.contains {
            $0.severity == .error
                && $0.message == "Slot macros are not supported. Declare a childPicker and render it with {{ childArea(\"id\") }}."
        })
        #expect(!PartTemplateRenderer.render("{{ slot.content }}", context: context).contains("Child"))
    }

    @Test
    func validatorReportsTemplateContractErrorsWithLineLocations() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: """
            <section>
              {{ control.missing }}
              {{ slot id="unknown" }}
              {{ asset("../secret.txt") }}
              {{ id }}
              {{ mystery }}
              {{ if control.title }}
            </section>
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        let messages = diagnostics.map(\.message)

        #expect(messages.contains(where: { $0.contains("part.attributes") }))
        #expect(messages.contains(where: { $0.contains("Unknown property 'missing'") }))
        #expect(messages.contains(where: { $0.contains("Slot macros are not supported") }))
        #expect(messages.contains(where: { $0.contains("childPicker 'content'") }))
        #expect(messages.contains(where: { $0.contains("Asset paths must be relative") }))
        #expect(messages.contains(where: { $0.contains("Unknown value 'id'") }))
        #expect(messages.contains(where: { $0.contains("unbalanced") }))
        #expect(messages.contains(where: { $0.contains("Unknown template macro 'mystery'") }))
        #expect(diagnostics.contains(where: { $0.location == "part.html:2" }))
    }

    @Test
    func validatorRequiresNamedFunctionSyntaxForPersistentTemplateMacros() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section class="sample {{ part.class }}" {{ part.attributes }}>{{ text }}{{ html="<p>Old</p>" }}{{ image }}{{ dropZone "content" }}{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains { $0.contains("Every editable macro must have a permanent quoted name") })
        #expect(messages.contains { $0.contains("Every drop zone must have a permanent quoted name") })
    }

    @Test
    func validatorRequiresUniquePersistentTemplateNames() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section class="sample {{ part.class }}" {{ part.attributes }}>{{ text("shared") }}{{ image("shared") }}{{ dropZone("shared") }}{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains {
            $0 == "Editable macro and drop-zone names must be unique; 'shared' is used more than once."
        })
    }

    @Test
    func validatorReservesRootIDAndRequiresRootClassHook() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section id="developer-root" {{ part.attributes }}>{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let templateURL = packageURL.appending(path: "Resources/part.html")
        try #"<section id="developer-root" {{ part.attributes }}>{{ childArea("content") }}</section>"#
            .write(to: templateURL, atomically: true, encoding: .utf8)
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        let messages = diagnostics.map(\.message)

        #expect(messages.contains("The part root cannot declare an id."))
        #expect(messages.contains("The root class must include {{ part.class }}."))
    }

    @Test
    func validatorRequiresWhitespaceAroundRootClassHook() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: #"<section class="sample{{ part.class }}" {{ part.attributes }}>{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains(
            "Separate {{ part.class }} from adjacent class names with literal whitespace."
        ))
    }

    @Test
    func validatorAllowsQuotedTemplateExpressionsInsideRootClassAttribute() throws {
        let template = #"""
        <nav class="navbar {{ if contains(control.position, 'fixed-bottom') }}fixed-bottom{{ endif }} {{ if contains(control.position, 'fixed-top') }}fixed-top{{ endif }} navbar-theme {{ if control.style == 'menubar' }}navbar-expand{{ control.expand }}{{ endif }} bg-{{ control.color }} {{ part.class }}" {{ part.attributes }}></nav>
        """#
        let packageURL = try makePackage(manifest: validManifest, template: template)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains("The root class must include {{ part.class }}.") == false)
    }

    @Test
    func validatorRequiresAllPrimaryHTMLOutputInsideOneStableRoot() throws {
        let invalidTemplates = [
            "Before {{ control.title }}<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>",
            "<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>After",
            "<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section><aside>Sibling</aside>",
            "{{ if control.title }}<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>{{ endif }}"
        ]
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        for template in invalidTemplates {
            let packageURL = try makePackage(manifest: validManifest, template: template)
            defer { try? FileManager.default.removeItem(at: packageURL) }
            let diagnostics = PartPackageValidator.validate(
                manifest,
                rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
            )

            #expect(diagnostics.contains {
                $0.severity == .error
                    && $0.message.contains("exactly one stable top-level root element")
            })
        }
    }

    @Test
    func validatorAllowsCommentsWhitespaceAndNestedMarkupInsidePrimaryHTMLRoot() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: """
            <!-- The comment is outside the rendered part. -->
            <section class="sample {{ part.class }}" {{ part.attributes }}>
                <section>{{ control.title }}</section>
                {{ loop 2 }}<span>{{ loop.position }}</span>{{ endloop }}
                {{ childArea("content") }}
            </section>
            <!-- Trailing comments are also inert. -->
            """
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(!diagnostics.contains { $0.message.contains("exactly one stable top-level root element") })
    }

    @Test
    func loaderAppliesRootOwnershipRuleOnlyWhenValidationIsEnabled() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "Outside<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        #expect(throws: Never.self) {
            _ = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false)
        }
        #expect(throws: PartPackageLoadingError.self) {
            _ = try PartPackageLoader.loadForCatalog(from: packageURL, validates: true)
        }
    }

    @Test
    func validatorRejectsMoreThanFiveTags() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: "\"description\" : \"A test card.\"",
            with: """
            "description" : "A test card.",
            "tags" : [
                "one", "two", "three",
                "four", "five", "six"
            ]
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains {
            $0.location == "manifest.json:tags" && $0.message == "A part can declare at most 5 tags."
        })
    }

    @Test
    func loaderProcessesInstanceScopedCSSTemplateFiles() throws {
        let manifest = validManifest.replacingOccurrences(
            of: instanceCSSDeclaration,
            with: """
            "files" : [
                {
                    "path" : "instance.css",
                    "scope" : "instance"
                },
                {
                    "path" : "default-scope.css"
                }
            ]
            """
        )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: [
                "instance.css": ":host { color: red; }",
                "default-scope.css": ":instance { display: block; }"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)

        #expect(package.manifest.render.files.map(\.scope) == [.instance, .instance])
        #expect(package.css.contains("color: red"))
        #expect(package.css.contains("display: block"))
    }

    @Test
    func validatorRejectsUnimplementedTemplateScopesAndFormats() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: instanceCSSDeclaration,
            with: """
            "files" : [
                {"path" : "part.scss", "scope" : "instance"}
            ]
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.scss": ":host {}"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains(where: { $0.message.contains("support CSS, JavaScript, PHP and placed HTML") }))
    }

    @Test
    func loaderProcessesScopedJavaScriptTemplates() throws {
        let declaration = """
        "files" : [
            {"path" : "instance.js", "scope" : "instance"},
            {"path" : "page.js", "scope" : "page", "closure" : false}
        ]
        """
        let manifestText = validManifest
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: [
                "instance.js": "document.querySelector('[data-foundry-id=\"{{ instance.id }}\"]');",
                "page.js": "console.log('{{ package.id }} page');"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)

        #expect(package.instanceJavaScript.hasPrefix("(function (part) {"))
        #expect(package.instanceJavaScript.contains("\"use strict\";"))
        #expect(package.instanceJavaScript.contains(#"document.querySelector('[data-foundry-id=\"{{ instance.id }}\"]')"#))
        #expect(package.instanceJavaScript.contains("const foundry = Object.freeze"))
        #expect(package.instanceJavaScript.contains("children: foundryChildren"))
        #expect(package.instanceJavaScript.contains("descendants: foundryDescendants"))
        #expect(package.instanceJavaScript.contains("ancestors: foundryAncestors"))
        #expect(package.instanceJavaScript.contains("closest: (packageIdentifier)"))
        #expect(package.pageJavaScript.contains("page"))
        #expect(!package.pageJavaScript.contains("(function ()"))
    }

    @Test
    func validatorAllowsSiteScopeOnlyForCSS() throws {
        let declaration = """
        "files" : [
            {"path" : "site.js", "scope" : "site"},
            {"path" : "site.php", "scope" : "site"}
        ]
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "\"templates\"", with: "\"requiresPHP\" : true,\n            \"templates\"")
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: [
                "site.js": "console.log('site');",
                "site.php": "<?php $site = true; ?>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.filter { $0.message == "Site scope is available only to CSS templates." }.count == 2)
    }

    @Test
    func staticRendererConnectsInstanceJavaScriptToItsPartElement() throws {
        let identifier = "com.example.javascript\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        "files" : [
            {"path" : "instance.js", "scope" : "instance"}
        ]
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section class=\"test {{ part.class }}\" {{ part.attributes }}><button>Test</button>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["instance.js": "part.querySelector('button');"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        let node = PartNode(type: PartType(rawValue: identifier))
        let site = Site(name: "JavaScript", pages: [Page(title: "Home", slug: "index", parts: [node])])

        let bundle = StaticSiteRenderer().render(site: site)
        let html = try #require(bundle.file(at: "index.html")?.contents)
        let pageJavaScript = try #require(bundle.file(at: "files/page.js")?.contents)

        #expect(html.contains("data-foundry-id=\"\(node.id.uuidString)\""))
        #expect(!html.contains("id=\"foundry-"))
        #expect(pageJavaScript.contains(##"document.querySelector('[data-foundry-id=\"\##(node.id.uuidString)\"]')"##))
    }

    @Test @MainActor
    func renderersAddValidUniversalRootValuesAndOmitInvalidOnes() throws {
        let identifier = "com.example.anchor\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let packageURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: identifier),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        let node = PartNode(
            type: PartType(rawValue: identifier),
            anchor: "contact-us",
            customClasses: "featured wide",
            rootAttributes: [.init(name: "aria-label", value: "Contact & help")]
        )
        let invalidNode = PartNode(
            type: PartType(rawValue: identifier),
            anchor: "123 invalid!",
            rootAttributes: [
                .init(name: "onclick", value: "alert(1)"),
                .init(name: "data-foundry-test", value: "reserved")
            ]
        )
        let site = Site(
            name: "Anchor",
            pages: [Page(title: "Home", slug: "index", parts: [node, invalidNode])]
        )
        let html = try #require(StaticSiteRenderer().render(site: site).file(at: "index.html")?.contents)
        let canvasHTML = HTMLPageRenderer().render(page: site.pages[0], framework: .standard)

        #expect(html.contains("data-foundry-id=\"\(node.id.uuidString)\""))
        #expect(html.contains("id=\"contact-us\""))
        #expect(html.contains("featured wide"))
        #expect(html.contains("aria-label=\"Contact &amp; help\""))
        #expect(html.contains("data-foundry-id=\"\(invalidNode.id.uuidString)\""))
        #expect(!html.contains("id=\"123 invalid!\""))
        #expect(!html.contains("onclick="))
        #expect(!html.contains("data-foundry-test="))
        #expect(canvasHTML.contains("id=\"contact-us\""))
        #expect(!canvasHTML.contains("id=\"123 invalid!\""))
    }

    @Test
    func manifestRejectsRemovedAnchorOptInKey() throws {
        let manifestText = validManifest.replacingOccurrences(
            of: "\"minimumAPIVersion\"",
            with: "\"anchor\" : true,\n            \"minimumAPIVersion\""
        )
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifestText.utf8))

        #expect(diagnostics.contains { $0.location == "manifest.json:anchor" && $0.message.contains("Unknown key") })
    }

    @Test
    func loaderProcessesScopedPHPTemplatesIntoExportedPagePrelude() throws {
        let identifier = "com.example.phptemplates\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        "files" : [
            {"path" : "instance.php", "scope" : "instance"},
            {"path" : "page.php", "scope" : "page"}
        ]
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: "\"templates\"", with: "\"requiresPHP\" : true,\n            \"templates\"")
            .replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: [
                "instance.php": "<?php $partIDs[] = '{{ instance.id }}'; ?>",
                "page.php": "<?php $package = '{{ package.id }}'; ?>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        let type = PartType(rawValue: identifier)
        let first = PartNode(type: type)
        let second = PartNode(type: type)
        let site = Site(name: "PHP", pages: [Page(title: "Home", slug: "index", parts: [first, second])])
        let php = try #require(StaticSiteRenderer().render(site: site).file(at: "index.php")?.contents)

        #expect(package.instancePHP.contains("$partIDs"))
        #expect(php.hasPrefix("<?php"))
        #expect(php.contains(first.id.uuidString.lowercased()))
        #expect(php.contains(second.id.uuidString.lowercased()))
        #expect(php.components(separatedBy: "$package =").count - 1 == 1)
        let doctypeRange = try #require(php.range(of: "<!doctype html>"))
        #expect(doctypeRange.lowerBound > php.startIndex)
    }

    @Test
    func validatorRequiresPhpExtensionForPHPTemplates() throws {
        let declaration = """
        "files" : [{"path" : "part.php"}]
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.php": "<?php return; ?>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifestText.utf8))

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains { $0.location == "manifest.json:requiresPHP" })
    }

    @Test
    func textAlignmentSpecializedControlProvidesValidatedLogicalValues() throws {
        let item = """
        {
            "id" : "alignment",
            "label" : "Alignment",
            "type" : "textAlignment",
            "defaults" : {"base" : "start"},
            "responsive" : true
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }} style=\"text-align: {{ control.alignment }}\">{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first { $0.key.rawValue == "alignment" })

        if case .textAlignment = property.control {} else { Issue.record("Expected the specialised text-alignment control") }
        #expect(property.defaultValue == .choice("start"))
        #expect(property.isResponsive)
    }

    @Test
    func controlsDefaultToTheSettingsGroup() throws {
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        // The title control sits inside the Content section wrapper; the
        // top-level childPicker carries no wrapper and lands in Settings.
        #expect(manifest.resolvedProperties.first?.group == "Content")
        #expect(manifest.resolvedProperties.last?.group == "Settings")
    }

    @Test
    func multiSelectRejectsFrameworkValues() throws {
        let item = """
        {
            "id" : "sizes",
            "label" : "Font sizes",
            "type" : "select",
            "frameworkValues" : "fontSizes",
            "count" : 2,
            "defaults" : {"base" : ["base", "base"]},
            "responsive" : false
        }
        """
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withInspectorEntries: item).utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains {
            $0.location == "manifest.json:inspector.sizes.frameworkValues" &&
                $0.message == "Select supports only declared options; remove frameworkValues."
        })
    }

    @Test
    func numberControlUnitsAreOptionalAndLimitedToThreeCharacters() throws {
        let numberItem = """
        {
            "id" : "spacing",
            "label" : "Spacing",
            "type" : "number",
            "defaults" : {"base" : 12},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: numberItem)
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let property = try #require(manifest.resolvedProperties.first)
        #expect(property.units == [""])

        let invalidText = manifestText.replacingOccurrences(
            of: "\"type\" : \"number\"",
            with: "\"type\" : \"number\", \"units\" : \"pixels\""
        )
        let invalidManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(invalidText.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            invalidManifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains { $0.message == "A control unit can contain at most three characters." })
    }

    @Test
    func sliderUsesContinuousDefaultStepVisualTicksAndOptionalUnits() throws {
        let sliderItem = """
        {
            "id" : "opacity",
            "label" : "Opacity",
            "type" : "slider",
            "minimum" : 0,
            "maximum" : 100,
            "ticks" : 11,
            "units" : "%",
            "defaults" : {"base" : 50},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: sliderItem)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ part.attributes }}>{{ control.opacity }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .slider(let options) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(options.range == 0...100)
        #expect(options.step == 0)
        #expect(options.ticks == 11)
        #expect(options.unit == "%")
        #expect(!options.editableValue)
    }

    @Test
    func multiSliderSupportsOneDisplayUnitPerValue() throws {
        let item = """
        {
            "id" : "dimensions",
            "label" : "Dimensions",
            "type" : "slider",
            "count" : 3,
            "units" : ["px", "rem", "%"],
            "defaults" : {"base" : [20, 4, 80]},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ part.attributes }}>{{ control.dimensions[0] }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .array(_, let count, _, _, _, _, _, _, let units, _) = property.control else {
            Issue.record("Expected a multi control")
            return
        }

        #expect(count == 3)
        #expect(units == ["px", "rem", "%"])
    }

    @Test
    func sliderRequiresExplicitBaseDefault() throws {
        let cases: [(minimum: Double, maximum: Double, expected: Double)] = [
            (-100, 100, 0),
            (10, 100, 10),
            (-100, -10, -10)
        ]

        for testCase in cases {
            let item = """
            {
                "id" : "slider",
                "label" : "Slider",
                "type" : "slider",
                "minimum" : \(testCase.minimum),
                "maximum" : \(testCase.maximum),
                "responsive" : false
            }
            """
            let manifestText = manifest(withInspectorEntries: item)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifestText.utf8))
            }
        }
    }

    @Test
    func sliderCanMakeItsValueEditable() throws {
        let item = """
        {
            "id" : "slider",
            "label" : "Slider",
            "type" : "slider",
            "editableValue" : true,
            "defaults" : {"base" : 0},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ part.attributes }}>{{ control.slider }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .slider(let options) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(options.editableValue)
    }

    @Test
    func sliderRejectsShowsValueField() throws {
        let entry = #"{"id":"slider","label":"Slider","type":"slider","showsValueField":true,"defaults":{"base":0},"responsive":false}"#
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entry).utf8))
        #expect(diagnostics.contains { $0.severity == .error && $0.message.contains("editableValue") })
    }

    @Test
    func sliderStepSnapsIndependentlyOfTicks() {
        #expect(InspectorSliderValueResolver.resolve(48.020833, range: -100...100, step: 1) == 48)
        #expect(InspectorSliderValueResolver.resolve(0.86, range: 0...1, step: 0.1) == 0.9)
        #expect(InspectorSliderValueResolver.resolve(12.345, range: 0...100, step: 0) == 12.345)
        #expect(InspectorSliderValueResolver.resolve(12, range: 10...20, step: 3) == 13)
    }

    @Test
    func sliderRejectsInvalidTicksStepRangeAndUnit() throws {
        let item = """
        {
            "id" : "slider",
            "label" : "Slider",
            "type" : "slider",
            "minimum" : 10,
            "maximum" : 10,
            "step" : -1,
            "ticks" : 1,
            "units" : "pixels",
            "defaults" : {"base" : 10},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        let messages = Set(diagnostics.map(\.message))

        #expect(messages.contains("The control maximum must be greater than its minimum."))
        #expect(messages.contains("The control step cannot be negative."))
        #expect(messages.contains("Slider ticks must be zero or at least two."))
        #expect(messages.contains("A control unit can contain at most three characters."))
    }

    @Test
    func sliderCustomisationsReachTheInspectorOptions() throws {
        let item = """
        {
            "id" : "rows",
            "label" : "Rows",
            "type" : "slider",
            "minimum" : 0,
            "maximum" : 12,
            "step" : 1,
            "ticks" : 3,
            "tickLabels" : {"0" : "Auto", "12" : "12"},
            "valueLabels" : {"0" : "Auto"},
            "minimumLabel" : {"systemImage" : "sun.min", "title" : "Dim"},
            "maximumLabel" : {"title" : "Bright"},
            "neutralValue" : 6,
            "defaults" : {"base" : 0},
            "responsive" : false
        }
        """
        let packageURL = try makePackage(
            manifest: manifest(withInspectorEntries: item),
            template: "<output {{ part.attributes }}>{{ control.rows }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .slider(let options) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(options.tickLabels == [.init(value: 0, text: "Auto"), .init(value: 12, text: "12")])
        #expect(options.valueLabel(for: 0) == "Auto")
        #expect(options.valueLabel(for: 1) == nil)
        #expect(options.minimumLabel == .init(title: "Dim", systemImage: "sun.min"))
        #expect(options.maximumLabel == .init(title: "Bright", systemImage: nil))
        #expect(options.neutralValue == 6)
        // The three even marks and the two labelled values share 0 and 12.
        #expect(options.tickValues == [0, 6, 12])
        #expect(options.tickLabel(at: 0) == "Auto")
        #expect(options.tickLabel(at: 6) == nil)
    }

    @Test(arguments: [
        #""tickLabels":{"auto":"Auto"}"#,
        #""tickLabels":{"0":""}"#,
        #""valueLabels":["Auto"]"#,
        #""minimumLabel":{}"#,
        #""minimumLabel":{"symbol":"sun.min"}"#,
        #""neutralValue":"0""#,
        #""valueLabels":{"0":"Auto"},"editableValue":true"#
    ])
    func sliderCustomisationsRejectMalformedValues(_ setting: String) throws {
        let entry = #"{"id":"slider","label":"Slider","type":"slider",\#(setting),"defaults":{"base":0},"responsive":false}"#
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entry).utf8))
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test
    func sliderOnlyKeysAreRejectedOnOtherControls() throws {
        let entry = #"{"id":"size","label":"Size","type":"number","tickLabels":{"0":"None"},"defaults":{"base":0},"responsive":false}"#
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest(withInspectorEntries: entry).utf8))
        #expect(diagnostics.contains { $0.message == "Only a slider control accepts tickLabels." })
    }

    @Test
    func sliderLabelledValuesMustFallInsideTheRange() throws {
        let item = """
        {
            "id" : "slider",
            "label" : "Slider",
            "type" : "slider",
            "minimum" : 0,
            "maximum" : 10,
            "tickLabels" : {"20" : "Far"},
            "valueLabels" : {"-1" : "Off"},
            "neutralValue" : 11,
            "defaults" : {"base" : 0},
            "responsive" : false
        }
        """
        let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest(withInspectorEntries: item).utf8))
        let messages = Set(PartPackageValidator.validate(manifest, rootURL: FileManager.default.temporaryDirectory).map(\.message))

        #expect(messages.contains("tickLabels value 20 is outside the slider's range."))
        #expect(messages.contains("valueLabels value -1 is outside the slider's range."))
        #expect(messages.contains("The slider's neutralValue is outside its range."))
    }

    @Test
    func dividerCustomControlIsPresentationOnly() throws {
        let item = """
        {
            "id" : "contentDivider",
            "type" : "divider"
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(
            PartPackageAdapter.definition(from: package).properties.first {
                $0.key.rawValue == "contentDivider"
            }
        )
        if case .divider = property.control {} else { Issue.record("Expected a divider control") }
        #expect(!property.isResponsive)

        let invalidPackageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ control.contentDivider }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: invalidPackageURL) }
        let diagnostics = PartPackageValidator.validate(
            package.manifest,
            rootURL: invalidPackageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        #expect(diagnostics.contains { $0.message.contains("Unknown property 'contentDivider'") })

        let unsupportedKeys = ["label", "subtitle", "tooltip", "default", "responsive", "count", "group"]
        for key in unsupportedKeys {
            let value: String
            switch key {
            case "responsive": value = "true"
            case "count": value = "2"
            default: value = "\"Unsupported\""
            }
            let invalidItem = """
            {
                "id" : "divider",
                "type" : "divider",
                "\(key)" : \(value)
            }
            """
            let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: invalidItem).utf8)
            )
            #expect(schemaDiagnostics.contains { $0.severity == .error })
        }
    }

    @Test
    func dividerAndNoteMayOmitTheirIDs() throws {
        let entries = """
        { "type" : "divider" },
        { "type" : "note", "body" : "First" },
        { "section" : "Layout", "controls" : [
            { "type" : "divider" },
            { "type" : "note", "body" : "Second" }
        ] }
        """
        let manifestText = manifest(withInspectorEntries: entries)
        let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifestText.utf8))
        #expect(!schemaDiagnostics.contains { $0.severity == .error }, "\(schemaDiagnostics)")

        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        func omittable(_ manifest: PartPackageManifest) -> [PartPackageProperty] {
            manifest.resolvedProperties.filter { $0.control.type.permitsOmittedID }
        }
        let properties = omittable(package.manifest)
        let allSynthesized = properties.allSatisfy { $0.hasSynthesizedID }
        #expect(properties.count == 4)
        #expect(allSynthesized)
        // Each declaration gets its own id, and loading again yields the same ones.
        #expect(Set(properties.map(\.id)).count == 4)
        let reloaded = omittable(try PartPackageLoader.load(from: packageURL).manifest).map(\.id)
        #expect(reloaded == properties.map(\.id))

        let diagnostics = PartPackageValidator.validate(
            package.manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
    }

    @Test
    func spacerNeedsNoIDAndDefaultsToTenPoints() throws {
        let entries = """
        { "type" : "spacer" },
        { "type" : "spacer", "height" : 24 }
        """
        let manifestText = manifest(withInspectorEntries: entries)
        let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifestText.utf8))
        #expect(!schemaDiagnostics.contains { $0.severity == .error }, "\(schemaDiagnostics)")

        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        let heights = PartPackageAdapter.definition(from: package).properties.compactMap { property -> Double? in
            if case .spacer(let height) = property.control { return height }
            return nil
        }
        #expect(heights == [10, 24])
        let diagnostics = PartPackageValidator.validate(
            package.manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
    }

    @Test(arguments: [
        #"{ "type" : "spacer", "height" : 0 }"#,
        #"{ "type" : "spacer", "height" : 31 }"#,
        #"{ "type" : "spacer", "height" : "10" }"#,
        #"{ "type" : "spacer", "height" : true }"#,
        #"{ "type" : "spacer", "label" : "Gap" }"#,
        #"{ "id" : "size", "type" : "number", "height" : 10, "defaults" : { "base" : 1 } }"#
    ])
    func spacerRejectsInvalidDeclarations(_ entry: String) throws {
        let diagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: entry).utf8)
        )
        #expect(diagnostics.contains { $0.severity == .error }, "No error for \(entry)")
    }

    @Test
    func spacerAcceptsItsFullRange() throws {
        for height in [1, 30] {
            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: #"{ "type" : "spacer", "height" : \#(height) }"#).utf8)
            )
            #expect(!diagnostics.contains { $0.severity == .error }, "height \(height): \(diagnostics)")
        }
    }

    @Test
    func mathStillRequiresAnID() throws {
        let entries = """
        { "type" : "math", "argument1" : 1, "argument2" : 2, "operation" : "add" }
        """
        let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: entries).utf8)
        )
        #expect(schemaDiagnostics.contains { $0.severity == .error && $0.location.hasSuffix(":id") })
    }

    @Test
    func noteCustomControlUsesDedicatedContentKeys() throws {
        let validItem = """
        {
            "id" : "guidance",
            "type" : "note",
            "title" : "About this setting",
            "body" : "Helpful guidance.",
            "systemImage" : "info.circle"
        }
        """
        let validData = Data(manifest(withInspectorEntries: validItem).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: validData).isEmpty)

        let decodedManifest = try JSONDecoder().decode(PartPackageManifest.self, from: validData)
        let property = try #require(decodedManifest.resolvedProperties.first)
        #expect(property.noteTitle == "About this setting")
        #expect(property.noteBody == "Helpful guidance.")
        #expect(property.noteSystemImage == "info.circle")
        #expect(property.label.isEmpty)
        #expect(property.subtitles.isEmpty)
        #expect(!property.responsive)
        #expect(property.control.count == nil)

        let unsupportedKeys = ["label", "subtitle", "responsive", "count", "group"]
        for key in unsupportedKeys {
            let value = switch key {
            case "responsive": "true"
            case "count": "2"
            default: "\"Unsupported\""
            }
            let item = """
            {
                "id" : "guidance",
                "type" : "note",
                "body" : "Helpful guidance.",
                "\(key)" : \(value)
            }
            """

            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "manifest.json:inspector[0]:\(key)" &&
                    $0.message == "A note control does not support \(key)."
            })
        }

        let missingBodyItem = """
        {
            "id" : "guidance",
            "type" : "note"
        }
        """
        let missingBodyDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: missingBodyItem).utf8)
        )
        #expect(missingBodyDiagnostics.contains {
            $0.location == "manifest.json:inspector[0]:body" &&
                $0.message == "A body string is required."
        })
    }

    @Test
    func linkControlRejectsCountAndResponsive() throws {
        for key in ["count", "responsive"] {
            let value = key == "count" ? "2" : "true"
            let item = """
            {
                "id" : "destination",
                "type" : "link",
                "label" : "Destination",
                "defaults" : {"base" : ""},
                "\(key)" : \(value)
            }
            """

            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "manifest.json:inspector[0]:\(key)" &&
                    $0.message == "A link control does not support \(key)."
            })
        }
    }

    @Test
    func loaderProcessesPageScopedHTMLPlacements() throws {
        let declaration = """
        "files" : [
            {
                "path" : "head.html",
                "scope" : "page",
                "placement" : "headEnd"
            },
            {
                "path" : "body.html",
                "scope" : "page",
                "placement" : "bodyEnd"
            }
        ]
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: [
                "head.html": "<meta name=\"package\" content=\"{{ package.id }}\">",
                "body.html": "<div data-package=\"{{ package.id }}\"></div>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)

        #expect(package.placedHTML.map(\.placement) == [.headEnd, .bodyEnd])
        #expect(package.placedHTML.first?.contents.contains("{{ package.id }}") == true)
    }

    @Test
    func loaderProcessesSiteScopedCSSAndRejectsInstanceMacrosThere() throws {
        let declaration = """
        "files" : [
            {"path" : "site.css", "scope" : "site"}
        ]
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["site.css": ".package-{{ package.id }} { box-sizing: border-box; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try PartPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.isEmpty)
        #expect(package.siteCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["site.css": "[data-foundry-id=\"{{ instance.id }}\"] { display: none; }"]
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func loaderProcessesPageScopedCSSAndRejectsInstanceMacrosThere() throws {
        let declaration = """
        "files" : [
            {"path" : "page.css", "scope" : "page"}
        ]
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["page.css": "[data-foundry-package=\"{{ package.id }}\"] { display: block; }"]
        )
        defer { try? FileManager.default.removeItem(at: validURL) }

        let package = try PartPackageLoader.load(from: validURL)
        #expect(package.css.isEmpty)
        #expect(package.pageCSS.contains("{{ package.id }}"))

        let invalidURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["page.css": "[data-foundry-id=\"{{ instance.id }}\"] { color: {{ control.title }}; }"]
        )
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.load(from: invalidURL)
        }
    }

    @Test
    func insertingThroughChildPickerStoresItsIdentifierOnTheChild() throws {
        let packageURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: "com.example.named-slot-parent"),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let parentID = UUID()
        var tree = [PartNode(id: parentID, type: PartType(rawValue: package.manifest.identifier))]
        let child = PartNode.make(.paragraph)

        let didInsert = tree.insert(child, at: .insideSlot(parentID, "content"))

        #expect(didInsert)
        let insertedChild = try #require(tree.first?.children.first)
        #expect(insertedChild.slotID == "content")
    }

    @Test
    func childPickersEnforceAcceptedTypesMaximumAndLockedContainment() throws {
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: "com.example.managed-parent")
            .replacingOccurrences(of: "\"label\" : \"Content\"", with: "\"label\" : \"Cards\"")
            .replacingOccurrences(
                of: "\"accepts\" : [\"*\"]",
                with: "\"accepts\" : [\"foundry.content.paragraph\"], \"initial\" : [\"foundry.content.paragraph\"], \"minimum\" : 1, \"maximum\" : 2, \"containment\" : \"locked\""
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        let parentID = UUID()
        let firstID = UUID()
        var tree = [PartNode(
            id: parentID,
            type: PartType(rawValue: package.manifest.identifier),
            children: [PartNode(id: firstID, type: .paragraph, slotID: "content")]
        )]

        let insertedButton = tree.insert(PartNode.make(.button), at: .insideSlot(parentID, "content"))
        let insertedSecondParagraph = tree.insert(PartNode.make(.paragraph), at: .insideSlot(parentID, "content"))
        let insertedThirdParagraph = tree.insert(PartNode.make(.paragraph), at: .insideSlot(parentID, "content"))
        let movedOutside = tree.moveNode(withID: firstID, to: .end)
        let reorderedInside = tree.moveNode(withID: firstID, to: .insideSlot(parentID, "content"))
        let canDeleteAboveMinimum = tree.permitsRemoving(firstID)
        var treeAtMinimum = tree
        _ = treeAtMinimum.extractNode(withID: firstID)
        let remainingChildID = try #require(treeAtMinimum.first?.children.first?.id)

        #expect(!insertedButton)
        #expect(insertedSecondParagraph)
        #expect(!insertedThirdParagraph)
        #expect(!movedOutside)
        #expect(reorderedInside)
        #expect(canDeleteAboveMinimum)
        #expect(!treeAtMinimum.permitsRemoving(remainingChildID))
    }

    @Test
    func childPickerCreatesInitialChildrenRecursively() throws {
        let grandchildIdentifier = "com.example.initial-grandchild"
        let childIdentifier = "com.example.initial-child"
        let parentIdentifier = "com.example.initial-parent"
        let acceptsDeclaration = "\"accepts\" : [\"*\"]"

        let grandchildURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: grandchildIdentifier),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: grandchildURL) }
        let grandchildPackage = try PartPackageLoader.load(from: grandchildURL)
        PartRegistry.register(grandchildPackage)
        defer { PartRegistry.unregisterPackage(identifier: grandchildIdentifier) }

        let childInitial = """
        \(acceptsDeclaration),
        "initial" : [
            "\(grandchildIdentifier)",
            "\(grandchildIdentifier)"
        ]
        """
        let childURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: childIdentifier)
                .replacingOccurrences(of: "\"pickerItems\" : [\"com.example.child\"]", with: "\"pickerItems\" : [\"\(grandchildIdentifier)\"]")
                .replacingOccurrences(of: acceptsDeclaration, with: childInitial),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: childURL) }
        let childPackage = try PartPackageLoader.load(from: childURL)
        PartRegistry.register(childPackage)
        defer { PartRegistry.unregisterPackage(identifier: childIdentifier) }

        let parentInitial = """
        \(acceptsDeclaration),
        "initial" : [
            "\(childIdentifier)",
            "\(grandchildIdentifier)",
            "\(childIdentifier)"
        ]
        """
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
                .replacingOccurrences(of: "\"pickerItems\" : [\"com.example.child\"]", with: "\"pickerItems\" : [\"\(childIdentifier)\"]")
                .replacingOccurrences(of: acceptsDeclaration, with: parentInitial),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let parentPackage = try PartPackageLoader.load(from: parentURL)
        PartRegistry.register(parentPackage)
        defer { PartRegistry.unregisterPackage(identifier: parentIdentifier) }

        let parent = PartNode.make(PartType(rawValue: parentIdentifier))

        #expect(parent.children.map(\.type.rawValue) == [
            childIdentifier,
            grandchildIdentifier,
            childIdentifier
        ])
        #expect(parent.children.allSatisfy { $0.slotID == "content" })
        #expect(parent.children.first?.children.map(\.type.rawValue) == [
            grandchildIdentifier,
            grandchildIdentifier
        ])
        #expect(parent.children.first?.children.allSatisfy { $0.slotID == "content" } == true)
    }

    @Test
    func childPickerCanOfferFewerTypesThanItAccepts() throws {
        let childIdentifier = "com.example.picker-child"
        let parentIdentifier = "com.example.picker-parent"
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
                .replacingOccurrences(of: "\"pickerItems\" : [\"com.example.child\"]", with: "\"pickerItems\" : [\"\(childIdentifier)\"]"),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let parentPackage = try PartPackageLoader.load(from: parentURL)
        let slot = try #require(parentPackage.manifest.slots.first)

        #expect(slot.acceptsPart(.paragraph))
        #expect(!slot.offersInPicker(.paragraph))
        #expect(slot.offersInPicker(PartType(rawValue: childIdentifier)))
    }

    @Test
    func childPickerValidatesInitialChildren() throws {
        let wrongShape = validManifest.replacingOccurrences(
            of: "\"accepts\" : [\"*\"]",
            with: "\"accepts\" : [\"*\"], \"initial\" : 2"
        )
        let invalidValues = validManifest
            .replacingOccurrences(
                of: "\"pickerItems\" : [\"com.example.child\"]",
                with: "\"pickerItems\" : [\"Invalid\", \"com.example.child\"]"
            )
            .replacingOccurrences(
                of: "\"accepts\" : [\"*\"]",
                with: "\"accepts\" : [\"com.example.child\"], \"initial\" : [\"com.example.child\", \"com.example.other\"], \"maximum\" : 1"
            )

        let wrongShapeDiagnostics = try PartPackageManifestSchema.diagnostics(for: Data(wrongShape.utf8))
        let invalidValueDiagnostics = try PartPackageManifestSchema.diagnostics(for: Data(invalidValues.utf8))

        #expect(wrongShapeDiagnostics.contains { $0.location.contains("initial") && $0.message.contains("strings") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("pickerItems[0]") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("initial") && $0.message.contains("maximum") })
        #expect(invalidValueDiagnostics.contains { $0.location.contains("initial[1]") && $0.message.contains("permitted") })
    }

    @Test
    func childPickerContainmentDefaultsToOpenAndDecodesLocked() throws {
        let openManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(openManifest.slots.first?.containment == .open)

        let lockedText = validManifest.replacingOccurrences(
            of: "\"accepts\" : [\"*\"]",
            with: "\"accepts\" : [\"*\"], \"containment\" : \"locked\""
        )
        let lockedManifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(lockedText.utf8)
        )
        #expect(lockedManifest.slots.first?.containment == .locked)
    }

    @Test(arguments: ["", #", "buttonText": "Add Card""#, #", "buttonIcon": "square.stack""#,
                      #", "buttonText": "Add Card", "buttonIcon": "square.stack""#])
    func childPickerButtonPresentationLoadsAndRoundTrips(_ presentation: String) throws {
        let manifest = validManifest.replacingOccurrences(
            of: "\"accepts\" : [\"*\"]",
            with: "\"accepts\" : [\"*\"]" + presentation
        )
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest.utf8))
        #expect(diagnostics.filter { $0.severity == .error }.isEmpty)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: Data(manifest.utf8))
        let slot = try #require(decoded.slots.first)
        #expect(slot.buttonText == (presentation.contains("buttonText") ? "Add Card" : "Add Child"))
        #expect(slot.buttonIcon == (presentation.contains("buttonIcon") ? "square.stack" : "plus.app"))
        let encoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(PartPackageManifest.self, from: encoded)
        #expect(roundTripped.slots == decoded.slots)
    }

    @Test(arguments: ["buttonText", "buttonIcon"], ["42", "true", "[]", "{}", "\"\"", "\"   \""])
    func childPickerButtonPresentationRejectsInvalidValues(_ key: String, _ value: String) throws {
        let manifest = validManifest.replacingOccurrences(of: "\"accepts\" : [\"*\"]",
            with: "\"accepts\" : [\"*\"], \"\(key)\": \(value)")
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest.utf8))
        #expect(diagnostics.contains { $0.severity == .error && $0.location.contains(key) })
    }

    @Test
    func dropZoneCreatesAnOrdinaryUnslottedChildArea() throws {
        let identifier = "com.example.drop-zone-parent"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration + ",", with: "")
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section class=\"container {{ part.class }}\" {{ part.attributes }}>{{ dropZone(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: identifier) }

        let parentID = UUID()
        var tree = [PartNode(id: parentID, type: PartType(rawValue: identifier))]
        let child = PartNode(type: PartType(rawValue: "com.example.any-child"))

        #expect(package.hasDropZone)
        #expect(PartPackageAdapter.definition(from: package).allowsChildren)
        let inserted = tree.insert(child, at: .inside(parentID))
        #expect(inserted)
        #expect(tree.node(withID: child.id)?.slotID == package.dropZoneSlotID(for: "content"))
    }

    @Test
    func removedNamedDropZonePreservesItsChildrenUntilTheNameReturns() throws {
        let identifier = "com.example.updated-drop-zone-parent"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration + ",", with: "")
        let originalURL = try makePackage(
            manifest: manifest,
            template: "<main class=\"layout {{ part.class }}\" {{ part.attributes }}>{{ dropZone(\"content\") }}{{ dropZone(\"sidebar\") }}</main>"
        )
        let updatedURL = try makePackage(
            manifest: manifest,
            template: "<main class=\"layout {{ part.class }}\" {{ part.attributes }}>{{ dropZone(\"content\") }}</main>"
        )
        defer {
            PartRegistry.unregisterPackage(identifier: identifier)
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: updatedURL)
        }

        let originalPackage = try PartPackageLoader.load(from: originalURL)
        PartRegistry.register(originalPackage)
        let parentID = UUID()
        let child = PartNode(type: PartType(rawValue: "com.example.sidebar-child"))
        var tree = [PartNode(id: parentID, type: PartType(rawValue: identifier))]
        let inserted = tree.insert(
            child,
            at: .insideSlot(parentID, originalPackage.dropZoneSlotID(for: "sidebar"))
        )
        #expect(inserted)

        let updatedPackage = try PartPackageLoader.load(from: updatedURL)
        PartRegistry.register(updatedPackage)
        let preservedSlotID = tree.node(withID: child.id)?.slotID
        #expect(preservedSlotID == LoadedPartPackage.dropZoneSlotPrefix + "sidebar")
        #expect(updatedPackage.isDropZoneSlotID(preservedSlotID ?? "") == false)
        #expect(LoadedPartPackage.dropZoneName(forSlotID: preservedSlotID ?? "") == "sidebar")
        #expect(tree.node(withID: child.id) != nil)

        PartRegistry.register(originalPackage)
        #expect(originalPackage.isDropZoneSlotID(tree.node(withID: child.id)?.slotID ?? ""))
    }

    @Test
    func allowedParentsRestrictsChildPlacement() throws {
        let parentIdentifier = "com.example.allowed-parent"
        let childIdentifier = "com.example.restricted-child"
        let parentManifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration + ",", with: "")
        let childManifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: childIdentifier)
            .replacingOccurrences(
                of: "\"title\" : \"Card\"",
                with: "\"title\" : \"Card\", \"allowedParents\" : [\"\(parentIdentifier)\"]"
            )
        let parentURL = try makePackage(
            manifest: parentManifest,
            template: "<section class=\"container {{ part.class }}\" {{ part.attributes }}>{{ dropZone(\"content\") }}</section>"
        )
        let childURL = try makePackage(
            manifest: childManifest,
            template: "<article class=\"card {{ part.class }}\" {{ part.attributes }}>{{ childArea(\"content\") }}</article>"
        )
        defer {
            try? FileManager.default.removeItem(at: parentURL)
            try? FileManager.default.removeItem(at: childURL)
        }
        let parentPackage = try PartPackageLoader.load(from: parentURL)
        let childPackage = try PartPackageLoader.load(from: childURL)
        PartRegistry.register(parentPackage)
        PartRegistry.register(childPackage)
        defer {
            PartRegistry.unregisterPackage(identifier: parentIdentifier)
            PartRegistry.unregisterPackage(identifier: childIdentifier)
        }

        let parentID = UUID()
        let child = PartNode.make(PartType(rawValue: childIdentifier))
        var tree = [PartNode(id: parentID, type: PartType(rawValue: parentIdentifier))]

        #expect(!tree.accepts(child, at: .end))
        let inserted = tree.insert(child, at: .inside(parentID))
        #expect(inserted)
    }

    @Test @MainActor
    func builtInsAreLoadedAsPublicPartPackages() async throws {
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        #expect(catalog.phase == .ready)
        #expect(!catalog.isInitialLoading)
        let bundledPackages = catalog.packages.values.filter {
            $0.rootURL.path.contains("BuiltInParts.bundle")
        }
        let builtIns = bundledPackages.map(PartPackageAdapter.definition)

        #expect(builtIns.allSatisfy { $0.renderKind == .package })
        #expect(builtIns.allSatisfy { definition in
            definition.package?.rootURL.deletingLastPathComponent().lastPathComponent == "Parts"
        })
        #expect(Set(builtIns.compactMap { $0.package?.manifest.identifier }).count == builtIns.count)
        #expect(PartType.image.definition.package?.manifest.identifier == PartType.image.rawValue)
        #expect(PartType.section.definition.package?.manifest.identifier == PartType.section.rawValue)
        #expect(PartType.section.definition.allowsChildren)
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "spacing.frameworkPadding" })
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "spacing.frameworkMargin" })
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "sizing.heightMode" })
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "layout.position" })
        #expect(!PartType.section.definition.properties.contains { $0.key.rawValue == "minimumHeight" })
        #expect(PartType.stack.definition.properties.contains { $0.key.rawValue == "borders.frameworkBorder.width" })
        #expect(PartType.stack.definition.properties.contains { $0.key.rawValue == "reveal.revealEffect" })
        #expect(PartType.grid.definition.properties.contains { $0.key.rawValue == "layout.overflow" })
        #expect(!PartType.grid.definition.properties.contains { $0.key.rawValue == "overflow" })
        #expect(PartType.image.definition.properties.contains { $0.key == .source && $0.isInspectorVisible })
        // Image uses the standard Sizing group, starting at 1200px wide.
        #expect(PartType.image.definition.properties.contains {
            $0.key.rawValue == "sizing.customWidth" && $0.defaultValue == .number(1200)
        })
        #expect(!PartType.image.definition.properties.contains { $0.key.rawValue == "maxWidth" })
        #expect(PartType.image.definition.properties.contains {
            $0.key.rawValue == "alignment" && $0.defaultValue == .choice("center") && $0.isResponsive
        })
        let bundledIdentifiers = Set(bundledPackages.map(\.manifest.identifier))
        #expect(bundledIdentifiers.isSubset(of: Set(PartType.allCases.map(\.rawValue))))
        let html = try #require(catalog.packages["foundry.content.html"])
        let htmlDefinition = PartPackageAdapter.definition(from: html)
        #expect(htmlDefinition.properties.contains { $0.key.rawValue == "content" && !$0.isInspectorVisible })

        let container = PartNode.make(.section)
        let page = Page(title: "Layout", slug: "index", parts: [container])
        let rendered = HTMLPageRenderer().render(
            page: page,
            framework: Framework.standard
        )
        #expect(rendered.contains("<section"))
        #expect(rendered.contains("fd-section__content"))
    }

    @Test @MainActor
    func installedStressPartCatalogLoadTime() async throws {
        let installedRoot = try FoundryPackLoader.installedPacksURL()
        let stressPackURL = installedRoot.appending(
            path: "FoundryStressTest.foundrypack",
            directoryHint: .isDirectory
        )
        guard FileManager.default.fileExists(atPath: stressPackURL.path) else {
            print("Stress benchmark skipped because FoundryStressTest.foundrypack is not installed.")
            return
        }
        let expectedCount = FoundryPackLoader.packURLs(in: stressPackURL, includingRoot: true)
            .filter { $0.pathExtension.lowercased() == "foundrypack" }
            .count - 1

        let stressPartURLs = FoundryPackLoader.packURLs(in: stressPackURL, includingRoot: true)
            .filter {
                $0.pathExtension.lowercased() == "foundrypack"
                    && $0.standardizedFileURL != stressPackURL.standardizedFileURL
            }
        let catalog = PartPackageCatalog.shared
        await catalog.waitUntilLoaded()
        let profileStart = ContinuousClock.now
        let measuredTimings = await withTaskGroup(of: (Int, PartPackageLoadTimings?).self) { group in
            var results = Array<PartPackageLoadTimings?>(repeating: nil, count: stressPartURLs.count)
            let workerCount = min(4, stressPartURLs.count)
            for index in 0..<workerCount {
                group.addTask {
                    (index, try? PartPackageLoader.loadWithDiagnostics(from: stressPartURLs[index]).timings)
                }
            }
            var nextIndex = workerCount
            for await (index, timings) in group {
                results[index] = timings
                if nextIndex < stressPartURLs.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, try? PartPackageLoader.loadWithDiagnostics(from: stressPartURLs[index]).timings)
                    }
                }
            }
            return results.compactMap { $0 }.reduce(PartPackageLoadTimings(), +)
        }
        let profileElapsed = profileStart.duration(to: .now)
        func seconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }
        let measuredWork = seconds(measuredTimings.total)
        let validationWork = seconds(measuredTimings.validation)
        let validationPercentage = measuredWork > 0 ? validationWork / measuredWork * 100 : 0
        print("""
        Profiled \(stressPartURLs.count) stress parts in \(profileElapsed):
          manifest reads: \(seconds(measuredTimings.manifestRead))s
          schema validation: \(seconds(measuredTimings.schemaValidation))s
          manifest decoding: \(seconds(measuredTimings.manifestDecoding))s
          semantic validation: \(seconds(measuredTimings.semanticValidation))s
          resource loading: \(seconds(measuredTimings.resourceLoading))s
          validation total: \(validationWork)s (\(validationPercentage)% of measured package work)
        """)

        let clock = ContinuousClock()
        let start = clock.now
        let validationMode = PartValidationPreference.mode
        catalog.reloadAllPacks()
        await catalog.waitUntilLoaded()
        let elapsed = start.duration(to: clock.now)
        let estimatedValidationWallTime = seconds(profileElapsed) * validationPercentage / 100
        let loadedCount = catalog.packages.keys.filter {
            $0.hasPrefix("foundry.stress.part")
        }.count

        print("Loaded and published \(loadedCount) stress parts in \(elapsed).")
        print("Catalog validation mode: \(validationMode.rawValue).")
        if validationMode == .allPacks {
            let validationShare = estimatedValidationWallTime / seconds(elapsed) * 100
            print("Estimated validation share of this catalog load: \(validationShare)% (\(estimatedValidationWallTime)s).")
        } else {
            let estimatedValidatedLoadTime = seconds(elapsed) + estimatedValidationWallTime
            let potentialValidationShare = estimatedValidationWallTime / estimatedValidatedLoadTime * 100
            print("Estimated validation cost avoided: \(estimatedValidationWallTime)s (\(potentialValidationShare)% of an estimated validated load).")
        }
        #expect(loadedCount == expectedCount)
        #expect(elapsed < .seconds(20), "The installed stress catalog should reload within 20 seconds.")
    }

    @Test
    func catalogIndexRestoresPreparedDefinitionsWithoutLoadingRuntimePayloads() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ part.attributes }}>{{ text(\"content\", default: \"Cached text\") }}</div>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let initial = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false)
        #expect(!initial.package.isPayloadLoaded)
        #expect(PartPackageAdapter.definition(from: initial.package).properties.contains {
            $0.defaultValue == .string("Cached text")
        })
        #expect(!initial.package.isPayloadLoaded)
        PartPackagePreparedIndex.flush()

        let cached = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false)
        #expect(cached.timings.total == .zero)
        #expect(!cached.package.isPayloadLoaded)
        #expect(cached.package.htmlTemplate.contains("Cached text"))
        #expect(cached.package.isPayloadLoaded)
    }

    @Test
    func lazyPayloadFailureIsTransactionalAndRecoversAfterReload() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ part.attributes }}>Recoverable</div>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let cssURL = packageURL.appending(path: "Resources/part.css")
        let originalCSS = try Data(contentsOf: cssURL)
        let package = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false).package
        try FileManager.default.removeItem(at: cssURL)

        #expect(throws: PartPackagePayloadFailure.self) {
            try package.preparePayload()
        }
        #expect(!package.isPayloadLoaded)
        #expect(package.payloadFailure?.location == "Resources/part.css")

        try originalCSS.write(to: cssURL)
        let reloaded = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false).package
        try reloaded.preparePayload()
        #expect(reloaded.isPayloadLoaded)
        #expect(reloaded.css.contains("display: block"))
    }

    @Test @MainActor
    func paragraphUsesUnifiedCustomColorWithOptInCapabilities() throws {
        _ = PartPackageCatalog.shared
        let properties = PartType.paragraph.definition.properties
        let color = try #require(properties.first(where: { $0.key.rawValue == "textColor" }))
        let alignment = try #require(properties.first(where: { $0.key.rawValue == "textAlignment" }))
        #expect(!properties.contains { ["textSize", "typeface"].contains($0.key.rawValue) })
        let textDecoration = try #require(properties.first(where: { $0.key.rawValue == "textDecoration" }))

        #expect(color.defaultValue == .packageColor(.init(
            source: FrameworkColorRole.text.rawValue,
            customColor: "#000000",
            opacity: 1
        )))
        if case .packageColor(let frameworkValues, let opacity, _, _) = color.control {
            #expect(frameworkValues)
            #expect(opacity)
        } else {
            Issue.record("Paragraph should use the package colour control")
        }
        #expect(!properties.contains { $0.key.rawValue.hasPrefix("textColor") && $0.key != color.key })
        #expect(alignment.defaultValue == .choice("start"))
        #expect(alignment.isResponsive)
        if case .textAlignment = alignment.control {} else {
            Issue.record("Paragraph should use the specialised text-alignment control")
        }
        #expect(textDecoration.defaultValue == .choice("none"))
        #expect(textDecoration.isResponsive)
        if case .choice(let choices) = textDecoration.control {
            #expect(choices.map(\.value) == ["none", "underline", "overline", "line-through"])
        } else {
            Issue.record("Paragraph should use a select control for text decoration")
        }
        #expect(
            PartType.paragraph.definition.package?.css.contains(
                "text-align: {{ control.textAlignment }}"
            ) == true
        )
        let sizeEnabled = try #require(properties.first(where: { $0.key.rawValue == "sizeEnabled" }))
        #expect(sizeEnabled.defaultValue == .boolean(false))
        let fontSize = try #require(properties.first(where: { $0.key.rawValue == "fontSize" }))
        #expect(fontSize.defaultValue == .choice("base"))
        #expect(fontSize.isResponsive)
        #expect(
            PartType.paragraph.definition.package?.css.contains(
                "line-height: {{ control.fontSize.lineHeight }}"
            ) == true
        )
        #expect(
            PartType.paragraph.definition.package?.css.contains(
                "text-decoration-line: {{ control.textDecoration }}"
            ) == true
        )

        var paragraph = PartNode.make(.paragraph)
        var site = Site(name: "Line height", pages: [Page(title: "Home", slug: "index", parts: [paragraph])])



        paragraph.setProperty(.init(rawValue: "textDecoration"), value: .choice("underline"))
        site.pages[0].parts = [paragraph]
        let underlinedHTML = HTMLPageRenderer(site: site).render(page: site.pages[0], framework: site.framework)
        #expect(underlinedHTML.contains("text-decoration-line: underline"))
    }

    @Test @MainActor
    func headingUsesSemanticLevelAndFrameworkTypography() throws {
        _ = PartPackageCatalog.shared
        let definition = PartType.heading.definition
        let properties = definition.properties
        let level = try #require(properties.first { $0.key.rawValue == "headingLevel" })
        let font = try #require(properties.first { $0.key.rawValue == "font" })
        let color = try #require(properties.first { $0.key.rawValue == "textColor" })
        let decoration = try #require(properties.first { $0.key.rawValue == "textDecoration" })
        let sizeEnabled = try #require(properties.first { $0.key.rawValue == "sizeEnabled" })
        let fontSize = try #require(properties.first { $0.key.rawValue == "fontSize" })

        #expect(level.defaultValue == .choice("2"))
        #expect(level.isResponsive == false)
        if case .choice(let choices) = level.control {
            #expect(choices.map(\.value) == ["1", "2", "3", "4", "5", "6"])
        } else {
            Issue.record("Heading level should use a select control")
        }
        guard case .frameworkFont = font.control else {
            Issue.record("Heading should use the framework font control")
            return
        }
        let heading = PartNode.make(.heading)
        #expect(heading.propertyValue(.init(rawValue: "font")).stringValue == "heading")
        #expect(heading.propertyValue(.init(rawValue: "font.weight")) == .number(700))
        #expect(heading.propertyValue(.init(rawValue: "font.style")).stringValue == "normal")
        #expect(color.defaultValue == .packageColor(.init(
            source: FrameworkColorRole.text.rawValue,
            customColor: "#000000",
            opacity: 1
        )))
        #expect(decoration.defaultValue == .choice("none"))
        #expect(decoration.isResponsive)
        #expect(sizeEnabled.defaultValue == .boolean(false))
        #expect(fontSize.defaultValue == .choice("2xl"))
        #expect(fontSize.isResponsive)
        #expect(definition.package?.css.contains("font-family: {{ control.font.family }}") == true)
        #expect(definition.package?.css.contains("font-weight: {{ control.font.weight }}") == true)
        #expect(definition.package?.css.contains("font-style: {{ control.font.style }}") == true)
        #expect(definition.package?.css.contains("text-decoration-line: {{ control.textDecoration }}") == true)
        #expect(definition.package?.css.contains("{{ if control.sizeEnabled }}") == true)
    }

    @Test
    func packDiscoveryTreatsAnOuterPackAsAContentBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePackHeader(identifier: "com.example.root", at: root)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root.standardizedFileURL])
        #expect(try FoundryPackLoader.load(from: root).identifier == "com.example.root")
    }

    @Test
    func packLoaderDiscoversTypedPlainDirectoriesAndRejectsUnknownTopLevelContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(identifier: "com.example.typed", at: root)
        let part = root.appending(path: "Parts/com.example.card", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: part.appending(path: "Resources", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data(validManifest.utf8).write(to: part.appending(path: "manifest.json"))

        let pack = try FoundryPackLoader.load(from: root)
        #expect(pack.partURLs == [part.standardizedFileURL])
        #expect(pack.templateURLs.isEmpty)
        #expect(pack.frameworkURLs.isEmpty)
        #expect(pack.invalidItemPaths.isEmpty)

        // Hidden files must not reject a pack: development packs live in git
        // checkouts alongside .git and .gitignore.
        try Data("Resources/".utf8).write(to: root.appending(path: ".gitignore"))
        #expect(try FoundryPackLoader.load(from: root).partURLs == [part.standardizedFileURL])

        // Pack-wide files belong in the root Resources directory — the home
        // of the personal pack's template organization file.
        let sharedResources = root.appending(path: "Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sharedResources, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: sharedResources.appending(path: "library.json"))
        let withSharedResources = try FoundryPackLoader.load(from: root)
        #expect(withSharedResources.partURLs == [part.standardizedFileURL])
        #expect(withSharedResources.invalidItemPaths.isEmpty)

        // An incomplete item (a part folder mid-creation) is skipped and
        // reported without hiding the pack's remaining valid items.
        try FileManager.default.createDirectory(
            at: root.appending(path: "Parts/com.example.incomplete", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let degraded = try FoundryPackLoader.load(from: root)
        #expect(degraded.partURLs == [part.standardizedFileURL])
        #expect(degraded.invalidItemPaths == ["Parts/com.example.incomplete"])

        try FileManager.default.createDirectory(
            at: root.appending(path: "Components", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func packLoaderDiscoversAssetCollectionsAsPlainFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(identifier: "com.example.assets", at: root)

        // A collection with a licence manifest: files live at the folder
        // root, the manifest never lists as a file, hidden files never ship.
        let item = root.appending(path: "Assets/stock-photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: item.appending(path: "badges", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data("jpeg".utf8).write(to: item.appending(path: "hero.jpg"))
        try Data("svg".utf8).write(to: item.appending(path: "badges/badge.svg"))
        try Data("hidden".utf8).write(to: item.appending(path: ".DS_Store"))
        let manifest: [String: Any] = [
            "id": "com.example.assets.stock-photos",
            "title": "Stock Photos",
            "license": "CC0 1.0",
            "licenseURL": "https://example.com/license",
            "attribution": "Photos by Example"
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: item.appending(path: "manifest.json"))

        let pack = try FoundryPackLoader.load(from: root)
        #expect(pack.assetCollectionURLs.count == 1)
        let collection = try AssetCollectionStore.load(from: pack.assetCollectionURLs[0])
        #expect(collection.identifier == "com.example.assets.stock-photos")
        #expect(collection.title == "Stock Photos")
        #expect(collection.license == "CC0 1.0")
        #expect(collection.licenseURL == URL(string: "https://example.com/license"))
        #expect(collection.attribution == "Photos by Example")
        #expect(collection.files.map(\.filename) == ["badge.svg", "hero.jpg"])
        #expect(collection.files.map(\.mediaType) == ["image/svg+xml", "image/jpeg"])

        // A hand-authored folder with no manifest is a complete collection:
        // titled by its name, identified by its path.
        let plain = root.appending(path: "Assets/textures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: plain.appending(path: "wood.png"))
        let reloaded = try FoundryPackLoader.load(from: root)
        #expect(reloaded.assetCollectionURLs.count == 2)
        #expect(reloaded.invalidItemPaths.isEmpty)
        let handAuthored = try AssetCollectionStore.load(from: plain)
        #expect(handAuthored.title == "textures")
        #expect(handAuthored.manifestID == nil)
        #expect(handAuthored.identifier == plain.standardizedFileURL.path)
        #expect(handAuthored.files.map(\.filename) == ["wood.png"])

        // A manifest without an id is fine — it exists just for the licence
        // or title; a malformed manifest still fails the collection.
        try JSONSerialization.data(withJSONObject: ["license": "CC0"])
            .write(to: plain.appending(path: "manifest.json"))
        #expect(AssetCollectionStore.entry(at: plain)?.license == "CC0")
        let broken = root.appending(path: "Assets/broken", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appending(path: "manifest.json"))
        #expect(AssetCollectionStore.entry(at: broken) == nil)
        #expect(throws: Error.self) { try AssetCollectionStore.load(from: broken) }

        // Loose files directly under Assets are flagged, not silently hidden.
        try Data("png".utf8).write(to: root.appending(path: "Assets/loose.png"))
        #expect(try FoundryPackLoader.load(from: root).invalidItemPaths == ["Assets/loose.png"])
    }

    @Test
    func developmentPacksUseTheSameOuterPackLoader() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(identifier: "com.example.development", at: root)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root.standardizedFileURL])
        #expect(try FoundryPackLoader.load(from: root).identifier == "com.example.development")
    }

    @Test
    func loadedPartsKnowWhenTheyBelongToADevelopmentPack() throws {
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<section {{ part.attributes }}>Development{{ childArea(\"content\") }}</section>",
            pathExtension: "foundrydevpack"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)

        #expect(package.isDevelopmentPack)
    }

    @Test
    func packIdentityUsesOnlyThePublicIDKey() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let contents = root.appending(path: "Contents", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let legacyManifest: [String: Any] = ["CFBundleIdentifier": "com.example.legacy"]
        let data = try JSONSerialization.data(withJSONObject: legacyManifest)
        try data.write(to: contents.appending(path: "manifest.json"))

        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func manifestSchemaRejectsUnknownKeysUnsupportedAPIsAndInvalidVersions() throws {
        let cases: [(manifest: String, expected: String)] = [
            (
                validManifest.replacingOccurrences(
                    of: "\"title\" : \"Card\"",
                    with: "\"titel\" : \"Typo\", \"title\" : \"Card\""
                ),
                "Unknown key 'titel'"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "\"minimumAPIVersion\" : 1",
                    with: "\"minimumAPIVersion\" : 999"
                ),
                "requires Foundry part API 999"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "\"version\" : \"1.0.0\"",
                    with: "\"version\" : \"1.0\""
                ),
                "MAJOR.MINOR.PATCH"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "\"version\" : \"1.0.0\"",
                    with: "\"version\" : \"1.0.0-01\""
                ),
                "MAJOR.MINOR.PATCH"
            )
        ]

        for testCase in cases {
            let packageURL = try makePackage(
                manifest: testCase.manifest,
                template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
            )
            defer { try? FileManager.default.removeItem(at: packageURL) }
            do {
                _ = try PartPackageLoader.load(from: packageURL)
                Issue.record("The invalid manifest unexpectedly loaded.")
            } catch {
                #expect(error.localizedDescription.contains(testCase.expected))
            }
        }
    }

    @Test
    func packManifestSupportsOptionalUpdateMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(identifier: "com.example.collection", at: root)
        #expect(try FoundryPackLoader.load(from: root).identifier == "com.example.collection")

        let updateEnabled: [String: Any] = [
            "minimumAPIVersion": 1,
            "id": "com.example.collection",
            "title": "Collection",
            "author": "Example Developer",
            "version": "1.2.3",
            "updates": [
                "appcastURL": "https://example.com/appcast.json",
                "publicKey": Data(repeating: 1, count: 32).base64EncodedString()
            ]
        ]
        let updateData = try JSONSerialization.data(withJSONObject: updateEnabled)
        try updateData.write(to: root.appending(path: "manifest.json"))
        let updatePack = try FoundryPackLoader.load(from: root)
        #expect(updatePack.identifier == "com.example.collection")
        #expect(updatePack.metadata.version == "1.2.3")
        #expect(updatePack.metadata.updates?.appcastURL.absoluteString == "https://example.com/appcast.json")

        let invalid: [String: Any] = ["unexpected": "value"]
        let data = try JSONSerialization.data(withJSONObject: invalid)
        try data.write(to: root.appending(path: "manifest.json"))
        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func appcastSelectsNewestCompatibleSemanticRelease() throws {
        let releases = [
            FoundryPackAppcast.Release(
                version: "1.1.0",
                publishedAt: Date(),
                minimumAPIVersion: 1,
                downloadURL: URL(string: "https://example.com/1.1.zip")!,
                releaseNotesURL: nil,
                fileSize: 1,
                sha256: "00",
                signature: "signature"
            ),
            FoundryPackAppcast.Release(
                version: "2.0.0",
                publishedAt: Date(),
                minimumAPIVersion: 2,
                downloadURL: URL(string: "https://example.com/2.0.zip")!,
                releaseNotesURL: nil,
                fileSize: 1,
                sha256: "00",
                signature: "signature"
            )
        ]
        let appcast = FoundryPackAppcast(formatVersion: 1, packID: "com.example.pack", releases: releases)
        let release = try FoundryPackUpdateVerifier.newestRelease(
            in: appcast,
            packID: "com.example.pack",
            currentVersion: "1.0.0"
        )
        #expect(release.version == "1.1.0")
    }

    @Test
    func updateVerifierRejectsTampering() throws {
        let data = Data("release archive".utf8)
        let key = Curve25519.Signing.PrivateKey()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let release = FoundryPackAppcast.Release(
            version: "1.1.0",
            publishedAt: Date(),
            minimumAPIVersion: 1,
            downloadURL: URL(string: "https://example.com/release.zip")!,
            releaseNotesURL: nil,
            fileSize: Int64(data.count),
            sha256: digest,
            signature: try key.signature(for: data).base64EncodedString()
        )
        try FoundryPackUpdateVerifier.verify(
            data,
            release: release,
            publicKey: key.publicKey.rawRepresentation.base64EncodedString()
        )
        #expect(throws: FoundryPackUpdateError.self) {
            try FoundryPackUpdateVerifier.verify(
                Data("tampered archive".utf8),
                release: release,
                publicKey: key.publicKey.rawRepresentation.base64EncodedString()
            )
        }
    }

    @Test
    func declaredBuiltInIconLibraryIsInjectedOnlyWhenRequested() throws {
        let identifier = "com.example.icons\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "\"templates\"",
                with: """
                "libraries" : [{
                    "id" : "bootstrapIcons",
                    "majorVersion" : 1
                }],
                "templates"
                """
            )
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ part.attributes }}><i class=\"bi bi-alarm\"></i>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        let site = Site(
            name: "Icons",
            pages: [Page(title: "Home", slug: "index", parts: [
                PartNode(type: PartType(rawValue: identifier))
            ])]
        )
        let bundle = StaticSiteRenderer().render(site: site)

        #expect(bundle.file(at: "files/site.css")?.contents.contains("bootstrap-icons") == true)
        #expect(bundle.file(at: "files/libraries/bootstrapIcons/bootstrap-icons.woff2") != nil)
    }

    @Test
    func iconControlUsesTheBuiltInIconCatalogue() throws {
        let item = """
        {
            "id" : "symbol",
            "label" : "Icon",
            "type" : "icon",
            "defaults" : {"base" : "stars"},
            "responsive" : false
        }
        """
        let manifest = manifest(withInspectorEntries: item)
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<span {{ part.attributes }}><i class=\"bi bi-{{ control.symbol }}\"></i>{{ childArea(\"content\") }}</span>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(
            PartPackageAdapter.definition(from: package).properties.first {
                $0.key.rawValue == "symbol"
            }
        )

        if case .icon = property.control {} else { Issue.record("Expected an icon control") }
        #expect(property.defaultValue == .choice("stars"))
        #expect(FoundryWebLibraryRegistry.icons.count > 2_000)
        #expect(FoundryWebLibraryRegistry.icon(named: "stars")?.cssClass == "bi-stars")
        #expect(FoundryWebLibraryRegistry.icon(named: "bi-stars")?.name == "stars")
        #expect(FoundryWebLibraryRegistry.uniqueRequirements(in: [package, package]) == [
            FoundryWebLibraryRegistry.iconRequirement
        ])
    }

    @Test
    func revealControlGroupIncludesGSAPAndScrollTrigger() throws {
        let identifier = "com.example.reveal-library.\(UUID().uuidString.lowercased())"
        let manifest = """
        {
        "minimumAPIVersion" : 1,
        "id" : "\(identifier)",
        "title" : "Reveal Library",
        "version" : "1.0.0",
        "libraries" : [{
            "id" : "alpine",
            "majorVersion" : 3
        }],
        "inspector" : [{"type" : "reveal", "id": "reveal"}],
        "templates" : {"html" : "part.html"}
        }
        """
        let packageURL = try makePackage(
            manifest: manifest,
            template: "<section {{ part.attributes }}>Reveal</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        PartRegistry.register(package)

        #expect(FoundryWebLibraryRegistry.uniqueRequirements(in: [package]) == [
            FoundryWebLibraryRegistry.alpineRequirement,
            FoundryWebLibraryRegistry.gsapRequirement,
            FoundryWebLibraryRegistry.gsapScrollTriggerRequirement
        ])
        let directLibraryPaths = FoundryWebLibraryRegistry.exportFiles(for: [package]).map(\.path)
        #expect(directLibraryPaths.contains("files/libraries/alpine/alpine.min.js"))
        #expect(directLibraryPaths.contains("files/libraries/gsap/gsap.min.js"))
        #expect(directLibraryPaths.contains("files/libraries/gsapScrollTrigger/ScrollTrigger.min.js"))

        let site = Site(
            name: "Reveal",
            pages: [Page(title: "Home", slug: "index", parts: [
                PartNode(type: PartType(rawValue: identifier))
            ])]
        )
        let bundle = StaticSiteRenderer().render(site: site)
        #expect(bundle.errors.isEmpty)
        let document = try #require(bundle.file(at: "index.html")?.contents)
        let pageJavaScript = try #require(bundle.file(at: "files/page.js")?.contents)

        #expect(document.contains("files/libraries/gsap/gsap.min.js"))
        #expect(document.contains("files/libraries/gsapScrollTrigger/ScrollTrigger.min.js"))
        #expect(document.contains("files/libraries/alpine/alpine.min.js"))
        #expect(bundle.file(at: "files/libraries/gsap/gsap.min.js") != nil)
        #expect(bundle.file(at: "files/libraries/gsapScrollTrigger/ScrollTrigger.min.js") != nil)
        #expect(bundle.file(at: "files/libraries/alpine/alpine.min.js") != nil)
        #expect(pageJavaScript.contains("prefers-reduced-motion: reduce"))
        #expect(pageJavaScript.contains("gsap.registerPlugin(ScrollTrigger)"))
    }

    @Test
    func webLibrariesSupportAlpineGLightboxAndResolveScrollTriggerDependency() {
        #expect(FoundryWebLibraryRegistry.supports(FoundryWebLibraryRegistry.alpineRequirement))
        #expect(FoundryWebLibraryRegistry.supports(FoundryWebLibraryRegistry.gsapRequirement))
        #expect(FoundryWebLibraryRegistry.supports(FoundryWebLibraryRegistry.glightboxRequirement))
        #expect(FoundryWebLibraryRegistry.supports(FoundryWebLibraryRegistry.gsapScrollTriggerRequirement))
    }

    @Test
    func iconControlAutomaticallyIncludesItsLibraryAndRequiresAValidDefault() throws {
        let item = """
        {
            "id" : "symbol",
            "label" : "Icon",
            "type" : "icon",
            "defaults" : {"base" : "not-a-real-foundry-icon"},
            "responsive" : false
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains {
            $0.message == "An icon default must be a valid Foundry icon name, for example stars."
        })
    }

    @Test
    func iconControlValidatesEveryMultiControlDefault() throws {
        let item = """
        {
            "type" : "icon",
            "id" : "icons",
            "label" : "Icons",
            "count" : 2,
            "subtitle" : ["Previous", "Next"],
            "defaults" : {"base" : ["arrow-left", "not-a-real-foundry-icon"]}
        }
        """
        let manifestText = manifest(withInspectorEntries: item)
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let property = try #require(manifest.resolvedProperties.first)
        #expect(property.defaultValue == .array([.string("arrow-left"), .string("not-a-real-foundry-icon")]))

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )
        #expect(diagnostics.contains {
            $0.location.hasSuffix("icons.default[1]")
                && $0.message == "An icon default must be a valid Foundry icon name, for example stars."
        })
    }

    @Test
    func developmentPackWatcherObservesNestedFileChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let file = resources.appending(path: "part.css")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("initial".utf8).write(to: file)

        await confirmation("Nested dev-pack change is observed") { changed in
            let watcher = FoundryDevelopmentPackWatcher(rootURL: root) { changed() }
            try? await Task.sleep(for: .milliseconds(250))
            try? Data("updated".utf8).write(to: file)
            try? await Task.sleep(for: .milliseconds(700))
            withExtendedLifetime(watcher) {}
        }
    }

    @Test
    func developmentPackWatcherTreatsNestedDistributionPacksAsOpaque() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
        let sourceFile = resources.appending(path: "part.css")
        let childPack = resources.appending(path: "Child.foundrypack", directoryHint: .isDirectory)
        let childFile = childPack.appending(path: "Resources/child.css")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: childFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: sourceFile)
        try Data().write(to: childFile)

        let watched = Set(FoundryDevelopmentPackWatcher.watchedURLs(in: root).map(\.standardizedFileURL))

        #expect(watched.contains(sourceFile.standardizedFileURL))
        #expect(!watched.contains(childPack.standardizedFileURL))
        #expect(!watched.contains(childFile.standardizedFileURL))
    }

    private var validManifest: String {
        """
        {
            "minimumAPIVersion" : 1,
            "id" : "com.example.card",
            "title" : "Card",
            "version" : "1.0.0",
            "description" : "A test card.",
            "group" : "Content part",
            \(defaultCustomItemsDeclaration),
            "templates" : {
                "html" : "part.html",
                \(instanceCSSDeclaration)
            },
            "assets" : [{"path" : "images/icon.svg"}]
        }
        """
    }

    private var defaultCustomItemsDeclaration: String {
        """
        "inspector" : [
            {
                "section" : "Content",
                "controls" : [
                    {
                        "id" : "title",
                        "label" : "Title",
                        "type" : "text",
                        "defaults" : {"base" : "Hello"},
                        "responsive" : false
                    }
                ]
            },
            {
                "type" : "childPicker",
                "id" : "content",
                "label" : "Content",
                "pickerItems" : ["com.example.child"],
                "accepts" : ["*"]
            }
        ]
        """
    }

    @Test
    func manifestDecodeFailureNamesTheFailingSpot() throws {
        let item = """
        {
            "id" : "cardShadow",
            "label" : "Shadow",
            "type" : "shadow",
            "defaults" : {"base" : "md"},
            "responsive" : false
        }
        """
        let data = Data(manifest(withInspectorEntries: item).utf8)
        let error = #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PartPackageManifest.self, from: data)
        }
        let message = PartPackageLoadingError
            .unreadableManifest(try #require(error))
            .errorDescription ?? ""
        // A renamed control type must be identifiable from the error alone:
        // the invalid value and the manifest location, not "isn't in the correct format".
        #expect(message.contains("shadow"), Comment(rawValue: message))
        #expect(message.contains("inspector[0]"), Comment(rawValue: message))
    }

    @Test
    func inspectorGroupIconsResolveFromSectionWrappersAndGroupedControls() throws {
        let controls = """
        {
            "section" : "Gallery",
            "systemImage" : "photo.stack",
            "controls" : [
                {
                    "id" : "galleryStyle",
                    "label" : "Style",
                    "type" : "toggle",
                    "defaults" : {"base" : true},
                    "responsive" : false
                },
                {"type" : "spacing", "id": "spacing"}
            ]
        },
        {"section" : "Content", "systemImage" : "doc.text"},
        {"type" : "reveal", "id": "reveal"}
        """
        let valid = Data(manifest(withInspectorEntries: controls).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: valid).isEmpty)
        let decoded = try JSONDecoder().decode(PartPackageManifest.self, from: valid)
        #expect(decoded.controlSections.map(\.name) == ["Gallery", "Content"])
        #expect(decoded.controlGroups.map(\.type) == [.spacing, .reveal])
        #expect(decoded.resolvedProperties.first { $0.id == "galleryStyle" }?.group == "Gallery")
        // A grouped control inside a section belongs to that section…
        #expect(decoded.resolvedProperties.first { $0.id == "spacing.frameworkPadding" }?.group == "Gallery")
        // …and a bare one lands in Settings like any other loose control.
        #expect(decoded.resolvedProperties.first { $0.id == "reveal.revealEnabled" }?.group == "Settings")
        #expect(decoded.resolvedGroupIcons["Gallery"] == "photo.stack")
        // An icon-only wrapper gives the implicit Content section its icon.
        #expect(decoded.resolvedGroupIcons["Content"] == "doc.text")
        // Sectioning is entirely the developer's: grouped controls provide no
        // automatic section or icon anywhere.
        #expect(decoded.resolvedGroupIcons["Spacing"] == nil)
        #expect(decoded.resolvedGroupIcons["Reveal"] == nil)
        // Undeclared sections fall back at presentation time, not in the manifest.
        #expect(decoded.resolvedGroupIcons["Settings"] == nil)
        // Sections round-trip as wrappers: no per-control section keys survive encoding.
        let encoded = JSONEncoder()
        let reencoded = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: encoded.encode(decoded)
        )
        #expect(reencoded.controlSections == decoded.controlSections)
        #expect(reencoded.resolvedGroupIcons == decoded.resolvedGroupIcons)
        #expect(!String(decoding: try encoded.encode(decoded.resolvedProperties), as: UTF8.self).contains("\"section\""))

        let failures: [(entries: String, message: String)] = [
            ("{\"systemImage\" : \"star\"}",
             "An inspector entry without a type is a section and requires a non-empty section name."),
            ("{\"section\" : \" \"}",
             "An inspector entry without a type is a section and requires a non-empty section name."),
            ("{\"section\" : \"Gallery\"}, {\"section\" : \"Gallery\"}",
             "Duplicate section 'Gallery'. Declare each section once and list its controls inside it."),
            ("{\"section\" : \"Gallery\", \"icon\" : \"star\"}",
             "Unknown key 'icon'. Check the spelling or remove it."),
            ("{\"section\" : \"Gallery\", \"controls\" : [{\"type\" : \"advanced\"}]}",
             "The advanced group is Foundry's own Advanced section — declare it at the top level of the inspector."),
            ("{\"type\" : \"spacing\", \"id\": \"spacing\"}, {\"section\" : \"Gallery\", \"controls\" : [{\"type\" : \"spacing\", \"id\": \"spacing\"}]}",
             "Control group 'spacing' is declared more than once."),
            ("{\"section\" : \"Gallery\", \"controls\" : [{\"section\" : \"Inner\"}]}",
             "Sections cannot nest inside sections; every entry here must be a control with a type.")
        ]
        for failure in failures {
            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withInspectorEntries: failure.entries).utf8)
            )
            #expect(diagnostics.contains { $0.message == failure.message }, Comment(rawValue: failure.message))
        }

        // Controls inside a wrapper receive the normal control validation at
        // their nested location.
        let invalidInner = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: """
            {"section" : "Gallery", "controls" : [{"id" : "broken", "type" : "mystery"}]}
            """).utf8)
        )
        #expect(invalidInner.contains {
            $0.location == "manifest.json:inspector[0].controls[0]:type"
                && $0.message == "Unknown control type 'mystery'."
        })

        // Section wrappers are the only home for section names: a control
        // carrying its own group key fails as an unknown key.
        let strayGroup = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withInspectorEntries: """
            {"id" : "styled", "type" : "text", "group" : "Gallery", "defaults" : {"base" : ""}}
            """).utf8)
        )
        #expect(strayGroup.contains { $0.message == "Unknown key 'group'. Check the spelling or remove it." })

        // The removed top-level groups array is an unknown manifest key.
        let legacyGroups = manifest(withInspectorEntries: controls).replacingOccurrences(
            of: "\"minimumAPIVersion\"",
            with: "\"groups\" : [{\"name\" : \"Gallery\", \"systemImage\" : \"photo.stack\"}],\n    \"minimumAPIVersion\""
        )
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(legacyGroups.utf8)).contains {
            $0.location == "manifest.json:groups" && $0.message.contains("Unknown key 'groups'")
        })
    }

    private func manifest(withInspectorEntries items: String) -> String {
        let replacement = """
        "inspector" : [
            \(items.isEmpty ? "" : items + ",")
            {
                "type" : "childPicker",
                "id" : "content",
                "label" : "Content",
                "pickerItems" : ["com.example.child"],
                "accepts" : ["*"]
            }
        ]
        """
        return validManifest.replacingOccurrences(of: defaultCustomItemsDeclaration, with: replacement)
    }

    private var instanceCSSDeclaration: String {
        """
        "files" : [
            {
                "path" : "part.css",
                "scope" : "instance"
            }
        ]
        """
    }

    @Test
    func partIconCannotExceedMaximumFileSize() throws {
        let iconManifest = validManifest.replacingOccurrences(
            of: "\"title\" : \"Card\",",
            with: "\"title\" : \"Card\",\n    \"icon\" : {\"file\" : \"icon.svg\", \"tint\" : \"blue\"},"
        )
        let oversizedIcon = "<svg>" + String(
            repeating: " ",
            count: PartPackageValidator.maximumIconByteCount
        ) + "</svg>"
        let packageURL = try makePackage(
            manifest: iconManifest,
            template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>",
            additionalFiles: ["icon.svg": oversizedIcon]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try JSONDecoder().decode(
            PartPackageManifest.self,
            from: Data(iconManifest.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains { $0.location == "icon.svg" && $0.message.contains("64 KiB") })
    }

    /// Icons render as template images: any solid colour works, and only
    /// artwork that changes the alpha — and so the shape — earns a warning.
    @Test(arguments: [
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="#000000"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="#F00"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="red"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="currentColor"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><path d="M1 1h22" fill="none" stroke="#123456"/></svg>"##,
        ##"<svg viewBox="0 0 24 24"><rect width="24" height="24" style="fill: blue"/></svg>"##
    ])
    func solidIconFillsInAnyColourPassWithoutWarning(_ source: String) {
        #expect(!PartPackageValidator.iconArtworkAltersShape(source), "\(source)")
    }

    @Test(arguments: [
        ##"<svg><linearGradient id="g"/><rect fill="url(#g)"/></svg>"##,
        ##"<svg><radialGradient id="g"/></svg>"##,
        ##"<svg><image href="photo.png"/></svg>"##,
        ##"<svg><pattern id="p"/></svg>"##,
        ##"<svg><filter id="f"/></svg>"##,
        ##"<svg><rect fill-opacity="0.5"/></svg>"##,
        ##"<svg><rect opacity="0.5"/></svg>"##,
        ##"<svg><rect style="stroke-opacity: 0.4"/></svg>"##,
        ##"<svg><rect fill="rgba(0,0,0,0.5)"/></svg>"##,
        ##"<svg><rect fill="#00000080"/></svg>"##,
        ##"<svg><rect fill="#0008"/></svg>"##
    ])
    func iconArtworkThatChangesTheShapeWarns(_ source: String) {
        #expect(PartPackageValidator.iconArtworkAltersShape(source), "\(source)")
    }

    @Test
    func iconTintShadesAndRenderingsResolveWithQuietFallbacks() {
        let light = PartPackageIcon(file: "icon.svg", tint: "blue.light", rendering: "original")
        #expect(light.resolvedTint == .blue)
        #expect(light.resolvedShade == .light)
        #expect(light.resolvedRendering == .original)
        #expect(PartPackageIcon(tint: "indigo.dark").resolvedShade == .dark)
        #expect(PartPackageIcon(tint: "indigo").resolvedShade == .regular)
        // Unknown names fall back rather than failing.
        let unknown = PartPackageIcon(tint: "chartreuse.misty", rendering: "sparkly")
        #expect(unknown.resolvedTint == .gray)
        #expect(unknown.resolvedShade == .regular)
        #expect(unknown.resolvedRendering == .monochrome)
        #expect(PartPackageIcon(tint: "red.misty").resolvedTint == .red)
    }

    @Test
    func iconRenderingKeysValidateWithoutErrors() throws {
        let item = #"{"type":"text","id":"note","defaults":{"base":""}}"#
        var manifestObject = try #require(JSONSerialization.jsonObject(with: Data(manifest(withInspectorEntries: item).utf8)) as? [String: Any])
        manifestObject["icon"] = ["symbol": "star", "tint": "purple.light", "rendering": "original"]
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: JSONSerialization.data(withJSONObject: manifestObject))
        #expect(diagnostics.filter { $0.location.contains("icon") }.isEmpty)
        manifestObject["icon"] = ["symbol": "star", "tint": "nope", "rendering": "nope"]
        let unknown = try PartPackageManifestSchema.diagnostics(for: JSONSerialization.data(withJSONObject: manifestObject))
        #expect(unknown.filter { $0.location.contains("icon") }.isEmpty)
    }

    @Test
    func decodedPartIconIsSynchronouslyReusable() async throws {
        let iconURL = FileManager.default.temporaryDirectory
            .appending(path: "Foundry-Icon-Cache-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: iconURL) }
        try Data(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><rect width=\"24\" height=\"24\"/></svg>".utf8
        ).write(to: iconURL)

        #expect(PartIconLoader.cachedIcon(at: iconURL) == nil)
        let loaded = await PartIconLoader.shared.icon(at: iconURL)
        #expect(loaded != nil)
        #expect(PartIconLoader.cachedIcon(at: iconURL) != nil)

        await PartIconLoader.shared.removeIcon(at: iconURL)
        #expect(PartIconLoader.cachedIcon(at: iconURL) == nil)
    }

    private func makePackage(
        manifest: String,
        template: String,
        additionalFiles: [String: String] = [:],
        pathExtension: String = "foundrypack"
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(pathExtension)", directoryHint: .isDirectory)
        let resourcesURL = rootURL.appending(path: "Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: resourcesURL.appending(path: "images", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let compatibleTemplate = template.contains("{{ part.attributes }}") &&
            !template.contains("{{ part.class }}")
            ? template.replacingOccurrences(
                of: "{{ part.attributes }}",
                with: "class=\"{{ part.class }}\" {{ part.attributes }}"
            )
            : template
        let files = [
            "part.html": compatibleTemplate,
            "part.css": ":host { display: block; }",
            "icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
            "icon-dark.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
            "images/icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        ].merging(additionalFiles) { _, additional in additional }
        try Data(manifest.utf8).write(to: rootURL.appending(path: "manifest.json"))
        for (path, contents) in files {
            let fileURL = resourcesURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL)
        }
        return rootURL
    }

    private func writePackHeader(
        identifier: String = "com.example.part",
        at rootURL: URL
    ) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "id": identifier,
            "minimumAPIVersion": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: rootURL.appending(path: "manifest.json"))
    }
}
