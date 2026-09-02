import Foundation

nonisolated struct ComponentTemplateContext: Sendable {
    let instanceID: UUID
    let packageIdentifier: String
    let properties: [String: ComponentPackageValue]
    let slots: [String: String]
    let componentClass: String
    let componentAttributes: String
    let assetBasePath: String

    init(
        instanceID: UUID,
        packageIdentifier: String,
        properties: [String: ComponentPackageValue],
        slots: [String: String],
        componentClass: String = "",
        componentAttributes: String = "",
        assetBasePath: String = ""
    ) {
        self.instanceID = instanceID
        self.packageIdentifier = packageIdentifier
        self.properties = properties
        self.slots = slots
        self.componentClass = componentClass
        self.componentAttributes = componentAttributes
        self.assetBasePath = assetBasePath
    }
}

nonisolated struct ComponentTextPrimitive: Equatable, Sendable {
    let key: String
    let defaultValue: String
}

nonisolated struct ComponentHTMLPrimitive: Equatable, Sendable {
    let key: String
    let defaultValue: String
}

nonisolated enum ComponentTemplateRenderer {
    private static let loremParagraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    static func render(_ template: String, context: ComponentTemplateContext) -> String {
        var result = renderText(in: template, context: context)
        result = renderImage(in: result, context: context)
        result = renderConditions(in: result, context: context)
        result = renderSlots(in: result, context: context)
        let expression = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let expressionRange = Range(match.range(at: 1), in: result) else { continue }
            let templateExpression = String(result[expressionRange])
            let trimmedExpression = templateExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedExpression == "html" || trimmedExpression.hasPrefix("html=") || trimmedExpression.hasPrefix("html =") {
                continue
            }
            let replacement = value(forExpression: templateExpression, context: context)
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return renderHTML(in: result, context: context)
    }

    static func textPrimitives(in template: String) -> [ComponentTextPrimitive] {
        primitiveMatches(in: template).enumerated().map { index, match in
            ComponentTextPrimitive(
                key: "content\(index + 1)",
                defaultValue: primitiveDefault(match: match, in: template)
            )
        }
    }

    static func hasImagePrimitive(in template: String) -> Bool {
        template.range(of: #"\{\{\s*image\s*\}\}"#, options: .regularExpression) != nil
    }

    static func htmlPrimitives(in template: String) -> [ComponentHTMLPrimitive] {
        htmlPrimitiveMatches(in: template).enumerated().map { index, match in
            ComponentHTMLPrimitive(
                key: "html\(index + 1)",
                defaultValue: htmlPrimitiveDefault(match: match, in: template)
            )
        }
    }

    static func scopedCSS(_ css: String, packageIdentifier: String) -> String {
        css.replacingOccurrences(
            of: ":host",
            with: ":is([data-foundry-package=\"\(escapeAttribute(packageIdentifier))\"], .\(packageClass(for: packageIdentifier)))"
        )
    }

    static func packageClass(for packageIdentifier: String) -> String {
        "foundry-package-" + packageIdentifier.map { character in
            character.isLetter || character.isNumber || character == "-" ? String(character) : "-"
        }.joined()
    }

    private static func renderText(in template: String, context: ComponentTemplateContext) -> String {
        var result = template
        let matches = primitiveMatches(in: result)
        for (index, match) in matches.enumerated().reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result) else { continue }
            let key = "content\(index + 1)"
            let declaredDefault = primitiveDefault(match: match, in: result)
            let currentValue = stringValue(context.properties[key]) ?? declaredDefault
            result.replaceSubrange(wholeRange, with: escapeText(currentValue))
            if !context.componentAttributes.isEmpty {
                addInlineEditingAttribute(for: key, atUTF16Offset: match.range.location, to: &result)
            }
        }
        return result
    }

    private static func renderImage(in template: String, context: ComponentTemplateContext) -> String {
        guard hasImagePrimitive(in: template) else { return template }
        let source = stringValue(context.properties["source"]) ?? ""
        let image: String
        if source.isEmpty && !context.componentAttributes.isEmpty {
            image = "<span class=\"foundry-image-drop-zone\" data-foundry-image-drop-zone>Drop an image here</span>"
        } else {
            image = "<img class=\"foundry-image\" data-foundry-image-drop-zone src=\"\(escapeAttribute(source))\" alt=\"\">"
        }
        let expression = try! NSRegularExpression(pattern: #"\{\{\s*image\s*\}\}"#)
        return expression.stringByReplacingMatches(
            in: template,
            range: NSRange(template.startIndex..., in: template),
            withTemplate: NSRegularExpression.escapedTemplate(for: image)
        )
    }

    private static func renderHTML(in template: String, context: ComponentTemplateContext) -> String {
        var result = template
        let matches = htmlPrimitiveMatches(in: result)
        for (index, match) in matches.enumerated().reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result) else { continue }
            let key = "html\(index + 1)"
            let currentValue = stringValue(context.properties[key]) ?? htmlPrimitiveDefault(match: match, in: result)
            result.replaceSubrange(wholeRange, with: currentValue)
            if !context.componentAttributes.isEmpty {
                addInlineEditingAttribute(
                    for: key,
                    atUTF16Offset: match.range.location,
                    rendersHTML: true,
                    inlineSource: currentValue,
                    to: &result
                )
            }
        }
        return result
    }

    private static func primitiveMatches(in template: String) -> [NSTextCheckingResult] {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*text(?:\s*=\s*"([^"]*)")?\s*\}\}"#
        )
        return expression.matches(in: template, range: NSRange(template.startIndex..., in: template))
    }

    private static func primitiveDefault(match: NSTextCheckingResult, in template: String) -> String {
        if let textRange = Range(match.range(at: 1), in: template) {
            return String(template[textRange])
        }
        return loremParagraph
    }

    private static func htmlPrimitiveMatches(in template: String) -> [NSTextCheckingResult] {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*html(?:\s*=\s*"([^"]*)")?\s*\}\}"#
        )
        return expression.matches(in: template, range: NSRange(template.startIndex..., in: template))
    }

    private static func htmlPrimitiveDefault(match: NSTextCheckingResult, in template: String) -> String {
        if let htmlRange = Range(match.range(at: 1), in: template) {
            return String(template[htmlRange])
        }
        return """
        <ul>
          <li>First item</li>
          <li>Second item</li>
          <li>Third item</li>
        </ul>
        """
    }

    private static func addInlineEditingAttribute(
        for key: String,
        atUTF16Offset offset: Int,
        rendersHTML: Bool = false,
        inlineSource: String? = nil,
        to result: inout String
    ) {
        let textPosition = String.Index(utf16Offset: offset, in: result)
        guard let tagStart = result[..<textPosition].lastIndex(of: "<"),
              let tagEnd = result[tagStart...].firstIndex(of: ">"),
              tagEnd < textPosition else { return }
        let tag = result[tagStart...tagEnd]
        guard !tag.hasPrefix("</"),
              !tag.hasPrefix("<!"),
              !tag.hasPrefix("<?"),
              !tag.contains("data-foundry-inline-property=") else { return }
        let htmlAttribute = rendersHTML ? " data-foundry-inline-html" : ""
        let sourceAttribute = inlineSource.map {
            " data-foundry-inline-source=\"\(Data($0.utf8).base64EncodedString())\""
        } ?? ""
        result.insert(
            contentsOf: " data-foundry-inline-property=\"\(escapeAttribute(key))\"\(htmlAttribute)\(sourceAttribute)",
            at: tagEnd
        )
    }

    private static func value(forExpression expression: String, context: ComponentTemplateContext) -> String {
        let parts = expression.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let key = parts.first else { return "" }
        var result = value(for: key, context: context)
        for filter in parts.dropFirst() {
            result = apply(filter: filter, to: result)
        }
        return result
    }

    private static func value(for key: String, context: ComponentTemplateContext) -> String {
        if key == "id" || key == "instance.id" {
            return "foundry-" + context.instanceID.uuidString.lowercased()
        }
        if key == "instance.uuid" {
            return context.instanceID.uuidString
        }
        if key == "package.id" { return escape(context.packageIdentifier) }
        if key == "component.class" {
            return context.componentClass.isEmpty ? "" : " " + escapeAttribute(context.componentClass)
        }
        if key == "component.attributes" { return context.componentAttributes }
        if key.hasPrefix("asset.") {
            let path = String(key.dropFirst("asset.".count))
            guard isSafeRelativePath(path) else { return "" }
            return escapeAttribute(join(context.assetBasePath, path))
        }
        if key.hasPrefix("slot.") {
            return context.slots[String(key.dropFirst("slot.".count))] ?? ""
        }
        let prefix = key.hasPrefix("control.") ? "control." : "property."
        guard key.hasPrefix(prefix) else { return "" }
        let reference = String(key.dropFirst(prefix.count))
        let value: ComponentPackageValue
        if let bracket = reference.lastIndex(of: "["), reference.hasSuffix("]"),
           let index = Int(reference[reference.index(after: bracket)..<reference.index(before: reference.endIndex)]),
           let stored = context.properties[String(reference[..<bracket])],
           case .array(let values) = stored, values.indices.contains(index) {
            value = values[index]
        } else if let stored = context.properties[reference] {
            value = stored
        } else {
            return ""
        }
        if reference.hasSuffix(".attributes"), case .string(let attributes) = value {
            return attributes
        }
        switch value {
        case .string(let value): return escape(value)
        case .number(let value): return value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): return value ? "true" : "false"
        case .array(let values): return values.map(packageValueString).joined(separator: ", ")
        }
    }

    private static func packageValueString(_ value: ComponentPackageValue) -> String {
        switch value {
        case .string(let value): escape(value)
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueString).joined(separator: ", ")
        }
    }

    private static func apply(filter: String, to value: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"^(lighten|darken)\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)$"#
        )
        guard let match = expression.firstMatch(in: filter, range: NSRange(filter.startIndex..., in: filter)),
              let nameRange = Range(match.range(at: 1), in: filter),
              let argumentRange = Range(match.range(at: 2), in: filter),
              let argument = Double(filter[argumentRange]) else { return value }
        switch String(filter[nameRange]) {
        case "lighten": return transformColor(value, target: 255, amount: argument / 100)
        case "darken": return transformColor(value, target: 0, amount: argument / 100)
        default: return value
        }
    }

    static func transformColor(_ value: String, target: Double, amount: Double) -> String {
        guard let color = rgb(value) else { return value }
        let amount = min(max(amount, 0), 1)
        return hex(
            color.red + (target - color.red) * amount,
            color.green + (target - color.green) * amount,
            color.blue + (target - color.blue) * amount
        )
    }

    static func colorWithAlpha(_ value: String, alpha: Double) -> String {
        guard let color = rgb(value) else { return value }
        let alpha = min(max(alpha, 0), 1).formatted(.number.precision(.fractionLength(0...3)))
        return "rgb(\(Int(color.red)) \(Int(color.green)) \(Int(color.blue)) / \(alpha))"
    }

    private static func rgb(_ value: String) -> (red: Double, green: Double, blue: Double)? {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let color = UInt64(cleaned, radix: 16) else { return nil }
        return (Double((color >> 16) & 0xFF), Double((color >> 8) & 0xFF), Double(color & 0xFF))
    }

    private static func hex(_ red: Double, _ green: Double, _ blue: Double) -> String {
        func channel(_ value: Double) -> Int { min(max(Int(value.rounded()), 0), 255) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    private static func renderConditions(in template: String, context: ComponentTemplateContext) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*if\s+property\.([A-Za-z][A-Za-z0-9_.-]*)(?:\s*==\s*[\"']([^\"']*)[\"'])?\s*\}\}([\s\S]*?)(?:\{\{\s*else\s*\}\}([\s\S]*?))?\{\{\s*endif\s*\}\}"#
        )
        var result = template
        var remainingPasses = 100
        while let match = expression.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let wholeRange = Range(match.range(at: 0), in: result),
              let keyRange = Range(match.range(at: 1), in: result),
              let bodyRange = Range(match.range(at: 3), in: result),
              remainingPasses > 0 {
            remainingPasses -= 1
            let key = String(result[keyRange])
            let truthyBody = String(result[bodyRange])
            let falseyBody = Range(match.range(at: 4), in: result).map { String(result[$0]) } ?? ""
            let condition: Bool
            if let expectedRange = Range(match.range(at: 2), in: result) {
                condition = stringValue(context.properties[key]) == String(result[expectedRange])
            } else {
                condition = isTruthy(context.properties[key])
            }
            result.replaceSubrange(wholeRange, with: condition ? truthyBody : falseyBody)
        }
        return result
    }

    private static func renderSlots(in template: String, context: ComponentTemplateContext) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*slot\s+id\s*=\s*[\"']([A-Za-z][A-Za-z0-9_.-]*)[\"'](?:\s+[^}]*?)?\s*\}\}"#
        )
        var result = template
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(wholeRange, with: context.slots[String(result[keyRange])] ?? "")
        }
        return result
    }

    private static func isTruthy(_ value: ComponentPackageValue?) -> Bool {
        switch value {
        case .boolean(let value): value
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array(let values): !values.isEmpty
        case nil: false
        }
    }

    private static func stringValue(_ value: ComponentPackageValue?) -> String? {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueString).joined(separator: ", ")
        case nil: nil
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private static func join(_ base: String, _ path: String) -> String {
        guard !base.isEmpty else { return path }
        return base.hasSuffix("/") ? base + path : base + "/" + path
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeText(_ value: String) -> String {
        escape(value.replacingOccurrences(of: "\r\n", with: "\n"))
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value)
    }
}
