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

nonisolated enum ComponentTemplateRenderer {
    private static let loremSentences = [
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
        "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
        "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        "Integer posuere erat a ante venenatis dapibus posuere velit aliquet.",
        "Maecenas faucibus mollis interdum, donec sed odio dui.",
        "Cras mattis consectetur purus sit amet fermentum.",
        "Aenean lacinia bibendum nulla sed consectetur.",
        "Praesent commodo cursus magna, vel scelerisque nisl consectetur et."
    ]

    static func render(_ template: String, context: ComponentTemplateContext) -> String {
        var result = renderText(in: template, context: context)
        result = renderConditions(in: result, context: context)
        result = renderSlots(in: result, context: context)
        let expression = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_./-]+)\s*\}\}"#)
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            let replacement = value(for: key, context: context)
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return result
    }

    static func textPrimitives(in template: String) -> [ComponentTextPrimitive] {
        primitiveMatches(in: template).enumerated().map { index, match in
            ComponentTextPrimitive(
                key: "content\(index + 1)",
                defaultValue: primitiveDefault(match: match, in: template)
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
            let attributes = context.componentAttributes.isEmpty
                ? ""
                : " data-foundry-inline-property=\"\(escapeAttribute(key))\""
            result.replaceSubrange(
                wholeRange,
                with: "<span\(attributes)>\(escape(currentValue))</span>"
            )
        }
        return result
    }

    private static func primitiveMatches(in template: String) -> [NSTextCheckingResult] {
        let expression = try! NSRegularExpression(
            pattern: #"%text=\"([^\"]*)\"%|%sentences\[([0-9]+)\]%"#
        )
        return expression.matches(in: template, range: NSRange(template.startIndex..., in: template))
    }

    private static func primitiveDefault(match: NSTextCheckingResult, in template: String) -> String {
        if let textRange = Range(match.range(at: 1), in: template) {
            return String(template[textRange])
        }
        let count = Range(match.range(at: 2), in: template)
            .flatMap { Int(template[$0]) } ?? 1
        return loremSentences.prefix(min(max(count, 1), 10)).joined(separator: " ")
    }

    private static func value(for key: String, context: ComponentTemplateContext) -> String {
        if key == "instance.id" { return context.instanceID.uuidString }
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
        guard key.hasPrefix("property."),
              let value = context.properties[String(key.dropFirst("property.".count))] else { return "" }
        switch value {
        case .string(let value): return escape(value)
        case .number(let value): return value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): return value ? "true" : "false"
        }
    }

    private static func renderConditions(in template: String, context: ComponentTemplateContext) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\{%\s*if\s+property\.([A-Za-z][A-Za-z0-9_.-]*)(?:\s*==\s*[\"']([^\"']*)[\"'])?\s*%\}([\s\S]*?)(?:\{%\s*else\s*%\}([\s\S]*?))?\{%\s*endif\s*%\}"#
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
            pattern: #"\{%\s*slot\s+id\s*=\s*[\"']([A-Za-z][A-Za-z0-9_.-]*)[\"'](?:\s+[^%]*?)?\s*%\}"#
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
        case nil: false
        }
    }

    private static func stringValue(_ value: ComponentPackageValue?) -> String? {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
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

    private static func escapeAttribute(_ value: String) -> String {
        escape(value)
    }
}
