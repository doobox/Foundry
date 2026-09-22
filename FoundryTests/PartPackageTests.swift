import Foundation
import CryptoKit
import Testing
@testable import Foundry

struct PartPackageTests {
    private static var developerDocsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Foundry Developer API", directoryHint: .isDirectory)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "AGENTS.md").path)))
    @MainActor func developerDocumentationQuickExamplesLoad() throws {
        // Read the current sibling working tree, not copied or stale fixtures.
        let pages = try FileManager.default.contentsOfDirectory(at: Self.developerDocsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let expression = try NSRegularExpression(pattern: #"(?s)## Quick example\s+.*?```xml\s*\n(.*?)```"#)
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
                manifest: manifest(withControls: controls),
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
        #expect(checked == 37, "Expected every documented control and control group's Quick example; update this count when adding a reference page.")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: developerDocsURL.appending(path: "AGENTS.md").path)))
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
            let xml = try #require(snippets["xml"], "Missing declaration in \(page.lastPathComponent)")
            // Older complete examples show the controls key and array; newer ones show a single item.
            let controls: String
            if xml.contains("<key>controls</key>") {
                let start = try #require(xml.range(of: "<array>"))
                let end = try #require(xml.range(of: "</array>", options: .backwards))
                controls = String(xml[start.upperBound..<end.lowerBound])
            } else {
                controls = xml
            }
            var exampleManifest = try #require(PropertyListSerialization.propertyList(
                from: Data(manifest(withControls: controls).utf8), format: nil
            ) as? [String: Any])
            var declarations = try #require(exampleManifest["controls"] as? [[String: Any]])
            declarations.removeLast() // Remove the test helper's unrelated content childPicker.
            exampleManifest["controls"] = declarations
            let manifestData = try PropertyListSerialization.data(fromPropertyList: exampleManifest, format: .xml, options: 0)
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
        #expect(checked == 26, "Expected all 26 control reference examples.")
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
            let base = try snippet("starter:Info.plist")
            var manifest = try #require(PropertyListSerialization.propertyList(from: Data(base.utf8), format: nil) as? [String: Any])
            if stage == "complete" {
                let fragment = try snippet("complete:controls")
                let additions = try #require(PropertyListSerialization.propertyList(
                    from: Data("<plist version=\"1.0\"><dict>\(fragment)</dict></plist>".utf8), format: nil
                ) as? [String: Any])
                manifest["controls"] = additions["controls"]
            }
            let encoded = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
            let packageURL = try makePackage(
                manifest: String(decoding: encoded, as: UTF8.self), template: snippet("\(stage):part.html"),
                additionalFiles: ["part.css": snippet("\(stage):part.css"), "icon.svg": snippet("starter:icon.svg")]
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
        <dict><key>type</key><string>number</string><key>id</key><string>pair</string><key>count</key><integer>2</integer><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><array><integer>1</integer><integer>2</integer></array><key>large</key><array><integer>3</integer><integer>4</integer></array></dict></dict>
        <dict><key>type</key><string>frameworkBorder</string><key>id</key><string>border</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><dict><key>width</key><string>none</string></dict><key>large</key><dict><key>width</key><string>sm</string><key>style</key><string>dashed</string></dict></dict></dict>
        <dict><key>type</key><string>frameworkFont</string><key>id</key><string>font</string><key>showsWeight</key><true/><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><dict><key>family</key><string>body</string><key>weight</key><integer>400</integer></dict><key>large</key><dict><key>family</key><string>heading</string><key>weight</key><integer>700</integer></dict></dict></dict>
        <dict><key>type</key><string>frameworkColor</string><key>id</key><string>colour</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>accent</string></dict><key>large</key><dict><key>palette</key><string>standard.lime</string><key>lightShade</key><integer>8</integer><key>darkShade</key><integer>3</integer></dict></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        let created = PartNode.make(.init(rawValue: package.manifest.identifier))
        #expect(created.responsiveDefaults?.isEmpty == false)
        #expect(created.responsiveOverrides == nil)
        let restored = try JSONDecoder().decode(PartNode.self, from: JSONEncoder().encode(created))
        let node = restored.resolved(at: .large)
        #expect(node.propertyValue(.init(rawValue: "pair")) == .array([.number(3), .number(4)]))
        #expect(node.propertyValue(.init(rawValue: "border.style")).stringValue == "dashed")
        #expect(node.propertyValue(.init(rawValue: "font")).stringValue == "heading")
        #expect(node.propertyValue(.init(rawValue: "font.weight")) == .number(700))
        guard case .packageColor(let colour) = node.propertyValue(.init(rawValue: "colour")) else { Issue.record("Missing colour"); return }
        #expect(colour.shade.rawValue == 8)
        #expect(colour.darkShade.rawValue == 3)
        let encoded = try PropertyListEncoder().encode(package.manifest)
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: encoded)
        #expect(decoded.resolvedProperties.first?.breakpointDefaults["large"] == .array([.number(3), .number(4)]))
    }

    @Test @MainActor func developerBreakpointDefaultsCascadeAndExport() throws {
        let controls = """
        <dict><key>type</key><string>number</string><key>id</key><string>gap</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><integer>4</integer><key>medium</key><integer>12</integer><key>large</key><integer>24</integer></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>", additionalFiles: ["part.css": ":instance { gap: {{ control.gap }}px; }"])
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }
        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        let key = PartProperty.Key(rawValue: "gap")
        #expect(node.propertyValue(key, at: .small) == .number(4))
        #expect(node.propertyValue(key, at: .medium) == .number(12))
        #expect(node.propertyValue(key, at: .extraLarge) == .number(24))
        #expect(!node.hasResponsiveOverride(key, at: .medium))
        var screens = ScreenTokens.standard
        screens.update(.medium) { $0.isEnabled = false }
        #expect(node.propertyValue(key, at: .medium, screens: screens) == .number(4))
        node.setResponsiveProperty(key, value: .number(18), at: .medium)
        #expect(node.propertyValue(key, at: .medium) == .number(18))
        #expect(node.propertyValue(key, at: .large) == .number(24))
        #expect(node.propertyValue(key, at: .medium, screens: screens) == .number(4))
        node.removeResponsiveOverride(key, at: .medium)
        #expect(node.propertyValue(key, at: .medium) == .number(12))
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
    }

    @Test @MainActor func editsTargetTheGoverningBreakpointNotTheViewedOne() throws {
        let controls = """
        <dict><key>type</key><string>number</string><key>id</key><string>gap</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><integer>4</integer><key>medium</key><integer>12</integer></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: controls), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
        defer { try? FileManager.default.removeItem(at: url) }
        let package = try PartPackageLoader.load(from: url)
        PartRegistry.register(package)
        defer { PartRegistry.unregisterPackage(identifier: package.manifest.identifier) }

        var node = PartNode(type: .init(rawValue: package.manifest.identifier))
        let key = PartProperty.Key(rawValue: "gap")

        // With no pins, everything below the developer's medium default inherits
        // the base; medium and above are governed by that declared default.
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
            "<key>default</key><integer>1</integer>",
            "<key>defaults</key><dict><key>large</key><integer>1</integer></dict>",
            "<key>defaults</key><dict><key>base</key><integer>1</integer><key>desktop</key><integer>2</integer></dict>",
            "<key>defaults</key><dict><key>base</key><integer>1</integer><key>large</key><integer>2</integer></dict>"
        ] {
            let item = "<dict><key>type</key><string>number</string><key>id</key><string>n</string>\(fields)</dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: item).utf8)).contains { $0.severity == .error })
        }
    }

    @Test @MainActor func edgesAndCornersControlsLoadPersistAndRender() throws {
        let controls = """
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string>
        <key>units</key><array><string>px</string><string>%</string></array>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>10</real><key>unit</key><string>px</string></dict></dict></dict>
        <dict><key>type</key><string>corners</string><key>id</key><string>round</string>
        <key>defaults</key><dict><key>base</key><dict>
            <key>topLeft</key><dict><key>value</key><real>2</real><key>unit</key><string>px</string></dict>
            <key>topRight</key><dict><key>value</key><real>4</real><key>unit</key><string>px</string></dict>
            <key>bottomLeft</key><dict><key>value</key><real>6</real><key>unit</key><string>px</string></dict>
            <key>bottomRight</key><dict><key>value</key><real>8</real><key>unit</key><string>px</string></dict>
        </dict></dict></dict>
        <dict><key>type</key><string>edges</string><key>id</key><string>free</string><key>linked</key><false/>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>10</real><key>unit</key><string>px</string></dict></dict></dict>
        """
        let url = try makePackage(
            manifest: manifest(withControls: controls),
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
        #expect(inset.verticalLinked && inset.horizontalLinked)
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
                manifest: manifest(withControls: controls),
                template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
                additionalFiles: ["part.css": ":instance { }"]
            )
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try PartPackageLoader.load(from: url)
        }
        // Framework tokens are not part of the generic contract.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string>
        <key>defaults</key><dict><key>base</key><string>sm</string></dict></dict>
        """) }
        // A default must use a declared unit.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string>
        <key>units</key><array><string>px</string></array>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>1</real><key>unit</key><string>rem</string></dict></dict></dict>
        """) }
        // Corners are nonnegative.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>corners</string><key>id</key><string>round</string>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>-2</real><key>unit</key><string>px</string></dict></dict></dict>
        """) }
        // Unknown units are rejected.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string>
        <key>units</key><array><string>pt</string></array>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>1</real><key>unit</key><string>px</string></dict></dict></dict>
        """) }
        // No multi variant.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string><key>count</key><integer>2</integer>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>1</real><key>unit</key><string>px</string></dict></dict></dict>
        """) }
        // Negative edges are permitted, matching margin semantics.
        #expect(throws: Never.self) { try load("""
        <dict><key>type</key><string>edges</string><key>id</key><string>inset</string>
        <key>defaults</key><dict><key>base</key><dict><key>value</key><real>-4</real><key>unit</key><string>px</string></dict></dict></dict>
        """) }
        // linked: true contradicts differing defaults.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>corners</string><key>id</key><string>round</string><key>linked</key><true/>
        <key>defaults</key><dict><key>base</key><dict>
            <key>topLeft</key><dict><key>value</key><real>2</real><key>unit</key><string>px</string></dict>
            <key>topRight</key><dict><key>value</key><real>4</real><key>unit</key><string>px</string></dict>
            <key>bottomLeft</key><dict><key>value</key><real>2</real><key>unit</key><string>px</string></dict>
            <key>bottomRight</key><dict><key>value</key><real>2</real><key>unit</key><string>px</string></dict>
        </dict></dict></dict>
        """) }
        // linked belongs to edges/corners only.
        #expect(throws: (any Error).self) { try load("""
        <dict><key>type</key><string>number</string><key>id</key><string>n</string><key>linked</key><true/>
        <key>defaults</key><dict><key>base</key><integer>1</integer></dict></dict>
        """) }
    }

    @Test @MainActor func frameworkColorChannelsFiltersAndFormatsResolveForBothAppearances() throws {
        let controls = """
        <dict><key>type</key><string>frameworkColor</string><key>id</key><string>primary</string>
        <key>allowsCustom</key><true/><key>customColor</key><string>#FF0000</string>
        <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>custom</string></dict></dict></dict>
        <dict><key>type</key><string>frameworkColor</string><key>id</key><string>formatted</string>
        <key>allowsCustom</key><true/><key>customColor</key><string>#FF0000</string><key>outputFormat</key><string>rgb</string>
        <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>custom</string></dict></dict></dict>
        """
        let url = try makePackage(
            manifest: manifest(withControls: controls),
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
            <dict><key>type</key><string>frameworkColor</string><key>id</key><string>primary</string>
            <key>outputFormat</key><string>\(format)</string>
            <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>accent</string></dict></dict></dict>
            """
            return try makePackage(
                manifest: manifest(withControls: controls),
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
        <dict><key>type</key><string>frameworkSpacing</string><key>id</key><string>frameworkSpacing</string>
        <key>responsive</key><true/><key>defaults</key><dict><key>base</key><string>sm</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: control), template: "<section {{ part.attributes }} data-spacing=\"{{ control.frameworkSpacing.css }}\" data-top=\"{{ control.frameworkSpacing }}\">{{ childArea(\"content\") }}</section>",
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
            "<string>sm</string>",
            "<dict><key>width</key><string>auto</string></dict>",
            "<dict><key>width</key><string>sm</string><key>style</key><string>invalid</string></dict>",
            "<dict><key>width</key><string>sm</string><key>color</key><dict><key>palette</key><string>bad</string></dict></dict>",
            "<dict><key>width</key><string>sm</string><key>color</key><dict><key>palette</key><string>accent</string><key>darkShade</key><integer>12</integer></dict></dict>"
        ]
        for value in invalid {
            let url = try makePackage(manifest: manifest(withControls: "<dict><key>type</key><string>frameworkBorder</string><key>id</key><string>border</string><key>defaults</key><dict><key>base</key>\(value)</dict></dict>"), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: (any Error).self) { try PartPackageLoader.load(from: url) }
        }
    }

    @Test @MainActor func frameworkBorderLoadsPersistsAndRenders() throws {
        let control = """
        <dict><key>type</key><string>frameworkBorder</string><key>id</key><string>border</string>
        <key>responsive</key><true/><key>showsStyle</key><true/><key>defaults</key><dict><key>base</key><dict><key>width</key><string>sm</string><key>style</key><string>dashed</string></dict></dict></dict>
        <dict><key>type</key><string>frameworkColor</string><key>id</key><string>borderColour</string><key>group</key><string>Settings</string><key>defaults</key><dict><key>base</key><dict><key>palette</key><string>standard.lime</string><key>lightShade</key><integer>8</integer></dict></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: control), template: "<section {{ part.attributes }} data-borderWidth=\"{{ control.border.width.css }}\" data-top=\"{{ control.border.width.top }}\">{{ childArea(\"content\") }}</section>",
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
        <dict><key>type</key><string>frameworkRadius</string><key>id</key><string>frameworkRadius</string>
        <key>responsive</key><true/><key>defaults</key><dict><key>base</key><string>sm</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: control), template: "<section {{ part.attributes }} data-radius=\"{{ control.frameworkRadius.css }}\" data-top=\"{{ control.frameworkRadius.topLeft }}\">{{ childArea(\"content\") }}</section>",
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
            <dict><key>type</key><string>frameworkColor</string><key>id</key><string>colour</string>
            <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>\(palette.id)</string>
            <key>lightShade</key><integer>8</integer><key>darkShade</key><integer>3</integer></dict></dict></dict>
            """
            let url = try makePackage(manifest: manifest(withControls: control),
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
            let control = "<dict><key>type</key><string>frameworkColor</string><key>id</key><string>colour</string><key>defaults</key><dict><key>base</key><dict><key>palette</key><string>\(id)</string></dict></dict></dict>"
            let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: control).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.severity == .error })
        }
    }
    @Test @MainActor func frameworkMarginLoadsPersistsAndRenders() throws {
        let control = """
        <dict><key>type</key><string>frameworkMargin</string><key>id</key><string>frameworkMargin</string>
        <key>responsive</key><true/><key>defaults</key><dict><key>base</key><string>auto</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: control), template: "<section {{ part.attributes }} data-margin=\"{{ control.frameworkMargin.css }}\" data-top=\"{{ control.frameworkMargin.top }}\">{{ childArea(\"content\") }}</section>",
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
        <dict><key>type</key><string>frameworkPadding</string><key>id</key><string>frameworkPadding</string>
        <key>responsive</key><true/><key>defaults</key><dict><key>base</key><string>sm</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: control), template: "<section {{ part.attributes }} data-padding=\"{{ control.frameworkPadding.css }}\" data-top=\"{{ control.frameworkPadding.top }}\">{{ childArea(\"content\") }}</section>",
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
        for extra in ["<key>count</key><integer>4</integer>", "<key>allowsCustom</key><true/>",
                      "<key>options</key><array/>", "<key>frameworkValues</key><string>spacing</string>"] {
            let control = "<dict><key>type</key><string>frameworkPadding</string><key>id</key><string>frameworkPadding</string><key>defaults</key><dict><key>base</key><string>sm</string></dict>\(extra)</dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: control).utf8)).contains { $0.severity == .error })
        }
    }

    @Test func explicitlyRequestedPackTreeLoadsUsingCurrentAPI() throws {
        guard let path = ProcessInfo.processInfo.environment["FOUNDRY_VALIDATE_PACK_TREE"] else { return }
        let urls = FoundryPackLoader.packURLs(in: URL(fileURLWithPath: path), includingRoot: true)
        #expect(!urls.isEmpty)
        for url in urls {
            let pack = try FoundryPackLoader.load(from: url)
            guard !pack.isCollection else { continue }
            do {
                _ = try PartPackageLoader.load(from: url)
            } catch {
                Issue.record("\(url.path): \(error)")
            }
        }
    }

    @Test func generatedFontRowsShareOneInspectorGrid() throws {
        let item = """
        <dict><key>type</key><string>frameworkFont</string><key>id</key><string>font</string>
        <key>defaults</key><dict><key>base</key><string>body</string></dict><key>showsWeight</key><true/><key>showsStyle</key><true/></dict>
        """
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: item).utf8))
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
        <dict><key>type</key><string>select</string><key>id</key><string>choice</string>
        <key>options</key><array><dict><key>value</key><string>body</string><key>title</key><string>Body</string></dict></array>
        <key>defaults</key><dict><key>base</key><string>body</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: item),
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

        for extra in ["<key>allowsCustom</key><false/>", "<key>allowsCustom</key><true/>"] +
            ["fontFamilies", "fontSizes", "spacing", "shadows", "colors"].map({ "<key>frameworkValues</key><string>\($0)</string>" }) {
            let invalid = item.replacingOccurrences(of: "<key>type</key>", with: extra + "<key>type</key>")
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: invalid).utf8))
                .contains { $0.message.contains("Select supports only declared options") })
        }
    }

    @Test @MainActor func frameworkFontSizeControlResolvesSizeAndLineHeightVariables() throws {
        let item = """
        <dict><key>type</key><string>frameworkFontSize</string><key>id</key><string>size</string>
        <key>label</key><string>Size</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><string>xl</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: item),
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
        let withValues = item.replacingOccurrences(of: "<key>type</key>", with: "<key>frameworkValues</key><string>fontSizes</string><key>type</key>")
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: withValues).utf8))
            .contains { $0.message.contains("does not accept frameworkValues") })
        let badDefault = item.replacingOccurrences(of: "<string>xl</string>", with: "<string>huge</string>")
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: badDefault).utf8))
        #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
            .contains { $0.message.contains("frameworkFontSize default must be a predefined size ID") })
    }

    @Test @MainActor func frameworkStackingOrderControlResolvesVariable() throws {
        let item = """
        <dict><key>type</key><string>frameworkStackingOrder</string><key>id</key><string>layer</string>
        <key>label</key><string>Layer</string><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><string>modal</string></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: item),
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
        let withValues = item.replacingOccurrences(of: "<key>type</key>", with: "<key>frameworkValues</key><string>zIndexes</string><key>type</key>")
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: withValues).utf8))
            .contains { $0.message.contains("does not accept frameworkValues") })
        let badDefault = item.replacingOccurrences(of: "<string>modal</string>", with: "<string>everest</string>")
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: badDefault).utf8))
        #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
            .contains { $0.message.contains("frameworkStackingOrder default must be a predefined stacking ID") })
    }

    @Test @MainActor func unifiedFontControlHasStructuredOutputAndIndependentOverrides() throws {
        let item = """
        <dict><key>type</key><string>frameworkFont</string><key>id</key><string>typography</string>
        <key>showsWeight</key><true/><key>showsStyle</key><true/><key>responsive</key><true/>
        <key>defaults</key><dict><key>base</key><dict><key>family</key><string>body</string><key>weight</key><integer>650</integer><key>style</key><string>italic</string></dict></dict></dict>
        """
        let url = try makePackage(manifest: manifest(withControls: item), template: "<section {{ part.attributes }} data-face=\"{{ control.typography.family }}|{{ control.typography.weight }}|{{ control.typography.style }}\">{{ childArea(\"content\") }}</section>")
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
            "<key>showsFamily</key><false/>",
            "<key>defaults</key><dict><key>base</key><dict><key>family</key><string>body</string><key>weight</key><integer>500</integer></dict></dict>",
            "<key>showsWeight</key><true/><key>defaults</key><dict><key>base</key><dict><key>family</key><string>body</string><key>weight</key><integer>1001</integer></dict></dict>",
            "<key>showsStyle</key><true/><key>defaults</key><dict><key>base</key><dict><key>family</key><string>body</string><key>style</key><string>bold</string></dict></dict>"
        ] {
            let defaultXML = extra.contains("<key>defaults</key>") ? "" : "<key>defaults</key><dict><key>base</key><string>body</string></dict>"
            let item = "<dict><key>type</key><string>frameworkFont</string><key>id</key><string>font</string>\(defaultXML)\(extra)</dict>"
            let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.severity == .error && ($0.message.contains("default.") || $0.message.contains("at least one")) })
        }
        for kind in ["fontWeight", "fontStyle"] {
            let item = "<dict><key>type</key><string>\(kind)</string><key>id</key><string>font</string><key>defaults</key><dict><key>base</key><string>normal</string></dict></dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: item).utf8)).contains { $0.message.contains("Use one frameworkFont") })
        }
    }

    @Test @MainActor func fixedFamilyCanExposeOnlyWeight() throws {
        let item = "<dict><key>type</key><string>frameworkFont</string><key>id</key><string>font</string><key>showsFamily</key><false/><key>showsWeight</key><true/><key>responsive</key><true/><key>defaults</key><dict><key>base</key><string>body</string></dict></dict>"
        let url = try makePackage(manifest: manifest(withControls: item), template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>")
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
            let item = "<dict><key>type</key><string>frameworkFont</string><key>id</key><string>family</string><key>defaults</key><dict><key>base</key><string>\(role)</string></dict><key>responsive</key><true/></dict>"
            let url = try makePackage(manifest: manifest(withControls: item), template: "<section {{ part.attributes }} style=\"font-family: {{ control.family.family }}\">{{ childArea(\"content\") }}</section>")
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
            let item = "<dict><key>type</key><string>frameworkFont</string><key>id</key><string>family</string><key>defaults</key><dict><key>base</key><string>\(value)</string></dict></dict>"
            let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifest(withControls: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory).contains { $0.message.contains("frameworkFont default") })
        }
        for extra in ["<key>count</key><integer>2</integer>", "<key>frameworkValues</key><string>fontFamilies</string>", "<key>options</key><array/>", "<key>allowsCustom</key><false/>"] {
            let item = "<dict><key>type</key><string>frameworkFont</string><key>id</key><string>family</string><key>defaults</key><dict><key>base</key><string>body</string></dict>\(extra)</dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: item).utf8)).contains { $0.message.contains("frameworkFont control does not accept") })
        }
    }

    @Test
    func frameworkColourAcceptsAnOptionalInitialShade() throws {
        for key in ["lightShade", "darkShade"] {
        for shade in [nil, 1, 8, 11] as [Int?] {
            let item = """
            <dict><key>id</key><string>colour</string>
            <key>type</key><string>frameworkColor</string>
            <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>accent</string>
            \(shade.map { "<key>\(key)</key><integer>\($0)</integer>" } ?? "")</dict></dict></dict>
            """
            let url = try makePackage(manifest: manifest(withControls: item),
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
            <dict><key>id</key><string>colour</string><key>type</key><string>\(type)</string>
            <key>defaults</key><dict><key>base</key><dict><key>palette</key><string>\(value)</string><key>lightShade</key><integer>\(initial)</integer></dict></dict></dict>
            """
            let decoded = try PropertyListDecoder().decode(PartPackageManifest.self,
                from: Data(manifest(withControls: item).utf8))
            #expect(PartPackageValidator.validate(decoded, rootURL: FileManager.default.temporaryDirectory)
                .contains { $0.location.hasSuffix(".lightShade") && $0.severity == .error })
        }
        for invalid in ["<string>8</string>", "<true/>", "<real>2.5</real>"] {
            let item = "<dict><key>id</key><string>colour</string><key>type</key><string>frameworkColor</string><key>defaults</key><dict><key>base</key><dict><key>palette</key><string>accent</string><key>lightShade</key>\(invalid)</dict></dict></dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: item).utf8))
                .contains { $0.message == "lightShade must be an integer." })
        }
    }

    @Test func frameworkColourRejectsOldDefaultsAndUnknownNestedKeys() throws {
        for value in ["<string>accent</string>", "<array><string>accent</string></array>",
                      "<dict><key>palette</key><string>accent</string><key>shade</key><integer>3</integer></dict>"] {
            let item = "<dict><key>id</key><string>colour</string><key>type</key><string>frameworkColor</string><key>defaults</key><dict><key>base</key>\(value)</dict></dict>"
            #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: item).utf8)).contains { $0.severity == .error })
        }
        let oldKeys = "<dict><key>id</key><string>colour</string><key>type</key><string>frameworkColor</string><key>defaults</key><dict><key>base</key><dict><key>palette</key><string>accent</string></dict></dict><key>lightShade</key><integer>8</integer></dict>"
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(manifest(withControls: oldKeys).utf8)).contains { $0.message.contains("Unknown key 'lightShade'") })
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
            path: "Contents/Resources/\(first.package.manifest.render.html)"
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
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>type</key><string>\(type)</string>
            </dict></plist>
            """

            do {
                _ = try PropertyListDecoder().decode(
                    PartPackageControl.self,
                    from: Data(plist.utf8)
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
            from: repositoryURL.appending(path: "DevelopmentFixtures/AppearanceToggle.foundrydevpack"))
        try appearancePackage.preparePayload()
        #expect(appearancePackage.manifest.identifier == "dev.foundry.appearance-toggle")
        #expect(FileManager.default.fileExists(atPath: appearancePackage.iconURL.path))
        #expect(PartPackageValidator.validate(
            appearancePackage.manifest,
            rootURL: appearancePackage.iconURL.deletingLastPathComponent()
        ).filter { $0.severity == .error }.isEmpty)
        let fixtureURL = repositoryURL.appending(
            path: "DevelopmentFixtures/BrokenPart.foundrydevpack",
            directoryHint: .isDirectory
        )

        let header = try FoundryPackLoader.load(from: fixtureURL)
        #expect(!header.isCollection)

        do {
            _ = try PartPackageLoader.load(from: fixtureURL)
            Issue.record("The intentionally broken part unexpectedly loaded.")
        } catch PartPackageLoadingError.invalid(let diagnostics) {
            #expect(diagnostics.contains { $0.message.contains("reverse-DNS") })
            #expect(diagnostics.contains { $0.message.contains("does not exist") })
        } catch {
            Issue.record("Expected part validation diagnostics, but received: \(error)")
        }

        let enablePackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/EnableConditions.foundrydevpack")
        )
        #expect(enablePackage.manifest.identifier == "dev.foundry.enable-conditions")
        #expect(enablePackage.manifest.resolvedProperties.contains { $0.visibleWhen?.id == "titles[2]" })

        let frameworkPackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/FrameworkValues.foundrydevpack")
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
            from: repositoryURL.appending(path: "DevelopmentFixtures/ScopedAssets.foundrydevpack")
        )
        #expect(scopedAssetsPackage.manifest.identifier == "dev.foundry.scoped-assets")
        #expect(scopedAssetsPackage.manifest.assets.count == 3)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .page }.count == 2)
        #expect(scopedAssetsPackage.manifest.assets.filter { $0.scope == .site }.count == 1)

        let expressionPackage = try PartPackageLoader.load(
            from: repositoryURL.appending(path: "DevelopmentFixtures/ExpressionEngine.foundrydevpack")
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
    func backgroundControlGroupExpandsIntoFoundryOwnedControls() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.background-group</string>
        <key>title</key><string>Background Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict><key>type</key><string>background</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """

        let data = Data(plist.utf8)
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups == [.init(type: .background)])
        #expect(manifest.resolvedProperties.first?.id == "backgroundMode")
        #expect(manifest.resolvedProperties.first?.defaultValue == .string("none"))
        #expect(manifest.resolvedProperties.contains { $0.id == "backgroundImage" && $0.control.type == .image })
        #expect(manifest.resolvedProperties.contains { $0.id == "backgroundGradientFrom" && $0.control.type == .frameworkColor })
        #expect(manifest.resolvedProperties.contains { $0.id == "backgroundVideo" && $0.control.type == .video })
        #expect(manifest.controlGroupCSS.contains(#"[data-foundry-control-group-background="{{ instance.id }}"]:hover"#))
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func backgroundControlGroupCanSelectStylesAndStates() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.selective-background-group</string>
        <key>title</key><string>Selective Background Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict>
            <key>type</key><string>background</string>
            <key>styles</key><array><string>colour</string><string>image</string></array>
            <key>states</key><array><string>static</string></array>
        </dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """

        let data = Data(plist.utf8)
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups == [
            .init(type: .background, styles: [.colour, .image], states: [.staticState])
        ])
        let identifiers = Set(manifest.resolvedProperties.map(\.id))
        #expect(identifiers.contains("backgroundColor"))
        #expect(identifiers.contains("backgroundImage"))
        #expect(!identifiers.contains("backgroundGradientType"))
        #expect(!identifiers.contains("backgroundVideo"))
        #expect(!identifiers.contains("backgroundHoverStyle"))
        let mode = try #require(manifest.resolvedProperties.first { $0.id == "backgroundMode" })
        #expect(mode.control.options?.map(\.value) == ["none", "static"])
        let style = try #require(manifest.resolvedProperties.first { $0.id == "backgroundStyle" })
        #expect(style.control.options?.map(\.value) == ["color", "image"])
        #expect(style.defaultValue == .string("color"))
        #expect(!manifest.controlGroupCSS.contains(#"[data-foundry-control-group-background="{{ instance.id }}"]:hover"#))
        #expect(!manifest.controlGroupCSS.contains("backgroundGradient"))
        #expect(!manifest.controlGroupCSS.contains("backgroundVideo"))
        #expect(manifest.htmlContributions.isEmpty)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func backgroundControlGroupValidatesSelectedStylesAndStates() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.invalid-background-group</string>
        <key>title</key><string>Invalid Background Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict>
            <key>type</key><string>background</string>
            <key>styles</key><array/>
            <key>states</key><array><string>hover</string><string>hover</string></array>
        </dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """

        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(plist.utf8))
        let messages = diagnostics.map(\.message)
        #expect(messages.contains("styles must contain at least one value."))
        #expect(messages.contains("Duplicate states value 'hover'."))
        #expect(messages.contains("states must include 'static'; hover augments the static background."))
    }

    @Test
    func backgroundControlGroupDecoratesVideoHTML() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.background-video</string>
        <key>title</key><string>Background Video</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict><key>type</key><string>background</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))
        let properties: [String: PartPackageValue] = [
            "backgroundMode": .string("hover"),
            "backgroundStyle": .string("color"),
            "backgroundHoverStyle": .string("video"),
            "backgroundHoverVideo": .string(#"assets/film&trailer.mp4"#),
            "backgroundHoverVideo.href": .string(#"assets/film&trailer.mp4"#),
            "backgroundHoverVideo.poster": .string("data:image/jpeg;base64,poster-frame")
        ]
        let instanceID = UUID()
        let context = PartTemplateContext(
            instanceID: instanceID,
            packageIdentifier: manifest.identifier,
            properties: properties,
            slots: [:]
        )
        let html = PartTemplateRenderer.render(
            #"<section class="example" {{ controlGroup.background }}><p>Content</p></section>"#,
            context: context
        )
        let rendered = PartPackageHTMLContributionRenderer.decorate(
            html,
            contributions: manifest.htmlContributions,
            context: context
        )

        #expect(rendered.contains(#"class="foundry-background-video foundry-background-video--hover""#))
        #expect(rendered.contains(#"src="assets/film&amp;trailer.mp4""#))
        #expect(rendered.contains(#"poster="data:image/jpeg;base64,poster-frame""#))
        #expect(rendered.contains("autoplay muted loop playsinline"))
        #expect(rendered.hasPrefix(#"<section class="example" data-foundry-control-group-background="\#(instanceID.uuidString)">"#))
        #expect(rendered.contains(">\n<video class=\"foundry-background-video foundry-background-video--hover\""))

        let canvasContext = PartTemplateContext(
            instanceID: instanceID,
            packageIdentifier: manifest.identifier,
            properties: properties,
            slots: [:],
            environment: .canvas
        )
        let canvasHTML = PartTemplateRenderer.render(
            #"<section class="example" {{ controlGroup.background }}><p>Content</p></section>"#,
            context: canvasContext
        )
        let canvasRendered = PartPackageHTMLContributionRenderer.decorate(
            canvasHTML,
            contributions: manifest.htmlContributions,
            context: canvasContext
        )
        #expect(canvasRendered.contains(#"<img class="foundry-background-video foundry-background-video--hover""#))
        #expect(canvasRendered.contains(#"src="data:image/jpeg;base64,poster-frame""#))
        #expect(!canvasRendered.contains("<video"))
        #expect(!canvasRendered.contains("assets/film&amp;trailer.mp4"))
        #expect(!canvasRendered.contains("autoplay"))
    }

    @Test
    func backgroundControlGroupRequiresExactlyOnePlacementMacro() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.background-placement</string>
        <key>title</key><string>Background Placement</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict><key>type</key><string>background</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))

        for template in [
            #"<section class="sample {{ part.class }}" {{ part.attributes }}></section>"#,
            #"<section class="sample {{ part.class }}" {{ part.attributes }} {{ controlGroup.background }}><div {{ controlGroup.background }}></div></section>"#
        ] {
            let packageURL = try makePackage(manifest: plist, template: template)
            defer { try? FileManager.default.removeItem(at: packageURL) }
            let diagnostics = PartPackageValidator.validate(
                manifest,
                rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            )
            #expect(diagnostics.contains { $0.message.contains("exactly one {{ controlGroup.background }}") })
        }
    }

    @Test
    func sharedPropertyControlGroupsInjectPropertiesWithoutCSSOrHTML() throws {
        for (kind, expectedIDs) in [
            ("spacing", ["spacingEnabled", "frameworkPadding", "frameworkMargin"]),
            ("sizing", ["widthMode", "customWidth", "maxWidth", "minimumHeight", "heightMode", "customHeight"]),
            ("borders", ["borderEnabled", "frameworkBorder", "frameworkBorderColour", "frameworkRadius"]),
            ("effects", ["effectsEnabled", "frameworkShadow", "opacity"]),
            ("layoutItem", ["itemEnabled", "flexGrow", "flexShrink", "alignSelf", "columnSpan", "rowSpan"])
        ] {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>minimumAPIVersion</key><integer>1</integer>
            <key>id</key><string>com.example.\(kind)-group</string>
            <key>title</key><string>\(kind) Group</string>
            <key>version</key><string>1.0.0</string>
            <key>controls</key><array><dict><key>type</key><string>\(kind)</string></dict></array>
            <key>templates</key><dict><key>html</key><string>part.html</string></dict>
            </dict></plist>
            """
            let data = Data(plist.utf8)
            let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
            #expect(manifest.resolvedProperties.map(\.id) == expectedIDs)
            #expect(manifest.controlGroupCSS.isEmpty)
            #expect(manifest.htmlContributions.isEmpty)
            #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
        }
    }

    @Test
    func builtInControlGroupResourcesDecodeToRealControls() {
        for kind in PartPackageControlGroup.Kind.allCases {
            let definition = BuiltInControlGroupRegistry.definition(for: kind)
            #expect(definition.type == kind)
            #expect(!definition.name.isEmpty)
            #expect(!definition.systemImage.isEmpty)
            #expect(!definition.controls.isEmpty)
            #expect(Set(definition.controls.map(\.id)).count == definition.controls.count)
            #expect(definition.controls.allSatisfy { $0.group == definition.name })
        }
    }

    @Test
    func sharedControlGroupDefaultOverridesReplaceOnlyTheNamedProperty() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.spacing-override-group</string>
        <key>title</key><string>Spacing Override Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict>
            <key>type</key><string>spacing</string>
            <key>defaultOverrides</key><dict>
                <key>frameworkPadding</key><dict><key>left</key><string>sm</string></dict>
            </dict>
        </dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.resolvedProperties.first { $0.id == "frameworkPadding" }?.defaultValue == .object(["left": .string("sm")]))
        #expect(manifest.resolvedProperties.first { $0.id == "frameworkMargin" }?.defaultValue == .string("none"))
        #expect(manifest.resolvedProperties.first { $0.id == "spacingEnabled" }?.defaultValue == .boolean(true))
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func unknownControlGroupTypeIsRejected() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.unknown-group</string>
        <key>title</key><string>Unknown Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict><key>id</key><string>gradientField</string><key>type</key><string>gradient</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(plist.utf8))
        // "gradient" isn't a recognised Grouped-control kind, so it falls
        // through to standard property validation, which rejects it as an
        // unrecognised control type instead.
        #expect(diagnostics.contains { $0.message.contains("Unknown control type 'gradient'") })
    }

    @Test
    func duplicateControlGroupTypeIsRejected() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.duplicate-group</string>
        <key>title</key><string>Duplicate Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array>
            <dict><key>type</key><string>spacing</string></dict>
            <dict><key>type</key><string>spacing</string></dict>
        </array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(plist.utf8))
        #expect(diagnostics.contains { $0.message.contains("declared more than once") })
    }

    @Test
    func groupedControlReferencesExpandInlineAtTheAuthorsDeclaredPosition() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.inline-ordering</string>
        <key>title</key><string>Inline Ordering</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array>
            <dict>
                <key>id</key><string>before</string>
                <key>label</key><string>Before</string>
                <key>type</key><string>toggle</string>
                <key>defaults</key><dict><key>base</key><true/></dict>
            </dict>
            <dict><key>type</key><string>borders</string></dict>
            <dict>
                <key>id</key><string>after</string>
                <key>label</key><string>After</string>
                <key>type</key><string>toggle</string>
                <key>defaults</key><dict><key>base</key><false/></dict>
            </dict>
        </array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)

        #expect(manifest.resolvedProperties.map(\.id) == [
            "before", "borderEnabled", "frameworkBorder", "frameworkBorderColour", "frameworkRadius", "after"
        ])
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)
    }

    @Test
    func theOldSeparateControlGroupsKeyIsNoLongerRecognised() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.legacy-control-groups-key</string>
        <key>title</key><string>Legacy Control Groups Key</string>
        <key>version</key><string>1.0.0</string>
        <key>controlGroups</key><array><dict><key>type</key><string>background</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: data)

        #expect(diagnostics.contains { $0.message.contains("Unknown key 'controlGroups'") })
        // Grouped controls declared this way are also silently absent from
        // decode, since the separate key is no longer read at all.
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        #expect(manifest.controlGroups.isEmpty)
    }

    @Test @MainActor
    func videoControlProvidesStructuredTemplateValues() throws {
        let control = """
        <dict>
            <key>id</key><string>film</string>
            <key>label</key><string>Film</string>
            <key>type</key><string>video</string>
            <key>defaults</key><dict><key>base</key><string></string></dict>
        </dict>
        """
        let data = Data(manifest(withControls: control).utf8)
        let decodedManifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        let property = try #require(decodedManifest.resolvedProperties.first)
        #expect(property.control.type == .video)
        #expect(!property.responsive)
        let responsiveControl = control.replacingOccurrences(
            of: "<key>defaults</key><dict><key>base</key><string></string></dict>",
            with: "<key>defaults</key><dict><key>base</key><string></string></dict><key>responsive</key><true/>"
        )
        let responsiveDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withControls: responsiveControl).utf8)
        )
        #expect(responsiveDiagnostics.contains { $0.message == "A video control does not support responsive." })
        let packageURL = try makePackage(
            manifest: manifest(withControls: control),
            template: #"<section class="sample {{ part.class }}" {{ part.attributes }}>{{ control.film }}{{ childArea("content") }}</section>"#
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let package = try PartPackageLoader.load(from: packageURL)
        guard case .video = PartPackageAdapter.definition(from: package).properties.first?.control else {
            Issue.record("Expected a video property control")
            return
        }
        let definitions = PartPackageAdapter.definition(from: package).properties
        #expect(definitions.count == 7)
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
            #"{{ control.film }}|{{ control.film.href }}|{{ control.film.poster }}|{{ control.film.autoplay }}|{{ control.film.muted }}|{{ control.film.controls }}|{{ control.film.loop }}|{{ control.film.startAt }}|{{ control.film.filename }}|{{ control.film.extension }}|{{ control.film.mimeType }}|{{ control.film.byteCount }}|{{ control.film.width }}|{{ control.film.height }}|{{ control.film.duration }}"#,
            context: .init(instanceID: UUID(), packageIdentifier: decodedManifest.identifier, properties: values, slots: [:])
        )
        #expect(rendered == #"<video src="assets/demo.mp4" poster="data:image/jpeg;base64,frame" controls playsinline></video>|assets/demo.mp4|data:image/jpeg;base64,frame|never|false|true|false|0|Demo Film.mp4|mp4|video/mp4|42000|1920|1080|12.5"#)

        PartVideoTemplateValues.insert(
            propertyID: "film",
            href: "assets/demo.mp4",
            poster: "poster.jpg",
            asset: asset,
            playback: .init(autoplay: "onLoad", muted: true, showsControls: false, loops: true, startAt: 4.5),
            into: &values
        )
        let configured = PartTemplateRenderer.render(
            "{{ control.film }}",
            context: .init(instanceID: UUID(), packageIdentifier: decodedManifest.identifier, properties: values, slots: [:])
        )
        #expect(configured == #"<video src="assets/demo.mp4#t=4.5" poster="poster.jpg" autoplay muted loop playsinline></video>"#)

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
        #expect(canvasHTML.contains(#"<video poster="data:image/jpeg;base64,ZnJhbWU=" controls data-foundry-image-drop-zone data-foundry-image-property="__foundry_video_poster_film" playsinline></video>"#))
        #expect(!canvasHTML.contains(asset.id.uuidString))

        var site = Site.starter()
        site.pages = [page]
        site.assetLibrary = [.asset(asset)]
        let exported = StaticSiteRenderer().render(site: site, assets: assets)
        let posterPath = "assets/foundry-video-posters/\(asset.id.uuidString.lowercased()).jpg"
        #expect(exported.file(at: posterPath) == nil)
        #expect(exported.file(at: "index.html")?.contents.contains(#"<video src="assets/"#) == true)
        #expect(exported.file(at: "index.html")?.contents.contains("poster=") == false)
        #expect(exported.file(at: "index.html")?.contents.contains("data-foundry-image-drop-zone") == false)
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
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.background-group</string>
        <key>title</key><string>Background Group</string>
        <key>version</key><string>1.0.0</string>
        <key>controls</key><array><dict><key>type</key><string>background</string></dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """

        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(plist.utf8))
        #expect(diagnostics.isEmpty)
    }

    @Test
    func controlArraysDecodePersistAndRenderIndexedValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.arrays</string>
        <key>title</key><string>Arrays</string><key>description</key><string>Array controls</string>
        <key>author</key><string>Foundry</string><key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>tags</key><array/><key>assets</key><array/>
        <key>controls</key><array><dict>
        <key>id</key><string>palette</string><key>label</key><string>Palette</string><key>group</key><string>Appearance</string>
        <key>subtitle</key><array><string>First</string><string>Second</string><string>Third</string><string>Fourth</string></array>
        <key>tooltip</key><string>Four colours</string>
        <key>type</key><string>color</string><key>count</key><integer>4</integer>
        <key>defaults</key><dict><key>base</key><array><string>#111111</string><string>#222222</string><string>#333333</string><string>#444444</string></array></dict>
        <key>responsive</key><true/>        </dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))
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
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.framework-values</string>
        <key>title</key><string>Framework Values</string><key>description</key><string>Named framework sources</string>
        <key>author</key><string>Foundry</string><key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>tags</key><array/><key>assets</key><array/>
        <key>controls</key><array><dict>
        <key>id</key><string>tone</string><key>label</key><string>Tone</string><key>group</key><string>Appearance</string>
        <key>type</key><string>select</string><key>frameworkValues</key><string>spacing</string>
        <key>allowsCustom</key><true/>
        <key>options</key><array><dict><key>value</key><string>inherit</string><key>title</key><string>Inherit</string></dict></array>
        <key>defaults</key><dict><key>base</key><string>md</string></dict><key>responsive</key><false/>
        </dict></array>
        <key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))
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

        let countedFrameworkSelect = plist
            .replacingOccurrences(
                of: "<key>frameworkValues</key><string>spacing</string>",
                with: "<key>frameworkValues</key><string>fontSizes</string>"
            )
            .replacingOccurrences(
                of: "<key>defaults</key><dict><key>base</key><string>md</string></dict><key>responsive</key><false/>",
                with: "<key>defaults</key><dict><key>base</key><string>base</string></dict><key>responsive</key><false/><key>count</key><integer>2</integer>"
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
                of: "<key>type</key><string>select</string>",
                with: "<key>type</key><string>frameworkColor</string>"
            )
        let colorSchemaDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(countedFrameworkColor.utf8)
        )
        #expect(colorSchemaDiagnostics.contains {
            $0.location.hasSuffix(".count")
                && $0.message == "A frameworkColor control cannot be a multi control; remove count."
        })

        let booleanFrameworkValues = Data(
            plist.replacingOccurrences(
                of: "<key>frameworkValues</key><string>spacing</string>",
                with: "<key>frameworkValues</key><true/>"
            ).utf8
        )
        #expect(try PartPackageManifestSchema.diagnostics(for: booleanFrameworkValues).contains {
            $0.location.hasSuffix(".frameworkValues") && $0.message == "frameworkValues must be a string."
        })

        do {
            _ = try PropertyListDecoder().decode(
                PartPackageControl.self,
                from: Data("<plist version=\"1.0\"><dict><key>type</key><string>color</string><key>frameworkValues</key><true/></dict></plist>".utf8)
            )
            Issue.record("Boolean frameworkValues should be rejected")
        } catch {
            // String-only decoding intentionally rejects the removed API.
        }
    }

    @Test
    func fontFamilyFrameworkSelectRejectsCustomValues() throws {
        let item = """
        <dict>
            <key>id</key><string>typeface</string>
            <key>label</key><string>Typeface</string>
            <key>group</key><string>Typography</string>
            <key>type</key><string>select</string>
            <key>frameworkValues</key><string>fontFamilies</string>
            <key>allowsCustom</key><true/>
            <key>defaults</key><dict><key>base</key><string>body</string></dict>
            <key>responsive</key><true/>
        </dict>
        """
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withControls: item).utf8)
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
        <dict>
            <key>id</key><string>cardShadow</string>
            <key>label</key><string>Shadow</string>
            <key>group</key><string>Appearance</string>
            <key>type</key><string>frameworkShadow</string>
            <key>allowsCustom</key><true/>
            <key>defaults</key><dict><key>base</key><string>md</string></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let decodedManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withControls: item).utf8)
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
            $0.location.contains("cardShadow") || $0.location.contains("controls")
        })

        let legacyItem = item
            .replacingOccurrences(
                of: "<key>type</key><string>frameworkShadow</string>",
                with: "<key>type</key><string>select</string><key>frameworkValues</key><string>shadows</string>"
            )
        let legacyDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withControls: legacyItem).utf8)
        )
        #expect(legacyDiagnostics.contains {
            $0.location.hasSuffix(".frameworkValues")
                && $0.message == "Select supports only declared options; remove frameworkValues."
        })

        // The pre-rename spelling is gone for good: bare `shadow` is an unknown type.
        let renamedItem = item.replacingOccurrences(
            of: "<key>type</key><string>frameworkShadow</string>",
            with: "<key>type</key><string>shadow</string>"
        )
        let renamedDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withControls: renamedItem).utf8)
        )
        #expect(renamedDiagnostics.contains { $0.message == "Unknown control type 'shadow'." })
    }

    @Test
    func malformedControlFieldsProduceActionableSchemaDiagnostics() throws {
        let validItem = """
        <dict>
            <key>id</key><string>example</string>
            <key>label</key><string>Example</string>
            <key>type</key><string>text</string>
            <key>defaults</key><dict><key>base</key><string>Hello</string></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let cases: [(replacement: String, locationSuffix: String, message: String)] = [
            (
                validItem
                    .replacingOccurrences(of: "<string>text</string>", with: "<string>frameworkColor</string>")
                    .replacingOccurrences(of: "<key>label</key>", with: "<key>colorMath</key><true/><key>label</key>"),
                ":colorMath", "Unknown key 'colorMath'. Check the spelling or remove it."
            ),
            (
                validItem.replacingOccurrences(of: "<key>type</key><string>text</string>", with: "<key>type</key><integer>1</integer>"),
                ":type", "type must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "<string>text</string>", with: "<string>fontFamily</string>"),
                ":type", "Unknown control type 'fontFamily'."
            ),
            (
                validItem.replacingOccurrences(of: "<key>label</key><string>Example</string>", with: "<key>label</key><array><string>Example</string></array>"),
                ":label", "label must be a string."
            ),
            (
                validItem.replacingOccurrences(of: "<key>label</key>", with: "<key>labels</key>"),
                ":labels", "Unknown key 'labels'. Check the spelling or remove it."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><string>false</string>"),
                ":responsive", "responsive must be a Boolean."
            ),
            (
                validItem.replacingOccurrences(of: "<key>defaults</key><dict><key>base</key><string>Hello</string></dict>", with: "<key>defaults</key><dict><key>base</key><dict/></dict>"),
                ":defaults.base", "defaults.base must be a string, number, Boolean, or array of those values."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><false/><key>minimum</key><string>zero</string>"),
                ":minimum", "minimum must be a number."
            ),
            (
                validItem.replacingOccurrences(of: "<key>responsive</key><false/>", with: "<key>responsive</key><false/><key>count</key><string>two</string>"),
                ":count", "count must be an integer."
            )
        ]

        for testCase in cases {
            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withControls: testCase.replacement).utf8)
            )
            #expect(diagnostics.contains {
                $0.location.hasSuffix(testCase.locationSuffix) && $0.message == testCase.message
            })
        }

        let malformedOptions = validItem.replacingOccurrences(
            of: "<key>responsive</key><false/>",
            with: "<key>responsive</key><false/><key>options</key><array><string>bad</string></array>"
        )
        #expect(try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withControls: malformedOptions).utf8)
        ).contains {
            $0.location.hasSuffix(":options[0]") && $0.message == "Each options entry must be a dictionary."
        })

        let withoutResponsive = validItem.replacingOccurrences(
            of: "<key>responsive</key><false/>",
            with: ""
        )
        let withoutResponsiveData = Data(manifest(withControls: withoutResponsive).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: withoutResponsiveData).isEmpty)
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: withoutResponsiveData)
        #expect(decoded.resolvedProperties.first?.responsive == false)
    }

    @Test
    func visibilityConditionsDecodeAndEvaluateScalarAndIndexedValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.visibleWhen</string>
        <key>title</key><string>Visibility</string><key>description</key><string>Conditional controls</string>
        <key>version</key><string>1.0.0</string><key>group</key><string>Other</string>
        <key>assets</key><array/>
        <key>controls</key><array>
        <dict><key>id</key><string>mode</string><key>label</key><string>Mode</string><key>type</key><string>select</string><key>options</key><array><dict><key>value</key><string>featured</string><key>title</key><string>Featured</string></dict></array><key>defaults</key><dict><key>base</key><string>featured</string></dict><key>responsive</key><false/></dict>
        <dict><key>id</key><string>titles</string><key>label</key><string>Titles</string><key>type</key><string>text</string><key>count</key><integer>3</integer><key>defaults</key><dict><key>base</key><array><string>One</string><string>Two</string><string>Featured story</string></array></dict><key>responsive</key><false/></dict>
        <dict><key>id</key><string>detail</string><key>label</key><string>Detail</string><key>type</key><string>text</string><key>defaults</key><dict><key>base</key><string>Visible</string></dict><key>responsive</key><false/><key>visibleWhen</key><dict><key>id</key><string>titles[2]</string><key>operation</key><string>containsInsensitive</string><key>value</key><string>featured</string></dict></dict>
        <dict><key>id</key><string>compoundDetail</string><key>label</key><string>Compound detail</string><key>type</key><string>text</string><key>defaults</key><dict><key>base</key><string>Visible</string></dict><key>responsive</key><false/><key>visibleWhen</key><dict><key>all</key><array><dict><key>id</key><string>mode</string><key>value</key><string>featured</string></dict><dict><key>any</key><array><dict><key>id</key><string>titles[0]</string><key>value</key><string>One</string></dict><dict><key>id</key><string>titles[1]</string><key>value</key><string>Other</string></dict></array></dict></array></dict></dict>
        </array><key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))
        let enabledProperty = try #require(manifest.resolvedProperties.first { $0.id == "detail" })
        #expect(enabledProperty.visibleWhen?.id == "titles[2]")
        #expect(enabledProperty.visibleWhen?.operation == "containsInsensitive")

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
        #expect(try PartPackageManifestSchema.diagnostics(for: Data(plist.utf8)).isEmpty)
    }

    @Test
    func virtualControlsAndButtonOutputsResolveFromManifestValues() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.derived</string>
        <key>title</key><string>Derived</string><key>description</key><string>Derived controls</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>controls</key><array>
        <dict><key>id</key><string>amount</string><key>label</key><string>Amount</string><key>group</key><string>Test</string><key>type</key><string>number</string><key>defaults</key><dict><key>base</key><real>21</real></dict><key>responsive</key><false/></dict>
        <dict><key>id</key><string>action</string><key>label</key><string>Action</string><key>group</key><string>Test</string><key>type</key><string>button</string><key>trueValue</key><string>active</string><key>falseValue</key><string>ready</string><key>defaults</key><dict><key>base</key><false/></dict><key>responsive</key><false/></dict>
        <dict><key>id</key><string>doubled</string><key>group</key><string>Test</string><key>type</key><string>math</string><key>argument1</key><string>amount</string><key>argument2</key><real>2</real><key>operation</key><string>*</string><key>round</key><false/></dict>
        </array><key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(plist.utf8))
        let resolved = PartPackageDerivedValueResolver.resolve(
            ["amount": .number(21), "action": .boolean(true)],
            properties: manifest.resolvedProperties
        )
        #expect(resolved["doubled"] == .number(42))
        #expect(resolved["action"] == .string("active"))
    }

    @Test
    func buttonContractSupportsOptionalLabelsSubtitlesAndValidatedMappings() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.buttons</string>
        <key>title</key><string>Buttons</string><key>description</key><string>Button contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>controls</key><array>
        <dict><key>id</key><string>plain</string><key>subtitle</key><string>Optional help</string><key>type</key><string>button</string><key>defaults</key><dict><key>base</key><false/></dict></dict>
        <dict><key>id</key><string>mapped</string><key>type</key><string>button</string><key>buttonText</key><string>Apply</string><key>buttonIcon</key><string>bolt.fill</string><key>trueValue</key><string>active</string><key>falseValue</key><string>idle</string><key>defaults</key><dict><key>base</key><true/></dict></dict>
        <dict><key>id</key><string>multiple</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>subtitle</key><array><string>First</string><string>Second</string></array><key>buttonText</key><array><string>Previous</string><string>Next</string></array><key>buttonIcon</key><array><string>arrow.left</string><string>arrow.right</string></array><key>activeButtonText</key><array><string>Selected previous</string><string>Selected next</string></array><key>activeButtonIcon</key><array><string>checkmark</string><string>checkmark</string></array><key>trueValue</key><array><string>one</string><string>two</string></array><key>falseValue</key><string>off</string><key>defaults</key><dict><key>base</key><array><true/><false/></array></dict></dict>
        <dict><key>id</key><string>singleChoice</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>selectionMode</key><string>single</string><key>trueValue</key><array><string>first</string><string>second</string></array><key>defaults</key><dict><key>base</key><array><false/><true/></array></dict></dict>
        <dict><key>id</key><string>wrongDefault</string><key>type</key><string>button</string><key>defaults</key><dict><key>base</key><string>no</string></dict></dict>
        <dict><key>id</key><string>wrongMapping</string><key>type</key><string>button</string><key>count</key><integer>2</integer><key>selectionMode</key><string>single</string><key>trueValue</key><array><string>only-one</string></array><key>defaults</key><dict><key>base</key><array><true/><true/></array></dict></dict>
        </array><key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
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
            <dict><key>id</key><string>\(format)</string><key>type</key><string>color</string><key>opacity</key><true/><key>outputFormat</key><string>\(format)</string><key>defaults</key><dict><key>base</key><string>#FF336680</string></dict></dict>
            """
        }.joined()
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.color-formats</string>
        <key>title</key><string>Colour formats</string><key>description</key><string>Colour output contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>controls</key><array>
        \(declarations)
        <dict><key>id</key><string>defaultHex</string><key>type</key><string>color</string><key>defaults</key><dict><key>base</key><string>#FF3366</string></dict></dict>
        <dict><key>id</key><string>opaqueRGBA</string><key>type</key><string>color</string><key>outputFormat</key><string>rgba</string><key>defaults</key><dict><key>base</key><string>#FF3366</string></dict></dict>
        <dict><key>id</key><string>array</string><key>type</key><string>color</string><key>count</key><integer>2</integer><key>outputFormat</key><string>rgbValues</string><key>defaults</key><dict><key>base</key><array><string>#FF3366</string><string>#3366CC</string></array></dict></dict>
        </array><key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
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
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>minimumAPIVersion</key><integer>1</integer>
        <key>id</key><string>com.example.dates</string>
        <key>title</key><string>Dates</string><key>description</key><string>Date contract</string>
        <key>version</key><string>1.0.0</string>
        <key>group</key><string>Other</string><key>assets</key><array/>
        <key>controls</key><array>
        <dict><key>id</key><string>published</string><key>type</key><string>date</string><key>minimum</key><string>2026-01-01</string><key>maximum</key><string>2026-12-31</string><key>defaults</key><dict><key>base</key><string>2026-09-08</string></dict></dict>
        <dict><key>id</key><string>schedule</string><key>type</key><string>date</string><key>count</key><integer>2</integer><key>defaults</key><dict><key>base</key><array><string>2026-10-01</string><string>2026-10-20</string></array></dict></dict>
        </array><key>templates</key><dict><key>html</key><string>part.html</string></dict>
        </dict></plist>
        """
        let data = Data(plist.utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: data).isEmpty)

        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
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

        let invalid = plist.replacingOccurrences(of: "2026-09-08", with: "2026-02-30")
        let invalidManifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(invalid.utf8))
        let diagnostics = PartPackageValidator.validate(invalidManifest, rootURL: FileManager.default.temporaryDirectory)
        #expect(diagnostics.contains { $0.message == "A date control requires a real calendar date using YYYY-MM-DD." })

        let outOfRange = plist.replacingOccurrences(of: "2026-09-08", with: "2027-01-01")
        let outOfRangeManifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(outOfRange.utf8))
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
        let defaultManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(defaultManifest.showsInPartLibrary)

        let hiddenManifestText = validManifest.replacingOccurrences(
            of: "<key>templates</key>",
            with: "<key>showsInPartLibrary</key><false/>\n            <key>templates</key>"
        )
        let hiddenManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(hiddenManifestText.utf8)
        )
        #expect(!hiddenManifest.showsInPartLibrary)
    }

    @Test
    func phpCapabilityForcesPageExtensionWithoutAnInlinePHPTemplate() throws {
        let defaultManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(!defaultManifest.requiresPHP)

        let identifier = "com.example.php\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict><dict><key>path</key><string>server/endpoint.php</string></dict></array>"
            )
            .replacingOccurrences(
                of: "<key>templates</key>",
                with: "<key>requiresPHP</key><true/>\n            <key>templates</key>"
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
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: """
                <key>assets</key><array>
                    <dict><key>path</key><string>images/icon.svg</string></dict>
                    <dict><key>path</key><string>shared/icons</string><key>scope</key><string>site</string></dict>
                </array>
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
                of: "<key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>",
                with: """
                <key>assets</key><array>
                    <dict><key>path</key><string>images/icon.svg</string></dict>
                    <dict><key>path</key><string>shared/icons</string><key>scope</key><string>site</string></dict>
                </array>
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
            manifest: manifest(withControls: "").replacingOccurrences(of: "com.example.card", with: identifier),
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
        <dict>
            <key>id</key><string>itemCount</string>
            <key>label</key><string>Items</string>
            <key>type</key><string>number</string>
            <key>minimum</key><real>0</real>
            <key>maximum</key><real>12</real>
            <key>defaults</key><dict><key>base</key><real>4</real></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
        let validURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ loop control.itemCount reversed }}<b>{{ loop.position }}</b>{{ endloop }}{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: validURL) }
        let package = try PartPackageLoader.load(from: validURL)
        #expect(package.loopMaximums == ["itemCount": 12])

        let invalidURL = try makePackage(
            manifest: manifestText.replacingOccurrences(of: "<key>maximum</key><real>12</real>", with: ""),
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
    func imageControlMayOmitItsDefaultAndResponsiveKeys() throws {
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withControls: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>group</key><string>Content</string>
                    <key>type</key><string>image</string>
                </dict>
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withControls: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>type</key><string>image</string>
                    <key>renditions</key>
                    <array>
                        <dict><key>id</key><string>thumbnail</string><key>maximumDimension</key><integer>480</integer></dict>
                        <dict><key>id</key><string>hero</string><key>maximumDimension</key><integer>5000</integer></dict>
                    </array>
                </dict>
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
            manifest: manifest(withControls: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>type</key><string>image</string>
                    <key>renditions</key><array>
                        <dict><key>id</key><string>thumbnail</string><key>maximumDimension</key><integer>20</integer></dict>
                    </array>
                </dict>
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
            manifest: manifest(withControls: "").replacingOccurrences(of: "com.example.card", with: identifier),
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
            manifest: manifest(withControls: """
                <dict>
                    <key>id</key><string>source</string>
                    <key>label</key><string>Image</string>
                    <key>group</key><string>Content</string>
                    <key>type</key><string>image</string>
                    <key>alt</key><string>Default description</string>
                    <key>focalPoint</key><true/>
                </dict>
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
        let manifestText = manifest(withControls: """
            <dict>
                <key>id</key><string>title</string>
                <key>label</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>defaults</key><dict><key>base</key><string>Hello</string></dict>
                <key>responsive</key><false/>
            </dict>
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
        let validImageManifest = manifest(withControls: """
            <dict>
                <key>id</key><string>source</string>
                <key>label</key><string>Image</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>image</string>
                <key>defaults</key><dict><key>base</key><string>images/icon.svg</string></dict>
            </dict>
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
            of: "<key>defaults</key><dict><key>base</key><string>images/icon.svg</string></dict>",
            with: "<key>defaults</key><dict><key>base</key><string>images/missing.svg</string></dict>"
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let templateURL = packageURL.appending(path: "Contents/Resources/part.html")
        try #"<section id="developer-root" {{ part.attributes }}>{{ childArea("content") }}</section>"#
            .write(to: templateURL, atomically: true, encoding: .utf8)
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let messages = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        ).map(\.message)

        #expect(messages.contains(
            "Separate {{ part.class }} from adjacent class names with literal whitespace."
        ))
    }

    @Test
    func validatorRequiresAllPrimaryHTMLOutputInsideOneStableRoot() throws {
        let invalidTemplates = [
            "Before {{ control.title }}<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>",
            "<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>After",
            "<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section><aside>Sibling</aside>",
            "{{ if control.title }}<section class=\"sample {{ part.class }}\" {{ part.attributes }}></section>{{ endif }}"
        ]
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        for template in invalidTemplates {
            let packageURL = try makePackage(manifest: validManifest, template: template)
            defer { try? FileManager.default.removeItem(at: packageURL) }
            let diagnostics = PartPackageValidator.validate(
                manifest,
                rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
            of: "<key>description</key><string>A test card.</string>",
            with: """
            <key>description</key><string>A test card.</string>
            <key>tags</key>
            <array>
                <string>one</string><string>two</string><string>three</string>
                <string>four</string><string>five</string><string>six</string>
            </array>
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains {
            $0.location == "Info.plist:tags" && $0.message == "A part can declare at most 5 tags."
        })
    }

    @Test
    func loaderProcessesInstanceScopedCSSTemplateFiles() throws {
        let manifest = validManifest.replacingOccurrences(
            of: instanceCSSDeclaration,
            with: """
            <key>files</key>
            <array>
                <dict>
                    <key>path</key><string>instance.css</string>
                    <key>scope</key><string>instance</string>
                </dict>
                <dict>
                    <key>path</key><string>default-scope.css</string>
                </dict>
            </array>
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
            <key>files</key>
            <array>
                <dict><key>path</key><string>part.scss</string><key>scope</key><string>instance</string></dict>
            </array>
            """
        )
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.scss": ":host {}"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains(where: { $0.message.contains("support CSS, JavaScript, PHP and placed HTML") }))
    }

    @Test
    func loaderProcessesScopedJavaScriptTemplates() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.js</string><key>scope</key><string>instance</string></dict>
            <dict><key>path</key><string>page.js</string><key>scope</key><string>page</string><key>closure</key><false/></dict>
        </array>
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
        <key>files</key>
        <array>
            <dict><key>path</key><string>site.js</string><key>scope</key><string>site</string></dict>
            <dict><key>path</key><string>site.php</string><key>scope</key><string>site</string></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "<key>templates</key>", with: "<key>requiresPHP</key><true/>\n            <key>templates</key>")
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
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.filter { $0.message == "Site scope is available only to CSS templates." }.count == 2)
    }

    @Test
    func staticRendererConnectsInstanceJavaScriptToItsPartElement() throws {
        let identifier = "com.example.javascript\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.js</string><key>scope</key><string>instance</string></dict>
        </array>
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
            of: "<key>minimumAPIVersion</key>",
            with: "<key>anchor</key><true/>\n            <key>minimumAPIVersion</key>"
        )
        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifestText.utf8))

        #expect(diagnostics.contains { $0.location == "Info.plist:anchor" && $0.message.contains("Unknown key") })
    }

    @Test
    func loaderProcessesScopedPHPTemplatesIntoExportedPagePrelude() throws {
        let identifier = "com.example.phptemplates\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let declaration = """
        <key>files</key>
        <array>
            <dict><key>path</key><string>instance.php</string><key>scope</key><string>instance</string></dict>
            <dict><key>path</key><string>page.php</string><key>scope</key><string>page</string></dict>
        </array>
        """
        let manifestText = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: "<key>templates</key>", with: "<key>requiresPHP</key><true/>\n            <key>templates</key>")
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
        <key>files</key>
        <array><dict><key>path</key><string>part.php</string></dict></array>
        """
        let manifestText = validManifest.replacingOccurrences(of: instanceCSSDeclaration, with: declaration)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>",
            additionalFiles: ["part.php": "<?php return; ?>"]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifestText.utf8))

        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains { $0.location == "Info.plist:requiresPHP" })
    }

    @Test
    func textAlignmentSpecializedControlProvidesValidatedLogicalValues() throws {
        let item = """
        <dict>
            <key>id</key><string>alignment</string>
            <key>label</key><string>Alignment</string>
            <key>group</key><string>Typography</string>
            <key>type</key><string>textAlignment</string>
            <key>defaults</key><dict><key>base</key><string>start</string></dict>
            <key>responsive</key><true/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
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
        let manifestText = validManifest.replacingOccurrences(
            of: "<key>group</key><string>Content</string>",
            with: ""
        )

        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )

        #expect(manifest.resolvedProperties.first?.group == "Settings")
    }

    @Test
    func multiSelectRejectsFrameworkValues() throws {
        let item = """
        <dict>
            <key>id</key><string>sizes</string>
            <key>label</key><string>Font sizes</string>
            <key>type</key><string>select</string>
            <key>frameworkValues</key><string>fontSizes</string>
            <key>count</key><integer>2</integer>
            <key>defaults</key><dict><key>base</key><array><string>base</string><string>base</string></array></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifest(withControls: item).utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: FileManager.default.temporaryDirectory
        )

        #expect(diagnostics.contains {
            $0.location == "Info.plist:controls.sizes.frameworkValues" &&
                $0.message == "Select supports only declared options; remove frameworkValues."
        })
    }

    @Test
    func numberControlUnitsAreOptionalAndLimitedToThreeCharacters() throws {
        let numberItem = """
        <dict>
            <key>id</key><string>spacing</string>
            <key>label</key><string>Spacing</string>
            <key>type</key><string>number</string>
            <key>defaults</key><dict><key>base</key><real>12</real></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: numberItem)
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(manifestText.utf8)
        )
        let property = try #require(manifest.resolvedProperties.first)
        #expect(property.units == [""])

        let invalidText = manifestText.replacingOccurrences(
            of: "<key>type</key><string>number</string>",
            with: "<key>type</key><string>number</string><key>units</key><string>pixels</string>"
        )
        let invalidManifest = try PropertyListDecoder().decode(
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
        <dict>
            <key>id</key><string>opacity</string>
            <key>label</key><string>Opacity</string>
            <key>type</key><string>slider</string>
            <key>minimum</key><real>0</real>
            <key>maximum</key><real>100</real>
            <key>ticks</key><integer>11</integer>
            <key>units</key><string>%</string>
            <key>defaults</key><dict><key>base</key><real>50</real></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: sliderItem)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ part.attributes }}>{{ control.opacity }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .slider(let range, let step, let ticks, let unit, let showsValueField) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(range == 0...100)
        #expect(step == 0)
        #expect(ticks == 11)
        #expect(unit == "%")
        #expect(showsValueField)
    }

    @Test
    func multiSliderSupportsOneDisplayUnitPerValue() throws {
        let item = """
        <dict>
            <key>id</key><string>dimensions</string>
            <key>label</key><string>Dimensions</string>
            <key>type</key><string>slider</string>
            <key>count</key><integer>3</integer>
            <key>units</key>
            <array><string>px</string><string>rem</string><string>%</string></array>
            <key>defaults</key><dict><key>base</key><array><real>20</real><real>4</real><real>80</real></array></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
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
            <dict>
                <key>id</key><string>slider</string>
                <key>label</key><string>Slider</string>
                <key>type</key><string>slider</string>
                <key>minimum</key><real>\(testCase.minimum)</real>
                <key>maximum</key><real>\(testCase.maximum)</real>
                <key>responsive</key><false/>
            </dict>
            """
            let manifestText = manifest(withControls: item)
            #expect(throws: (any Error).self) {
                try PropertyListDecoder().decode(PartPackageManifest.self, from: Data(manifestText.utf8))
            }
        }
    }

    @Test
    func sliderCanHideItsValueField() throws {
        let item = """
        <dict>
            <key>id</key><string>slider</string>
            <key>label</key><string>Slider</string>
            <key>type</key><string>slider</string>
            <key>showsValueField</key><false/>
            <key>defaults</key><dict><key>base</key><integer>0</integer></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
        let packageURL = try makePackage(
            manifest: manifestText,
            template: "<output {{ part.attributes }}>{{ control.slider }}{{ childArea(\"content\") }}</output>"
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let package = try PartPackageLoader.load(from: packageURL)
        let property = try #require(PartPackageAdapter.definition(from: package).properties.first)
        guard case .slider(_, _, _, _, let showsValueField) = property.control else {
            Issue.record("Expected a slider control")
            return
        }

        #expect(!showsValueField)
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
        <dict>
            <key>id</key><string>slider</string>
            <key>label</key><string>Slider</string>
            <key>type</key><string>slider</string>
            <key>minimum</key><real>10</real>
            <key>maximum</key><real>10</real>
            <key>step</key><real>-1</real>
            <key>ticks</key><integer>1</integer>
            <key>units</key><string>pixels</string>
            <key>defaults</key><dict><key>base</key><real>10</real></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
        let manifest = try PropertyListDecoder().decode(
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
    func dividerCustomControlIsPresentationOnly() throws {
        let item = """
        <dict>
            <key>id</key><string>contentDivider</string>
            <key>group</key><string>Content</string>
            <key>type</key><string>divider</string>
        </dict>
        """
        let manifestText = manifest(withControls: item)
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
            rootURL: invalidPackageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )
        #expect(diagnostics.contains { $0.message.contains("Unknown property 'contentDivider'") })

        let unsupportedKeys = ["label", "subtitle", "tooltip", "default", "responsive", "count"]
        for key in unsupportedKeys {
            let value: String
            switch key {
            case "responsive": value = "<true/>"
            case "count": value = "<integer>2</integer>"
            default: value = "<string>Unsupported</string>"
            }
            let invalidItem = """
            <dict>
                <key>id</key><string>divider</string>
                <key>type</key><string>divider</string>
                <key>\(key)</key>\(value)
            </dict>
            """
            let schemaDiagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withControls: invalidItem).utf8)
            )
            #expect(schemaDiagnostics.contains { $0.severity == .error })
        }
    }

    @Test
    func noteCustomControlUsesDedicatedContentKeys() throws {
        let validItem = """
        <dict>
            <key>id</key><string>guidance</string>
            <key>type</key><string>note</string>
            <key>title</key><string>About this setting</string>
            <key>body</key><string>Helpful guidance.</string>
            <key>systemImage</key><string>info.circle</string>
        </dict>
        """
        let validData = Data(manifest(withControls: validItem).utf8)
        #expect(try PartPackageManifestSchema.diagnostics(for: validData).isEmpty)

        let decodedManifest = try PropertyListDecoder().decode(PartPackageManifest.self, from: validData)
        let property = try #require(decodedManifest.resolvedProperties.first)
        #expect(property.noteTitle == "About this setting")
        #expect(property.noteBody == "Helpful guidance.")
        #expect(property.noteSystemImage == "info.circle")
        #expect(property.label.isEmpty)
        #expect(property.subtitles.isEmpty)
        #expect(!property.responsive)
        #expect(property.control.count == nil)

        let unsupportedKeys = ["label", "subtitle", "responsive", "count"]
        for key in unsupportedKeys {
            let value = switch key {
            case "responsive": "<true/>"
            case "count": "<integer>2</integer>"
            default: "<string>Unsupported</string>"
            }
            let item = """
            <dict>
                <key>id</key><string>guidance</string>
                <key>type</key><string>note</string>
                <key>body</key><string>Helpful guidance.</string>
                <key>\(key)</key>\(value)
            </dict>
            """

            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withControls: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "Info.plist:controls[0]:\(key)" &&
                    $0.message == "A note control does not support \(key)."
            })
        }

        let missingBodyItem = """
        <dict>
            <key>id</key><string>guidance</string>
            <key>type</key><string>note</string>
        </dict>
        """
        let missingBodyDiagnostics = try PartPackageManifestSchema.diagnostics(
            for: Data(manifest(withControls: missingBodyItem).utf8)
        )
        #expect(missingBodyDiagnostics.contains {
            $0.location == "Info.plist:controls[0]:body" &&
                $0.message == "A body string is required."
        })
    }

    @Test
    func linkControlRejectsCountAndResponsive() throws {
        for key in ["count", "responsive"] {
            let value = key == "count" ? "<integer>2</integer>" : "<true/>"
            let item = """
            <dict>
                <key>id</key><string>destination</string>
                <key>type</key><string>link</string>
                <key>label</key><string>Destination</string>
                <key>defaults</key><dict><key>base</key><string></string></dict>
                <key>\(key)</key>\(value)
            </dict>
            """

            let diagnostics = try PartPackageManifestSchema.diagnostics(
                for: Data(manifest(withControls: item).utf8)
            )

            #expect(diagnostics.contains {
                $0.location == "Info.plist:controls[0]:\(key)" &&
                    $0.message == "A link control does not support \(key)."
            })
        }
    }

    @Test
    func loaderProcessesPageScopedHTMLPlacements() throws {
        let declaration = """
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>head.html</string>
                <key>scope</key><string>page</string>
                <key>placement</key><string>headEnd</string>
            </dict>
            <dict>
                <key>path</key><string>body.html</string>
                <key>scope</key><string>page</string>
                <key>placement</key><string>bodyEnd</string>
            </dict>
        </array>
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
        <key>files</key>
        <array>
            <dict><key>path</key><string>site.css</string><key>scope</key><string>site</string></dict>
        </array>
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
        <key>files</key>
        <array>
            <dict><key>path</key><string>page.css</string><key>scope</key><string>page</string></dict>
        </array>
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
            .replacingOccurrences(of: "<key>label</key><string>Content</string>", with: "<key>label</key><string>Cards</string>")
            .replacingOccurrences(
                of: "<key>accepts</key><array><string>*</string></array>",
                with: "<key>accepts</key><array><string>foundry.content.paragraph</string></array><key>initial</key><array><string>foundry.content.paragraph</string></array><key>minimum</key><integer>1</integer><key>maximum</key><integer>2</integer><key>containment</key><string>locked</string>"
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
        let acceptsDeclaration = "<key>accepts</key><array><string>*</string></array>"

        let grandchildURL = try makePackage(
            manifest: validManifest.replacingOccurrences(of: "com.example.card", with: grandchildIdentifier),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: grandchildURL) }
        let grandchildPackage = try PartPackageLoader.load(from: grandchildURL)
        PartRegistry.register(grandchildPackage)
        defer { PartRegistry.unregisterPackage(identifier: grandchildIdentifier) }

        let childInitial = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(grandchildIdentifier)</string></array>
        <key>initial</key>
        <array>
            <string>\(grandchildIdentifier)</string>
            <string>\(grandchildIdentifier)</string>
        </array>
        """
        let childURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: childIdentifier)
                .replacingOccurrences(of: acceptsDeclaration, with: childInitial),
            template: "<section {{ part.attributes }}>{{ childArea(\"content\") }}</section>"
        )
        defer { try? FileManager.default.removeItem(at: childURL) }
        let childPackage = try PartPackageLoader.load(from: childURL)
        PartRegistry.register(childPackage)
        defer { PartRegistry.unregisterPackage(identifier: childIdentifier) }

        let parentInitial = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(childIdentifier)</string></array>
        <key>initial</key>
        <array>
            <string>\(childIdentifier)</string>
            <string>\(grandchildIdentifier)</string>
            <string>\(childIdentifier)</string>
        </array>
        """
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
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
        let acceptsDeclaration = "<key>accepts</key><array><string>*</string></array>"
        let pickerDeclaration = """
        \(acceptsDeclaration)
        <key>pickerItems</key>
        <array><string>\(childIdentifier)</string></array>
        """
        let parentURL = try makePackage(
            manifest: validManifest
                .replacingOccurrences(of: "com.example.card", with: parentIdentifier)
                .replacingOccurrences(of: acceptsDeclaration, with: pickerDeclaration),
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
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>initial</key><integer>2</integer>"
        )
        let invalidValues = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>com.example.child</string></array><key>pickerItems</key><array><string>Invalid</string><string>com.example.child</string></array><key>initial</key><array><string>com.example.child</string><string>com.example.other</string></array><key>maximum</key><integer>1</integer>"
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
        let openManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        #expect(openManifest.slots.first?.containment == .open)

        let lockedText = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>containment</key><string>locked</string>"
        )
        let lockedManifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(lockedText.utf8)
        )
        #expect(lockedManifest.slots.first?.containment == .locked)
    }

    @Test
    func childPickerAddPresentationIsOwnedByFoundry() throws {
        let manifest = validManifest.replacingOccurrences(
            of: "<key>accepts</key><array><string>*</string></array>",
            with: "<key>accepts</key><array><string>*</string></array><key>buttonText</key><string>Add Card</string>"
        )

        let diagnostics = try PartPackageManifestSchema.diagnostics(for: Data(manifest.utf8))

        #expect(diagnostics.contains {
            $0.location.contains("buttonText")
                && $0.message == "A childPicker control does not support buttonText."
        })
    }

    @Test
    func dropZoneCreatesAnOrdinaryUnslottedChildArea() throws {
        let identifier = "com.example.drop-zone-parent"
        let manifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: identifier)
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
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
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
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
            .replacingOccurrences(of: defaultCustomItemsDeclaration, with: "")
        let childManifest = validManifest
            .replacingOccurrences(of: "com.example.card", with: childIdentifier)
            .replacingOccurrences(
                of: "<key>title</key><string>Card</string>",
                with: "<key>title</key><string>Card</string><key>allowedParents</key><array><string>\(parentIdentifier)</string></array>"
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
            definition.package.map { FoundryPackLoader.isPackURL($0.rootURL) } == true
        })
        #expect(Set(builtIns.compactMap { $0.package?.manifest.identifier }).count == builtIns.count)
        #expect(PartType.image.definition.package?.manifest.identifier == PartType.image.rawValue)
        #expect(PartType.section.definition.package?.manifest.identifier == PartType.section.rawValue)
        let imageSlider = try #require(builtIns.first {
            $0.type.rawValue == "foundry.media.imageslider"
        })
        #expect(imageSlider.package?.loopMaximums["slideCount"] == 8)
        #expect(imageSlider.properties.filter {
            if case .image = $0.control { return true }
            return false
        }.map(\.key.rawValue) == (1...8).map { "slide-\($0)" })
        #expect(PartType.section.definition.allowsChildren)
        #expect(!PartType.section.definition.properties.contains { $0.key.rawValue == "contentWidth" })
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "frameworkPadding" })
        #expect(PartType.section.definition.properties.contains { $0.key.rawValue == "frameworkMargin" })
        #expect(PartType.image.definition.properties.contains { $0.key == .source && $0.isInspectorVisible })
        #expect(PartType.image.definition.properties.contains {
            $0.key.rawValue == "maxWidth" && $0.defaultValue == .number(1200) && $0.isResponsive
        })
        #expect(PartType.image.definition.properties.contains {
            $0.key.rawValue == "alignment" && $0.defaultValue == .choice("center") && $0.isResponsive
        })
        let bundledIdentifiers = Set(bundledPackages.map(\.manifest.identifier))
        #expect(bundledIdentifiers.isSubset(of: Set(PartType.allCases.map(\.rawValue))))
        let html = try #require(catalog.packages["foundry.content.html"])
        let htmlDefinition = PartPackageAdapter.definition(from: html)
        #expect(htmlDefinition.properties.contains { $0.key.rawValue == "content" && !$0.isInspectorVisible })
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
        let cssURL = packageURL.appending(path: "Contents/Resources/part.css")
        let originalCSS = try Data(contentsOf: cssURL)
        let package = try PartPackageLoader.loadForCatalog(from: packageURL, validates: false).package
        try FileManager.default.removeItem(at: cssURL)

        #expect(throws: PartPackagePayloadFailure.self) {
            try package.preparePayload()
        }
        #expect(!package.isPayloadLoaded)
        #expect(package.payloadFailure?.location == "Contents/Resources/part.css")

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

    @Test
    func packDiscoveryRecursesThroughFunctionalAndCollectionPacksWithoutFlattening() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        let nested = root.appending(path: "Nested.foundrypack", directoryHint: .isDirectory)
        let deeplyNested = nested.appending(path: "Deep.foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try writePackHeader(isCollection: true, at: root)
        try writePackHeader(identifier: "com.example.nested", at: nested)
        try writePackHeader(identifier: "com.example.deep", at: deeplyNested)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root, deeplyNested, nested].map(\.standardizedFileURL).sorted { $0.path < $1.path })
        #expect(try FoundryPackLoader.load(from: root).isCollection)
        #expect(!(try FoundryPackLoader.load(from: nested).isCollection))
        #expect(deeplyNested.path.hasPrefix(nested.path))
    }

    @Test
    func developmentPacksUseTheSameLoaderAndParticipateInRecursiveDiscovery() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrydevpack", directoryHint: .isDirectory)
        let nested = root.appending(path: "Nested.foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(isCollection: true, at: root)
        try writePackHeader(identifier: "com.example.development.child", at: nested)

        let urls = FoundryPackLoader.packURLs(in: root, includingRoot: true)

        #expect(urls.map(\.standardizedFileURL) == [root, nested].map(\.standardizedFileURL).sorted { $0.path < $1.path })
        #expect(try FoundryPackLoader.load(from: root).identifier == nil)
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
        let data = try PropertyListSerialization.data(fromPropertyList: legacyManifest, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))

        #expect(throws: FoundryPackLoadingError.self) {
            try FoundryPackLoader.load(from: root)
        }
    }

    @Test
    func manifestSchemaRejectsUnknownKeysUnsupportedAPIsAndInvalidVersions() throws {
        let cases: [(manifest: String, expected: String)] = [
            (
                validManifest.replacingOccurrences(
                    of: "<key>title</key>",
                    with: "<key>titel</key><string>Typo</string><key>title</key>"
                ),
                "Unknown key 'titel'"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>minimumAPIVersion</key><integer>1</integer>",
                    with: "<key>minimumAPIVersion</key><integer>999</integer>"
                ),
                "requires Foundry part API 999"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>version</key><string>1.0.0</string>",
                    with: "<key>version</key><string>1.0</string>"
                ),
                "MAJOR.MINOR.PATCH"
            ),
            (
                validManifest.replacingOccurrences(
                    of: "<key>version</key><string>1.0.0</string>",
                    with: "<key>version</key><string>1.0.0-01</string>"
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
    func collectionManifestSupportsOptionalUpdateMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).foundrypack", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackHeader(isCollection: true, at: root)
        #expect(try FoundryPackLoader.load(from: root).isCollection)

        let updateEnabled: [String: Any] = [
            "collection": true,
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
        let updateData = try PropertyListSerialization.data(fromPropertyList: updateEnabled, format: .xml, options: 0)
        try updateData.write(to: root.appending(path: "Contents/Info.plist"))
        let updatePack = try FoundryPackLoader.load(from: root)
        #expect(updatePack.identifier == "com.example.collection")
        #expect(updatePack.metadata.version == "1.2.3")
        #expect(updatePack.metadata.updates?.appcastURL.absoluteString == "https://example.com/appcast.json")

        let invalid: [String: Any] = ["collection": true, "unexpected": "value"]
        let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        try data.write(to: root.appending(path: "Contents/Info.plist"))
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
                of: "<key>templates</key>",
                with: """
                <key>libraries</key>
                <array><dict>
                    <key>id</key><string>bootstrapIcons</string>
                    <key>majorVersion</key><integer>1</integer>
                </dict></array>
                <key>templates</key>
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
        <dict>
            <key>id</key><string>symbol</string>
            <key>label</key><string>Icon</string>
            <key>group</key><string>Content</string>
            <key>type</key><string>icon</string>
            <key>defaults</key><dict><key>base</key><string>stars</string></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifest = manifest(withControls: item)
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
    func iconControlAutomaticallyIncludesItsLibraryAndRequiresAValidDefault() throws {
        let item = """
        <dict>
            <key>id</key><string>symbol</string>
            <key>label</key><string>Icon</string>
            <key>type</key><string>icon</string>
            <key>defaults</key><dict><key>base</key><string>not-a-real-foundry-icon</string></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let manifestText = manifest(withControls: item)
        let manifest = try PropertyListDecoder().decode(
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
        <dict>
            <key>type</key><string>icon</string>
            <key>id</key><string>icons</string>
            <key>label</key><string>Icons</string>
            <key>count</key><integer>2</integer>
            <key>subtitle</key>
            <array><string>Previous</string><string>Next</string></array>
            <key>defaults</key><dict><key>base</key><array><string>arrow-left</string><string>not-a-real-foundry-icon</string></array></dict>
        </dict>
        """
        let manifestText = manifest(withControls: item)
        let manifest = try PropertyListDecoder().decode(
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
        let resources = root.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
        let resources = root.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let sourceFile = resources.appending(path: "part.css")
        let childPack = resources.appending(path: "Child.foundrypack", directoryHint: .isDirectory)
        let childFile = childPack.appending(path: "Contents/Resources/child.css")
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
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>minimumAPIVersion</key><integer>1</integer>
            <key>id</key><string>com.example.card</string>
            <key>title</key><string>Card</string>
            <key>version</key><string>1.0.0</string>
            <key>description</key><string>A test card.</string>
            <key>group</key><string>Content part</string>
            \(defaultCustomItemsDeclaration)
            <key>templates</key>
            <dict>
                <key>html</key><string>part.html</string>
                \(instanceCSSDeclaration)
            </dict>
            <key>assets</key><array><dict><key>path</key><string>images/icon.svg</string></dict></array>
        </dict>
        </plist>
        """
    }

    private var defaultCustomItemsDeclaration: String {
        """
        <key>controls</key>
        <array>
            <dict>
                <key>id</key><string>title</string>
                <key>label</key><string>Title</string>
                <key>group</key><string>Content</string>
                <key>type</key><string>text</string>
                <key>defaults</key><dict><key>base</key><string>Hello</string></dict>
                <key>responsive</key><false/>
            </dict>
            <dict>
                <key>type</key><string>childPicker</string>
                <key>id</key><string>content</string>
                <key>label</key><string>Content</string>
                <key>pickerItems</key><array><string>com.example.child</string></array>
                <key>accepts</key><array><string>*</string></array>
            </dict>
        </array>
        """
    }

    @Test
    func manifestDecodeFailureNamesTheFailingSpot() throws {
        let item = """
        <dict>
            <key>id</key><string>cardShadow</string>
            <key>label</key><string>Shadow</string>
            <key>type</key><string>shadow</string>
            <key>defaults</key><dict><key>base</key><string>md</string></dict>
            <key>responsive</key><false/>
        </dict>
        """
        let data = Data(manifest(withControls: item).utf8)
        let error = #expect(throws: (any Error).self) {
            try PropertyListDecoder().decode(PartPackageManifest.self, from: data)
        }
        let message = PartPackageLoadingError
            .unreadableManifest(try #require(error))
            .errorDescription ?? ""
        // A renamed control type must be identifiable from the error alone:
        // the invalid value and the plist location, not "isn't in the correct format".
        #expect(message.contains("shadow"), Comment(rawValue: message))
        #expect(message.contains("controls[0]"), Comment(rawValue: message))
    }

    @Test
    func inspectorGroupIconsResolveFromGroupsAndGroupedControls() throws {
        let controls = """
        <dict>
            <key>id</key><string>galleryStyle</string>
            <key>label</key><string>Style</string>
            <key>group</key><string>Gallery</string>
            <key>type</key><string>toggle</string>
            <key>defaults</key><dict><key>base</key><true/></dict>
            <key>responsive</key><false/>
        </dict>
        <dict><key>type</key><string>spacing</string></dict>
        """
        func source(groups: String) -> Data {
            Data(manifest(withControls: controls).replacingOccurrences(
                of: "<key>controls</key>",
                with: "<key>groups</key>\n<array>\n\(groups)\n</array>\n<key>controls</key>"
            ).utf8)
        }

        let valid = source(groups: """
        <dict><key>name</key><string>Gallery</string><key>systemImage</key><string>photo.stack</string></dict>
        <dict><key>name</key><string>Content</string><key>systemImage</key><string>doc.text</string></dict>
        """)
        #expect(try PartPackageManifestSchema.diagnostics(for: valid).allSatisfy { !$0.location.contains("groups") })
        let decoded = try PropertyListDecoder().decode(PartPackageManifest.self, from: valid)
        #expect(decoded.groups == [
            .init(name: "Gallery", systemImage: "photo.stack"),
            .init(name: "Content", systemImage: "doc.text")
        ])
        #expect(decoded.resolvedGroupIcons["Gallery"] == "photo.stack")
        // Grouped controls carry their standard section icon with no declaration.
        #expect(decoded.resolvedGroupIcons["Spacing"] == "arrow.up.and.down.and.arrow.left.and.right")
        // Undeclared groups fall back at presentation time, not in the manifest.
        #expect(decoded.resolvedGroupIcons["Settings"] == nil)
        let reencoded = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: PropertyListEncoder().encode(decoded)
        )
        #expect(reencoded.groups == decoded.groups)
        #expect(reencoded.resolvedGroupIcons == decoded.resolvedGroupIcons)

        let failures: [(entries: String, message: String)] = [
            ("<dict><key>name</key><string>Gallery</string></dict><dict><key>name</key><string>Gallery</string></dict>",
             "Duplicate group entry 'Gallery'."),
            ("<dict><key>name</key><string>Sidebar</string></dict>",
             "groups declares 'Sidebar' but no control uses that group."),
            ("<dict><key>name</key><string>Gallery</string><key>icon</key><string>star</string></dict>",
             "Unknown key 'icon'. Check the spelling or remove it."),
            ("<dict><key>name</key><string> </string></dict>",
             "A group entry requires a non-empty name."),
            ("<dict><key>systemImage</key><string>star</string></dict>",
             "A name string is required.")
        ]
        for failure in failures {
            let diagnostics = try PartPackageManifestSchema.diagnostics(for: source(groups: failure.entries))
            #expect(diagnostics.contains { $0.message.contains(failure.message) }, Comment(rawValue: failure.message))
        }
    }

    private func manifest(withControls items: String) -> String {
        let replacement = """
        <key>controls</key>
        <array>
            \(items)
            <dict>
                <key>type</key><string>childPicker</string>
                <key>id</key><string>content</string>
                <key>label</key><string>Content</string>
                <key>pickerItems</key><array><string>com.example.child</string></array>
                <key>accepts</key><array><string>*</string></array>
            </dict>
        </array>
        """
        return validManifest.replacingOccurrences(of: defaultCustomItemsDeclaration, with: replacement)
    }

    private var instanceCSSDeclaration: String {
        """
        <key>files</key>
        <array>
            <dict>
                <key>path</key><string>part.css</string>
                <key>scope</key><string>instance</string>
            </dict>
        </array>
        """
    }

    @Test
    func partIconCannotExceedMaximumFileSize() throws {
        let oversizedIcon = "<svg>" + String(
            repeating: " ",
            count: PartPackageValidator.maximumIconByteCount
        ) + "</svg>"
        let packageURL = try makePackage(
            manifest: validManifest,
            template: "<div {{ part.attributes }}>{{ childArea(\"content\") }}</div>",
            additionalFiles: ["icon.svg": oversizedIcon]
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = try PropertyListDecoder().decode(
            PartPackageManifest.self,
            from: Data(validManifest.utf8)
        )
        let diagnostics = PartPackageValidator.validate(
            manifest,
            rootURL: packageURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        )

        #expect(diagnostics.contains { $0.location == "icon.svg" && $0.message.contains("64 KiB") })
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
        let resourcesURL = rootURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
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
            "images/icon.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
        ].merging(additionalFiles) { _, additional in additional }
        try Data(manifest.utf8).write(to: rootURL.appending(path: "Contents/Info.plist"))
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
        isCollection: Bool = false,
        identifier: String = "com.example.part",
        at rootURL: URL
    ) throws {
        let contentsURL = rootURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = isCollection
            ? ["collection": true]
            : ["id": identifier]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
    }
}
