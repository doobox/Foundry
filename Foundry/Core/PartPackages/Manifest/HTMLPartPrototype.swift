import CryptoKit
import Foundation
import Synchronization

/// Project-local source compiled through the ordinary package schema and adapter.
/// Only source changes invalidate this cache; Inspector value changes do not.
nonisolated enum HTMLPartPrototype {
    static let controlsKey = PartProperty.Key(rawValue: "htmlPrototypeControls")
    static let contentKey = PartProperty.Key(rawValue: "content")
    static let pageCSSKey = PartProperty.Key(rawValue: "htmlPrototypePageCSS")
    static let siteCSSKey = PartProperty.Key(rawValue: "htmlPrototypeSiteCSS")
    static let pageJavaScriptKey = PartProperty.Key(rawValue: "htmlPrototypePageJavaScript")
    static let sourceKeys: Set<PartProperty.Key> = [controlsKey, pageCSSKey, siteCSSKey, pageJavaScriptKey]

    struct Compilation: Sendable {
        let definition: PartDefinition?
        let diagnostics: [PartPackageDiagnostic]
    }

    private static let cache = Mutex<[HTMLPartSource: Compilation]>([:])

    static func definition(for node: PartNode) -> PartDefinition {
        let base = node.type.definition
        guard node.type == .html, let package = base.package else { return base }
        let html = node.storedPropertyValue(contentKey)?.stringValue
            ?? base.property(for: contentKey)?.defaultValue.stringValue ?? ""
        return compile(source: .init(
            html: html,
            css: node.storedPropertyValue(PartPackageAdapter.htmlCSSKey(for: "content"))?.stringValue ?? "",
            javaScript: node.storedPropertyValue(PartPackageAdapter.htmlJavaScriptKey(for: "content"))?.stringValue ?? "",
            controls: node.storedPropertyValue(controlsKey)?.stringValue ?? "[]",
            pageCSS: node.storedPropertyValue(pageCSSKey)?.stringValue ?? "",
            siteCSS: node.storedPropertyValue(siteCSSKey)?.stringValue ?? "",
            pageJavaScript: node.storedPropertyValue(pageJavaScriptKey)?.stringValue ?? ""),
            base: base, package: package
        ).definition ?? base
    }

    static func compile(html: String, css: String, javaScript: String, controls: String) -> Compilation {
        compile(source: .init(html: html, css: css, javaScript: javaScript, controls: controls))
    }

    static func compile(source: HTMLPartSource) -> Compilation {
        let base = PartType.html.definition
        guard let package = base.package else {
            return .init(definition: nil, diagnostics: [.init(severity: .error, location: "HTML", message: "The HTML part is not loaded yet.")])
        }
        return compile(source: source, base: base, package: package)
    }

    private static func compile(source: HTMLPartSource, base: PartDefinition, package: LoadedPartPackage) -> Compilation {
        let key = source
        if let result = cache.withLock({ $0[key] }) { return result }
        let sourceData = (try? JSONEncoder().encode([source.html, source.css, source.javaScript, source.controls ?? "[]", source.pageCSS, source.siteCSS, source.pageJavaScript])) ?? Data()
        let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        let result = build(source: source, identifier: "project.html.p" + digest, base: base, package: package)
        cache.withLock {
            if $0.count >= 128 { $0.removeAll(keepingCapacity: true) }
            $0[key] = result
        }
        return result
    }

    private static func build(source: HTMLPartSource, identifier: String, base: PartDefinition, package: LoadedPartPackage) -> Compilation {
        let html = source.html
        let css = source.css
        let javaScript = source.javaScript
        let controls = source.controls ?? "[]"
        do {
            let declaration = controls.trimmingCharacters(in: .whitespacesAndNewlines)
            let inspector = try JSONSerialization.jsonObject(with: Data((declaration.isEmpty ? "[]" : declaration).utf8))
            guard inspector is [Any] else {
                return .init(definition: nil, diagnostics: [.init(severity: .error, location: "Controls", message: "Use an array of Inspector controls and sections, as in a manifest's inspector field.")])
            }
            let template = editorTemplate(html)
            var files: [[String: String]] = []
            if !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files.append(["path": "prototype.css", "scope": "instance"]) }
            if !javaScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files.append(["path": "prototype.js", "scope": "instance"]) }
            if !source.pageCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files.append(["path": "page.css", "scope": "page"]) }
            if !source.siteCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files.append(["path": "site.css", "scope": "site"]) }
            if !source.pageJavaScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files.append(["path": "page.js", "scope": "page"]) }
            let manifestData = try JSONSerialization.data(withJSONObject: [
                "id": identifier, "title": "HTML", "version": "1.0.0", "minimumAPIVersion": FoundryPartAPI.currentVersion,
                "group": "Content", "assets": [], "libraries": [],
                "templates": ["html": "prototype.html", "files": files],
                "inspector": inspector
            ])
            let prepared = try PartPackageManifestSchema.preparingControls(in: manifestData)
            var diagnostics = prepared.warnings + (try PartPackageManifestSchema.validatePreparedData(prepared.data))
            guard !diagnostics.contains(where: { $0.severity == .error }) else { return .init(definition: nil, diagnostics: diagnostics) }
            let manifest = try JSONDecoder().decode(PartPackageManifest.self, from: prepared.data)
            diagnostics += PartPackageValidator.validate(manifest, rootURL: package.rootURL, sourceFiles: ["prototype.html": template, "prototype.css": css, "prototype.js": javaScript, "page.css": source.pageCSS, "site.css": source.siteCSS, "page.js": source.pageJavaScript])
            let reservedKeys = Set(base.properties.map(\.key)).union(sourceKeys)
            for property in manifest.resolvedProperties where reservedKeys.contains(.init(rawValue: property.id)) {
                diagnostics.append(.init(severity: .error, location: "Controls", message: "'\(property.id)' is reserved for the HTML source editor. Choose another control ID."))
            }
            guard !diagnostics.contains(where: { $0.severity == .error }) else { return .init(definition: nil, diagnostics: diagnostics) }
            let compiled = LoadedPartPackage(manifest: manifest, rootURL: package.rootURL, htmlTemplate: template, css: css, pageCSS: source.pageCSS, siteCSS: source.siteCSS, placedHTML: [], instanceJavaScript: javaScript, pageJavaScript: source.pageJavaScript, instancePHP: "", pagePHP: "", editorCSS: "", updateSourceURL: nil, imageMetadata: [:])
            if html.range(of: #"\{\{\s*part\.attributes\s*\}\}"#, options: .regularExpression) == nil,
               [css, compiled.renderDefinition.controlGroupCSS].contains(where: { $0.contains(":instance") || $0.contains(":host") }) {
                diagnostics.append(.init(severity: .warning, location: "HTML", message: "Instance styling needs an authored root with class=\"{{ part.class }}\" and {{ part.attributes }}. The automatic editing wrapper is not published."))
            }
            let adapted = PartPackageAdapter.definition(from: compiled)
            for property in adapted.properties where reservedKeys.contains(property.key) {
                diagnostics.append(.init(severity: .error, location: "HTML", message: "'\(property.key.rawValue)' is reserved for the source editor. Choose another primitive name."))
            }
            guard !diagnostics.contains(where: { $0.severity == .error }) else { return .init(definition: nil, diagnostics: diagnostics) }
            let keys = Set(adapted.properties.map(\.key))
            let definition = PartDefinition(type: .html, displayName: base.displayName, systemImage: base.systemImage, category: base.category, allowsChildren: adapted.allowsChildren, renderKind: .package, properties: adapted.properties + base.properties.filter { !keys.contains($0.key) }, package: compiled, inspectorRows: adapted.inspectorRows)
            return .init(definition: definition, diagnostics: diagnostics)
        } catch {
            return .init(definition: nil, diagnostics: [.init(severity: .error, location: "Controls", message: error.localizedDescription)])
        }
    }

    private static func editorTemplate(_ html: String) -> String {
        let editorAttributes = " data-foundry-inline-property=\"content\" data-foundry-inline-html data-foundry-inline-source=\"\(Data(html.utf8).base64EncodedString())\""
        // An authored component root uses the ordinary package hooks. Plain HTML
        // remains wrapper-free outside the canvas, including multiple siblings.
        if html.range(of: #"\{\{\s*part\.attributes\s*\}\}"#, options: .regularExpression) != nil {
            return html.replacingOccurrences(of: #"\{\{\s*part\.attributes\s*\}\}"#, with: "{{ part.attributes }}{{ if canvas }}" + editorAttributes + "{{ endif }}", options: .regularExpression)
        }
        return "{{ if canvas }}<div class=\"{{ part.class }}\" {{ part.attributes }}\(editorAttributes)>{{ endif }}\(html){{ if canvas }}</div>{{ endif }}"
    }
}
