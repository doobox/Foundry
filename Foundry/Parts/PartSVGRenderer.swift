import Foundation

/// Inline SVG is active document content, unlike an image URL. Only a static,
/// local-reference SVG vocabulary may cross into the page document.
nonisolated enum PartSVGRenderer {
    private static let elements: Set<String> = [
        "svg", "g", "defs", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
        "title", "desc", "text", "tspan", "linearGradient", "radialGradient", "stop", "clipPath", "mask"
    ]
    private static let attributes: Set<String> = [
        "id", "viewBox", "preserveAspectRatio", "x", "y", "x1", "x2", "y1", "y2", "cx", "cy", "r", "rx", "ry",
        "width", "height", "d", "points", "transform", "fill", "fill-rule", "fill-opacity", "stroke",
        "stroke-width", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
        "stroke-dasharray", "stroke-dashoffset", "opacity", "clip-path", "clip-rule", "mask", "maskUnits",
        "maskContentUnits", "gradientUnits", "gradientTransform", "spreadMethod", "offset", "stop-color",
        "stop-opacity", "fx", "fy", "fr", "color", "font-family", "font-size", "font-weight", "font-style",
        "text-anchor", "dominant-baseline", "dx", "dy", "rotate", "textLength", "lengthAdjust", "vector-effect"
    ]
    private static let styleNames: Set<String> = [
        "fill", "fill-rule", "fill-opacity", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap",
        "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "opacity", "color",
        "stop-color", "stop-opacity", "clip-path", "clip-rule", "mask", "font-family", "font-size", "font-weight",
        "font-style", "text-anchor", "dominant-baseline", "vector-effect"
    ]

    static func sanitized(_ data: Data, prefix: String, alt: String = "") -> String? {
        guard data.count <= 5_000_000, var source = String(data: data, encoding: .utf8),
              !source.localizedCaseInsensitiveContains("<!ENTITY") else { return nil }
        // Exporters commonly include the SVG 1.1 external DTD. Remove the
        // declaration before parsing: never fetch it or accept an internal subset.
        let doctype = #"<!DOCTYPE\s+svg(?:\s+(?:PUBLIC\s+(?:"[^"]*"|'[^']*')\s+(?:"[^"]*"|'[^']*')|SYSTEM\s+(?:"[^"]*"|'[^']*')))?\s*>"#
        source = source.replacingOccurrences(of: doctype, with: "", options: .regularExpression)
        guard !source.localizedCaseInsensitiveContains("<!DOCTYPE"),
              let document = try? XMLDocument(data: Data(source.utf8), options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement(), root.name == "svg",
              root.uri == nil || root.uri == "" || root.uri == "http://www.w3.org/2000/svg" else { return nil }
        let safePrefix = "fd-svg-" + prefix.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined() + "-"
        var ids: [String: String] = [:]
        func collect(_ element: XMLElement, depth: Int = 0) {
            guard depth < 128 else { return }
            if let id = element.attribute(forName: "id")?.stringValue { ids[id] = safePrefix + String(ids.count) }
            for child in element.children ?? [] { if let child = child as? XMLElement { collect(child, depth: depth + 1) } }
        }
        collect(root)
        func safeValue(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains("\\"), !trimmed.contains("/*"), !trimmed.contains("@"),
                  !trimmed.localizedCaseInsensitiveContains("expression"),
                  !trimmed.localizedCaseInsensitiveContains("javascript:"),
                  !trimmed.contains("<"), !trimmed.contains(">") else { return nil }
            if trimmed.localizedCaseInsensitiveContains("url") {
                let pattern = #"^url\(\s*['"]?#([^\s)'"\u0000]+)['"]?\s*\)$"#
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                      let range = Range(match.range(at: 1), in: trimmed), let id = ids[String(trimmed[range])] else { return nil }
                return "url(#\(id))"
            }
            return trimmed
        }
        func clean(_ element: XMLElement, depth: Int) {
            guard depth < 128 else { element.detach(); return }
            for attribute in element.attributes ?? [] {
                guard let name = attribute.name, let value = attribute.stringValue else { attribute.detach(); continue }
                if name == "style" {
                    let declarations = value.split(separator: ";").compactMap { entry -> String? in
                        let pair = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        guard pair.count == 2, styleNames.contains(pair[0]), let safe = safeValue(pair[1]) else { return nil }
                        return pair[0] + ":" + safe
                    }
                    attribute.stringValue = declarations.joined(separator: ";")
                } else if name == "id" {
                    attribute.stringValue = ids[value]
                } else if attributes.contains(name), let safe = safeValue(value) {
                    attribute.stringValue = safe
                } else { attribute.detach() }
            }
            element.namespaces = []
            for child in element.children ?? [] {
                if let child = child as? XMLElement {
                    if elements.contains(child.name ?? ""), child.uri == nil || child.uri == "" || child.uri == "http://www.w3.org/2000/svg" {
                        clean(child, depth: depth + 1)
                    } else { child.detach() }
                } else if child.kind != .text { child.detach() }
            }
        }
        clean(root, depth: 0)
        // Mark only existing paint. Invisible artboard rectangles and helper
        // geometry must never become visible just because a colour is overridden.
        let paintedElements: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan"]
        func paint(_ name: String, on element: XMLElement, inherited: Bool, initial: Bool) -> Bool {
            var value = element.attribute(forName: name)?.stringValue
            var important = false
            for declaration in (element.attribute(forName: "style")?.stringValue ?? "").split(separator: ";") {
                let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard pair.count == 2, pair[0].lowercased() == name else { continue }
                let isImportant = pair[1].range(of: #"!\s*important\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
                if !important || isImportant { value = pair[1]; important = isImportant }
            }
            let normalized = value?.replacingOccurrences(of: #"!\s*important\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case nil, "inherit", "unset": return inherited
            case "initial", "revert", "revert-layer": return initial
            case "none": return false
            default: return true
            }
        }
        func markPaint(_ element: XMLElement, fill: Bool, stroke: Bool) {
            guard !["defs", "clipPath", "mask"].contains(element.name ?? "") else { return }
            let hasFill = paint("fill", on: element, inherited: fill, initial: true)
            let hasStroke = paint("stroke", on: element, inherited: stroke, initial: false)
            if paintedElements.contains(element.name ?? "") {
                if hasFill { element.addAttribute(XMLNode.attribute(withName: "data-foundry-svg-fill", stringValue: "") as! XMLNode) }
                if hasStroke { element.addAttribute(XMLNode.attribute(withName: "data-foundry-svg-stroke", stringValue: "") as! XMLNode) }
            }
            for child in element.children ?? [] {
                if let child = child as? XMLElement { markPaint(child, fill: hasFill, stroke: hasStroke) }
            }
        }
        markPaint(root, fill: true, stroke: false)
        root.addNamespace(XMLNode.namespace(withName: "", stringValue: "http://www.w3.org/2000/svg") as! XMLNode)
        root.addAttribute(XMLNode.attribute(withName: "role", stringValue: "img") as! XMLNode)
        if !alt.isEmpty {
            root.addAttribute(XMLNode.attribute(withName: "aria-label", stringValue: alt) as! XMLNode)
        } else if root.elements(forName: "title").isEmpty {
            root.addAttribute(XMLNode.attribute(withName: "aria-hidden", stringValue: "true") as! XMLNode)
        }
        // Imported text must never become a Foundry template expression.
        return root.xmlString(options: [.nodeCompactEmptyElement])
            .replacingOccurrences(of: "{", with: "&#123;").replacingOccurrences(of: "}", with: "&#125;")
    }

    static func insert(node: PartNode, package: LoadedPartPackage, assets: ProjectAssetContents,
                       canvas: Bool, into values: inout [String: PartPackageValue]) {
        for definition in node.type.definition.properties {
            guard case .svg = definition.control else { continue }
            let key = definition.key.rawValue
            let alt = node.property(PartPackageAdapter.imageAltKey(for: key))
            func resolve(_ value: PartProperty.Value, path: [Int]) -> PartPackageValue {
                if case .array(let children) = value {
                    return .array(children.enumerated().map { resolve($0.element, path: path + [$0.offset]) })
                }
                let source = value.stringValue
                var data: Data?
                if let id = source.foundryAssetID { data = assets[id]?.data }
                else if !source.isEmpty, package.manifest.assetDeclaration(containing: source) != nil {
                    let root = package.resourceRootURL.resolvingSymlinksInPath()
                    let file = root.appending(path: source).resolvingSymlinksInPath()
                    if file.path.hasPrefix(root.path + "/") { data = try? Data(contentsOf: file) }
                }
                let markup = data.flatMap { sanitized($0, prefix: node.id.uuidString + "-" + key + "-" + path.map(String.init).joined(separator: "-"), alt: alt) } ?? ""
                return .string(fragment(markup: markup, key: key, path: path, canvas: canvas))
            }
            values[key] = resolve(node.storedPropertyValue(definition.key) ?? definition.defaultValue, path: [])
            values["__foundry_raw." + key] = .boolean(true)
            values["__foundry_svg." + key] = .boolean(true)
        }
    }

    static func fragment(markup: String, key: String, path: [Int], canvas: Bool) -> String {
        func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;") }
        guard canvas else { return markup }
        let pathAttribute = path.isEmpty ? "" : " data-foundry-property-path=\"\(path.map(String.init).joined(separator: ","))\" data-foundry-primitive-property=\"\(escape(key))\""
        let editorAttributes = "data-foundry-image-drop-zone data-foundry-svg-drop-zone data-foundry-image-property=\"\(escape(key))\"\(pathAttribute)"
        if markup.isEmpty {
            return "<span class=\"foundry-image-drop-zone\" \(editorAttributes)><span class=\"foundry-drop-label\">SVG</span></span>"
        }
        return "<span class=\"fd-inline-svg\" \(editorAttributes)>\(markup)</span>"
    }
}
