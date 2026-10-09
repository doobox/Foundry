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

    static func sanitized(_ data: Data, prefix: String, alt: String = "",
                          overrideFill: Bool = false, overrideStroke: Bool = false) -> String? {
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
        if overrideFill || overrideStroke {
            overridePaint(root, fill: overrideFill, stroke: overrideStroke)
        }
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


    /// Resolve the original paint before changing leaves. Never recolour helper
    /// geometry, introduce missing strokes, or turn fill:none into a solid shape.
    private static func overridePaint(_ root: XMLElement, fill: Bool, stroke: Bool) {
        let painted: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan"]
        func declarations(_ element: XMLElement) -> [(String, String)] {
            (element.attribute(forName: "style")?.stringValue ?? "").split(separator: ";").compactMap {
                let pair = $0.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                return pair.count == 2 ? (pair[0].lowercased(), pair[1]) : nil
            }
        }
        func hasPaint(_ name: String, element: XMLElement, inherited: Bool, initial: Bool) -> Bool {
            var value = element.attribute(forName: name)?.stringValue
            var important = false
            for (key, candidate) in declarations(element) where key == name {
                let isImportant = candidate.range(of: #"!\s*important\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
                if !important || isImportant { value = candidate; important = isImportant }
            }
            let normalized = value?.replacingOccurrences(of: #"!\s*important\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case nil, "inherit", "unset": return inherited
            case "initial", "revert", "revert-layer": return initial
            case "none", "transparent": return false
            default: return true
            }
        }
        func visit(_ element: XMLElement, inheritedFill: Bool, inheritedStroke: Bool) {
            guard !["defs", "clipPath", "mask"].contains(element.name ?? "") else { return }
            let hasFill = hasPaint("fill", element: element, inherited: inheritedFill, initial: true)
            let hasStroke = hasPaint("stroke", element: element, inherited: inheritedStroke, initial: false)
            var replacements: Set<String> = []
            if painted.contains(element.name ?? "") {
                if fill && hasFill { replacements.insert("fill") }
                if stroke && hasStroke { replacements.insert("stroke") }
            }
            // Imported color declarations must not block the selected Bootstrap
            // foreground from reaching currentColor. Definitions stay untouched.
            element.removeAttribute(forName: "color")
            let style = declarations(element).filter { $0.0 != "color" && !replacements.contains($0.0) }
                .map { $0.0 + ":" + $0.1 }.joined(separator: ";")
            element.removeAttribute(forName: "style")
            if !style.isEmpty { element.addAttribute(XMLNode.attribute(withName: "style", stringValue: style) as! XMLNode) }
            for name in replacements {
                element.removeAttribute(forName: name)
                element.addAttribute(XMLNode.attribute(withName: name, stringValue: "currentColor") as! XMLNode)
            }
            for child in element.children ?? [] {
                if let child = child as? XMLElement { visit(child, inheritedFill: hasFill, inheritedStroke: hasStroke) }
            }
        }
        visit(root, inheritedFill: true, inheritedStroke: false)
    }
    static func insert(node: PartNode, package: LoadedPartPackage, assets: ProjectAssetContents,
                       canvas: Bool, into values: inout [String: PartPackageValue]) {
        let usesPaintOverrides = node.type == .svg &&
            node.propertyValue(.init(rawValue: "foreground.enabled")) == .boolean(true)
        let overrideFill = usesPaintOverrides && node.propertyValue(.init(rawValue: "fillEnabled")) == .boolean(true)
        let overrideStroke = usesPaintOverrides && node.propertyValue(.init(rawValue: "strokeEnabled")) == .boolean(true)
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
                let markup = data.flatMap { sanitized($0, prefix: node.id.uuidString + "-" + key + "-" + path.map(String.init).joined(separator: "-"), alt: alt,
                    overrideFill: overrideFill, overrideStroke: overrideStroke) } ?? ""
                if path.isEmpty, let document = try? XMLDocument(xmlString: markup),
                   let root = document.rootElement() {
                    // Reuse the sanitized root directly, without a styling wrapper.
                    // The part supplies its own ID and classes.
                    root.removeAttribute(forName: "id")
                    let attributes = (root.attributes ?? []).map { $0.xmlString }.joined(separator: " ")
                    let content = (root.children ?? []).map { $0.xmlString(options: [.nodeCompactEmptyElement]) }.joined()
                    PartPackageControlGroupCSSResolver.insertRaw(attributes, at: key + ".attributes", into: &values)
                    PartPackageControlGroupCSSResolver.insertRaw(
                        content.replacingOccurrences(of: "{", with: "&#123;").replacingOccurrences(of: "}", with: "&#125;"),
                        at: key + ".content", into: &values)
                }
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
