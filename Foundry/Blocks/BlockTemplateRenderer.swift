import Foundation

nonisolated enum BlockTemplateEnvironment: String, Equatable, Sendable {
    case canvas
    case preview
    case published
}

nonisolated struct BlockTemplateContext: Sendable {
    let instanceID: UUID
    let packageIdentifier: String
    let properties: [String: BlockPackageValue]
    let templateValues: [String: BlockPackageValue]
    let slots: [String: String]
    let dropZones: [String: String]
    let blockClass: String
    let blockAttributes: String
    let assetBasePath: String
    let assetPaths: [String: String]
    let siteBaseURL: String
    let pageURL: String
    let siteRootPath: String
    let siteAssetsPath: String
    let enablesEditorMarkup: Bool
    let environment: BlockTemplateEnvironment
    let richTextLinkContext: FoundryRichTextCodec.LinkContext?
    let loopMaximums: [String: Int]

    var allProperties: [String: BlockPackageValue] {
        properties.merging(templateValues) { current, _ in current }
    }

    init(
        instanceID: UUID,
        packageIdentifier: String,
        properties: [String: BlockPackageValue],
        templateValues: [String: BlockPackageValue] = [:],
        slots: [String: String],
        dropZones: [String: String] = [:],
        blockClass: String = "",
        blockAttributes: String = "",
        assetBasePath: String = "",
        assetPaths: [String: String] = [:],
        siteBaseURL: String = "",
        pageURL: String = "",
        siteRootPath: String = "",
        siteAssetsPath: String = "",
        enablesEditorMarkup: Bool = false,
        environment: BlockTemplateEnvironment = .published,
        richTextLinkContext: FoundryRichTextCodec.LinkContext? = nil,
        loopMaximums: [String: Int]
    ) {
        self.instanceID = instanceID
        self.packageIdentifier = packageIdentifier
        self.properties = properties
        self.templateValues = templateValues
        self.slots = slots
        self.dropZones = dropZones
        self.blockClass = blockClass
        self.blockAttributes = blockAttributes
        self.assetBasePath = assetBasePath
        self.assetPaths = assetPaths
        self.siteBaseURL = siteBaseURL
        self.pageURL = pageURL
        self.siteRootPath = siteRootPath
        self.siteAssetsPath = siteAssetsPath
        self.enablesEditorMarkup = enablesEditorMarkup
        self.environment = environment
        self.richTextLinkContext = richTextLinkContext
        self.loopMaximums = loopMaximums
    }

    init(
        instanceID: UUID,
        packageIdentifier: String,
        properties: [String: BlockPackageValue],
        templateValues: [String: BlockPackageValue] = [:],
        slots: [String: String],
        dropZones: [String: String] = [:],
        blockClass: String = "",
        blockAttributes: String = "",
        assetBasePath: String = "",
        assetPaths: [String: String] = [:],
        siteBaseURL: String = "",
        pageURL: String = "",
        siteRootPath: String = "",
        siteAssetsPath: String = "",
        enablesEditorMarkup: Bool = false,
        environment: BlockTemplateEnvironment = .published,
        richTextLinkContext: FoundryRichTextCodec.LinkContext? = nil
    ) {
        self.init(
            instanceID: instanceID,
            packageIdentifier: packageIdentifier,
            properties: properties,
            templateValues: templateValues,
            slots: slots,
            dropZones: dropZones,
            blockClass: blockClass,
            blockAttributes: blockAttributes,
            assetBasePath: assetBasePath,
            assetPaths: assetPaths,
            siteBaseURL: siteBaseURL,
            pageURL: pageURL,
            siteRootPath: siteRootPath,
            siteAssetsPath: siteAssetsPath,
            enablesEditorMarkup: enablesEditorMarkup,
            environment: environment,
            richTextLinkContext: richTextLinkContext,
            loopMaximums: [:]
        )
    }
}

nonisolated struct BlockTextPrimitive: Codable, Equatable, Sendable {
    let key: String
    let defaultValue: String
    let isRepeated: Bool
}

nonisolated struct BlockHTMLPrimitive: Codable, Equatable, Sendable {
    let key: String
    let defaultValue: String
    let isRepeated: Bool
}

nonisolated struct BlockImagePrimitive: Codable, Equatable, Sendable {
    let key: String
    let isRepeated: Bool
}

nonisolated enum BlockTemplateRenderer {
    private static let dropZoneExpression = try! NSRegularExpression(
        pattern: #"^\s*dropZone\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*$"#
    )
    private static let childAreaExpression = try! NSRegularExpression(
        pattern: #"^\s*childArea\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*$"#
    )
    private static let assetExpression = try! NSRegularExpression(
        pattern: #"^\s*asset\(\s*\"([^\"]+)\"\s*\)\s*$"#
    )

    static func dropZoneNames(in template: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*dropZone\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*\}\}"#
        )
        return expression.matches(in: template, range: NSRange(template.startIndex..., in: template)).compactMap {
            Range($0.range(at: 1), in: template).map { String(template[$0]) }
        }
    }
    private static let loremParagraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
    private static let templateExpression = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
    private static let imageExpression = try! NSRegularExpression(pattern: #"\{\{\s*image\(\s*\"[A-Za-z][A-Za-z0-9_-]*\"\s*\)\s*\}\}"#)
    private static let filterCallExpression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)\(\s*(.*?)\s*\)$"#)
    private static let outputEncodingFilters: Set<String> = [
        "escapeHTML", "escapeHTMLAttribute", "encodeURL", "encodeURIComponent", "encodeJSON"
    ]
    private static let conditionBlockExpression = try! NSRegularExpression(pattern: #"\{\{\s*if\s+([^{}]+?)\s*\}\}([\s\S]*?)\{\{\s*endif\s*\}\}"#)
    private static let conditionBranchExpression = try! NSRegularExpression(pattern: #"\{\{\s*(elseif\s+([^{}]+?)|else)\s*\}\}"#)
    private static let keyedTextExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_text\s+key=\"([^\"]+)\"\s+default=\"([^\"]*)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let keyedHTMLExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_html\s+key=\"([^\"]+)\"\s+default=\"([^\"]*)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let keyedImageExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_image\s+key=\"([^\"]+)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let controlledImageElementExpression = try! NSRegularExpression(
        pattern: #"<img\b([^>]*?)\bsrc\s*=\s*([\"'])\{\{\s*control\.([A-Za-z][A-Za-z0-9_-]*)(\.rendition\.[A-Za-z][A-Za-z0-9_-]*(?:\.href)?|\.href)?\s*\}\}\2([^>]*)>"#,
        options: [.caseInsensitive]
    )

    static func render(_ template: String, context: BlockTemplateContext) -> String {
        let loopMaximums = context.loopMaximums.isEmpty
            ? BlockRegistry.definition(for: .init(rawValue: context.packageIdentifier)).package?.loopMaximums ?? [:]
            : context.loopMaximums
        let expanded = (try? BlockTemplateLoop.expand(
            template,
            properties: context.allProperties,
            maximums: loopMaximums,
            environment: context.environment
        ).template) ?? template
        var result = renderControlledImageElements(in: expanded, context: context)
        result = renderText(in: result, context: context)
        result = renderImage(in: result, context: context)
        result = renderConditions(in: result, context: context)
        let matches = templateExpression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let expressionRange = Range(match.range(at: 1), in: result) else { continue }
            let templateExpression = String(result[expressionRange])
            let trimmedExpression = templateExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedExpression.hasPrefix("__foundry_html ") {
                continue
            }
            let replacement = value(forExpression: templateExpression, context: context)
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return renderHTML(in: result, context: context)
    }

    static func textPrimitives(in template: String) -> [BlockTextPrimitive] {
        textPrimitives(in: template, loopMaximums: [:])
    }

    static func textPrimitives(in template: String, loopMaximums: [String: Int]) -> [BlockTextPrimitive] {
        (try? BlockTemplateLoop.declarations(in: template))?.compactMap {
            guard case .text = $0.kind else { return nil }
            return .init(key: $0.key, defaultValue: $0.defaultValue ?? loremParagraph, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func hasImagePrimitive(in template: String) -> Bool {
        imageExpression.firstMatch(in: template, range: NSRange(template.startIndex..., in: template)) != nil
    }

    static func htmlPrimitives(in template: String) -> [BlockHTMLPrimitive] {
        htmlPrimitives(in: template, loopMaximums: [:])
    }

    static func htmlPrimitives(in template: String, loopMaximums: [String: Int]) -> [BlockHTMLPrimitive] {
        (try? BlockTemplateLoop.declarations(in: template))?.compactMap {
            guard case .html = $0.kind else { return nil }
            return .init(key: $0.key, defaultValue: $0.defaultValue ?? htmlDefault, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func imagePrimitives(in template: String) -> [BlockImagePrimitive] {
        (try? BlockTemplateLoop.declarations(in: template))?.compactMap {
            guard case .image = $0.kind else { return nil }
            return .init(key: $0.key, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func scopedCSS(_ css: String, packageIdentifier: String, instanceID: UUID) -> String {
        css.replacingOccurrences(
            of: ":instance",
            with: "[data-foundry-id=\"\(instanceID.uuidString)\"]"
        ).replacingOccurrences(
            of: ":host",
            with: ":is([data-foundry-package=\"\(escapeAttribute(packageIdentifier))\"], .\(packageClass(for: packageIdentifier)))"
        )
    }

    static func packageClass(for packageIdentifier: String) -> String {
        "foundry-package-" + packageIdentifier.map { character in
            character.isLetter || character.isNumber || character == "-" ? String(character) : "-"
        }.joined()
    }

    private static func renderText(in template: String, context: BlockTemplateContext) -> String {
        var result = template
        let keyedMatches = keyedTextExpression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in keyedMatches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result),
                  let defaultRange = Range(match.range(at: 2), in: result) else { continue }
            let key = String(result[keyRange])
            let declaredDefault = decodedDefault(String(result[defaultRange])) ?? loremParagraph
            let path = indexPath(match, group: 4, in: result)
            let currentValue = stringValue(value(context.allProperties[key], at: path)) ?? declaredDefault
            let renderedValue = renderedText(currentValue, context: context)
            result.replaceSubrange(wholeRange, with: renderedValue)
            if context.enablesEditorMarkup {
                addInlineEditingAttribute(
                    for: key,
                    atUTF16Offset: match.range.location,
                    inlineSource: currentValue,
                    marksSelectablePrimitive: true,
                    indexPath: path,
                    to: &result
                )
            }
        }
        return result
    }

    private static func renderImage(in template: String, context: BlockTemplateContext) -> String {
        var result = template
        let keyedMatches = keyedImageExpression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in keyedMatches {
            guard let range = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            let path = indexPath(match, group: 3, in: result)
            result.replaceSubrange(
                range,
                with: renderedImage(
                    source: stringValue(value(context.allProperties[key], at: path)) ?? "",
                    key: key,
                    marksSelectablePrimitive: !path.isEmpty,
                    indexPath: path,
                    context: context
                )
            )
        }
        return result
    }

    private static func renderControlledImageElements(
        in template: String,
        context: BlockTemplateContext
    ) -> String {
        var result = template
        let matches = controlledImageElementExpression.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let beforeRange = Range(match.range(at: 1), in: result),
                  let keyRange = Range(match.range(at: 3), in: result),
                  let afterRange = Range(match.range(at: 5), in: result) else { continue }
            let key = String(result[keyRange])
            let suffix = Range(match.range(at: 4), in: result).map { String(result[$0]) } ?? ""
            let renditionSuffix = suffix.hasSuffix(".href") ? String(suffix.dropLast(5)) : suffix
            let valueKey = suffix == ".href" ? key : key + renditionSuffix
            let source = stringValue(context.allProperties[valueKey]) ?? ""
            let resolvedSource = context.assetPaths[source] ?? source
            let before = String(result[beforeRange])
            let after = String(result[afterRange])
            if resolvedSource.isEmpty {
                if context.enablesEditorMarkup {
                    let attributes = addingCSSClass("foundry-image-drop-zone", to: before + after)
                    result.replaceSubrange(
                        wholeRange,
                        with: "<span\(attributes) data-foundry-image-drop-zone data-foundry-image-property=\"\(escapeAttribute(key))\">Drop image here</span>"
                    )
                } else {
                    result.removeSubrange(wholeRange)
                }
                continue
            }
            let editorAttributes = context.enablesEditorMarkup
                ? " data-foundry-image-drop-zone data-foundry-image-property=\"\(escapeAttribute(key))\""
                : ""
            result.replaceSubrange(
                wholeRange,
                with: "<img\(before)src=\"\(escapeAttribute(resolvedSource))\"\(after)\(editorAttributes)>"
            )
        }
        return result
    }

    private static func renderHTML(in template: String, context: BlockTemplateContext) -> String {
        var result = template
        let keyedMatches = keyedHTMLExpression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in keyedMatches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result),
                  let defaultRange = Range(match.range(at: 2), in: result) else { continue }
            let key = String(result[keyRange])
            let defaultValue = decodedDefault(String(result[defaultRange])) ?? htmlDefault
            let path = indexPath(match, group: 4, in: result)
            let currentValue = stringValue(value(context.allProperties[key], at: path)) ?? defaultValue
            result.replaceSubrange(wholeRange, with: currentValue)
            if context.enablesEditorMarkup {
                addInlineEditingAttribute(
                    for: key,
                    atUTF16Offset: match.range.location,
                    rendersHTML: true,
                    inlineSource: currentValue,
                    marksSelectablePrimitive: !path.isEmpty,
                    indexPath: path,
                    to: &result
                )
            }
        }
        return result
    }

    private static let htmlDefault = """
        <ul>
          <li>First item</li>
          <li>Second item</li>
          <li>Third item</li>
        </ul>
        """

    private static func decodedDefault(_ value: String) -> String? {
        guard value != "~", let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func renderedText(_ value: String, context: BlockTemplateContext) -> String {
        if let fragment = FoundryRichTextCodec.htmlFragment(from: value) {
            return context.richTextLinkContext.map { FoundryRichTextCodec.resolvingLinks(in: fragment, context: $0) } ?? fragment
        }
        return escapeText(value)
    }

    private static func renderedImage(
        source: String,
        key: String,
        marksSelectablePrimitive: Bool,
        indexPath: [Int],
        context: BlockTemplateContext
    ) -> String {
        let resolvedSource = context.assetPaths[source] ?? source
        let propertyAttribute = context.enablesEditorMarkup ? " data-foundry-image-property=\"\(escapeAttribute(key))\"" : ""
        let primitiveAttribute = context.enablesEditorMarkup && marksSelectablePrimitive
            ? " data-foundry-primitive-property=\"\(escapeAttribute(key))\""
            : ""
        let pathAttribute = context.enablesEditorMarkup && !indexPath.isEmpty
            ? " data-foundry-property-path=\"\(indexPath.map(String.init).joined(separator: ","))\""
            : ""
        if resolvedSource.isEmpty && context.enablesEditorMarkup {
            return "<span class=\"foundry-image-drop-zone\" data-foundry-image-drop-zone\(propertyAttribute)\(primitiveAttribute)\(pathAttribute)>Drop image here</span>"
        }
        let editorAttribute = context.enablesEditorMarkup ? " data-foundry-image-drop-zone\(propertyAttribute)" : ""
        return "<img class=\"foundry-image\"\(editorAttribute)\(primitiveAttribute)\(pathAttribute) src=\"\(escapeAttribute(resolvedSource))\" alt=\"\">"
    }

    private static func addInlineEditingAttribute(
        for key: String,
        atUTF16Offset offset: Int,
        rendersHTML: Bool = false,
        inlineSource: String? = nil,
        marksSelectablePrimitive: Bool = false,
        indexPath: [Int] = [],
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
        let primitiveAttribute = marksSelectablePrimitive
            ? " data-foundry-primitive-property=\"\(escapeAttribute(key))\""
            : ""
        let sourceAttribute = inlineSource.map {
            " data-foundry-inline-source=\"\(Data($0.utf8).base64EncodedString())\""
        } ?? ""
        let pathAttribute = indexPath.isEmpty
            ? ""
            : " data-foundry-property-path=\"\(indexPath.map(String.init).joined(separator: ","))\""
        result.insert(
            contentsOf: " data-foundry-inline-property=\"\(escapeAttribute(key))\"\(htmlAttribute)\(primitiveAttribute)\(sourceAttribute)\(pathAttribute)",
            at: tagEnd
        )
    }

    private static func indexPath(_ match: NSTextCheckingResult, group: Int, in source: String) -> [Int] {
        guard match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: source) else { return [] }
        return source[range].split(separator: ",").compactMap { Int($0) }
    }

    private static func addingCSSClass(_ className: String, to attributes: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\bclass\s*=\s*([\"'])([^\"']*)\1"#,
            options: [.caseInsensitive]
        )
        guard let match = expression.firstMatch(
            in: attributes,
            range: NSRange(attributes.startIndex..., in: attributes)
        ), let valueRange = Range(match.range(at: 2), in: attributes) else {
            return attributes + " class=\"\(className)\""
        }
        var result = attributes
        result.replaceSubrange(valueRange, with: String(attributes[valueRange]) + " " + className)
        return result
    }

    private static func value(_ value: BlockPackageValue?, at path: [Int]) -> BlockPackageValue? {
        path.reduce(value) { current, index in
            guard case .array(let values) = current, values.indices.contains(index) else { return nil }
            return values[index]
        }
    }

    private static func value(forExpression expression: String, context: BlockTemplateContext) -> String {
        let expressionRange = NSRange(expression.startIndex..., in: expression)
        if let match = dropZoneExpression.firstMatch(in: expression, range: expressionRange),
           let nameRange = Range(match.range(at: 1), in: expression) {
            return context.dropZones[String(expression[nameRange])] ?? ""
        }
        if let match = childAreaExpression.firstMatch(in: expression, range: expressionRange),
           let nameRange = Range(match.range(at: 1), in: expression) {
            return context.slots[String(expression[nameRange])] ?? ""
        }
        if let match = assetExpression.firstMatch(in: expression, range: expressionRange),
           let pathRange = Range(match.range(at: 1), in: expression) {
            return assetPath(String(expression[pathRange]), context: context)
        }
        let parts = BlockTemplateExpression.templateParts(expression)
        guard let key = parts.first else { return "" }
        let filters = Array(parts.dropFirst())
        if let encodingIndex = filters.firstIndex(where: outputEncodingFilters.contains) {
            let valueFilters = Array(filters[..<encodingIndex])
            let encodingFilters = Array(filters[encodingIndex...])
            guard encodingFilters.allSatisfy(outputEncodingFilters.contains) else { return "" }
            return encodedValue(for: key, valueFilters: valueFilters, encodingFilters: encodingFilters, context: context)
        }
        if !filters.isEmpty,
           let filteredDate = filteredDate(for: key, filters: filters, context: context) {
            return escape(filteredDate)
        }
        if !filters.isEmpty,
           let filteredColor = filteredColor(for: key, filters: filters, context: context) {
            return escape(filteredColor)
        }
        let simpleValue = #"^(?:instance\.id|package\.id|site\.baseURL|page\.url|path\.(?:siteRoot|siteAssets)|block\.(?:class|attributes)|control\.[A-Za-z][A-Za-z0-9_.-]*(?:\[[0-9]+\])?)$"#
        var result: String
        if key.range(of: simpleValue, options: .regularExpression) != nil {
            result = value(for: key, context: context)
        } else if let node = try? BlockTemplateExpression.parse(key),
                  let evaluated = try? BlockTemplateExpression.evaluate(
                    node,
                    properties: context.allProperties,
                    environment: context.environment
                  ) {
            result = escape(evaluated.output)
        } else {
            result = ""
        }
        for filter in filters {
            result = apply(filter: filter, to: result, context: context)
        }
        return result
    }

    private static func encodedValue(
        for key: String,
        valueFilters: [String],
        encodingFilters: [String],
        context: BlockTemplateContext
    ) -> String {
        let typedValue = valueFilters.isEmpty ? packageValue(for: key, context: context) : nil
        var result: String
        if !valueFilters.isEmpty, let date = filteredDate(for: key, filters: valueFilters, context: context) {
            result = date
        } else if !valueFilters.isEmpty, let color = filteredColor(for: key, filters: valueFilters, context: context) {
            result = color
        } else if let typedValue {
            result = packageValueRawString(typedValue)
        } else {
            return ""
        }

        var jsonValue = typedValue
        for filter in encodingFilters {
            switch filter {
            case "escapeHTML": result = escape(result)
            case "escapeHTMLAttribute": result = escapeAttribute(result)
            case "encodeURL": result = encodeURL(result) ?? ""
            case "encodeURIComponent": result = encodeURIComponent(result)
            case "encodeJSON": result = encodeJSON(jsonValue ?? .string(result)) ?? ""
            default: return ""
            }
            jsonValue = nil
        }
        return result
    }

    private static func value(for key: String, context: BlockTemplateContext) -> String {
        if key == "instance.id" {
            return context.instanceID.uuidString
        }
        if key == "package.id" { return escape(context.packageIdentifier) }
        if key == "site.baseURL" { return escapeAttribute(context.siteBaseURL) }
        if key == "page.url" { return escapeAttribute(context.pageURL) }
        if key == "path.siteRoot" { return escapeAttribute(context.siteRootPath) }
        if key == "path.siteAssets" { return escapeAttribute(context.siteAssetsPath) }
        if key == "block.class" {
            return escapeAttribute(context.blockClass)
        }
        if key == "block.attributes" { return context.blockAttributes }
        guard key.hasPrefix("control.") else { return "" }
        let reference = String(key.dropFirst("control.".count))
        let value: BlockPackageValue
        if let bracket = reference.lastIndex(of: "["), reference.hasSuffix("]"),
           let index = Int(reference[reference.index(after: bracket)..<reference.index(before: reference.endIndex)]),
           let stored = context.allProperties[String(reference[..<bracket])],
           case .array(let values) = stored, values.indices.contains(index) {
            value = values[index]
        } else if let stored = context.allProperties[reference] {
            value = stored
        } else {
            return ""
        }
        if reference.hasSuffix(".attributes"), case .string(let attributes) = value {
            return attributes
        }
        switch value {
        case .string(let value):
            let resolved = reference.hasSuffix(".href") ? context.assetPaths[value] ?? value : value
            return escape(resolved)
        case .number(let value): return value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): return value ? "true" : "false"
        case .array(let values): return values.map(packageValueString).joined(separator: ", ")
        case .object: return ""
        }
    }

    private static func assetPath(_ path: String, context: BlockTemplateContext) -> String {
        guard isSafeRelativePath(path) else { return "" }
        if let resolvedPath = context.assetPaths[path] {
            return escapeAttribute(resolvedPath)
        }
        if let declarationPath = context.assetPaths.keys
            .filter({ path.hasPrefix($0 + "/") })
            .max(by: { $0.count < $1.count }),
           let resolvedBasePath = context.assetPaths[declarationPath] {
            let suffix = String(path.dropFirst(declarationPath.count + 1))
            return escapeAttribute(join(resolvedBasePath, suffix))
        }
        return escapeAttribute(join(context.assetBasePath, path))
    }


    private static func packageValueString(_ value: BlockPackageValue) -> String {
        switch value {
        case .string(let value): escape(value)
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueString).joined(separator: ", ")
        case .object: ""
        }
    }

    private static func packageValueRawString(_ value: BlockPackageValue) -> String {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueRawString).joined(separator: ", ")
        case .object: ""
        }
    }

    private static func packageValue(for key: String, context: BlockTemplateContext) -> BlockPackageValue? {
        guard key.hasPrefix("control.") else { return nil }
        let reference = String(key.dropFirst("control.".count))
        if let bracket = reference.lastIndex(of: "["), reference.hasSuffix("]"),
           let index = Int(reference[reference.index(after: bracket)..<reference.index(before: reference.endIndex)]),
           case .array(let values)? = context.allProperties[String(reference[..<bracket])],
           values.indices.contains(index) {
            return values[index]
        }
        return context.allProperties[reference]
    }

    private static func apply(filter: String, to value: String, context: BlockTemplateContext) -> String {
        guard let call = filterCall(filter),
              call.arguments.count == 1,
              let argument = numericFilterArgument(call.arguments[0], context: context) else { return value }
        switch call.name {
        case "lighten": return transformColor(value, target: 255, amount: argument / 100)
        case "darken": return transformColor(value, target: 0, amount: argument / 100)
        default: return value
        }
    }

    private static func filteredColor(
        for key: String,
        filters: [String],
        context: BlockTemplateContext
    ) -> String? {
        guard key.hasPrefix("control.") else { return nil }
        let reference = String(key.dropFirst("control.".count))
        guard case .string(let source)? = context.allProperties["\(reference).__colorSource"],
              case .string(let formatName)? = context.allProperties["\(reference).__colorFormat"],
              let format = BlockPackageControl.ColorOutputFormat(rawValue: formatName),
              var color = BlockColorChannels(hex: source) else { return nil }
        let declaredOpacity = context.allProperties["\(reference).__colorOpacity"] == .boolean(true)
        var includesOpacity = declaredOpacity

        for filter in filters {
            guard let call = filterCall(filter) else { return nil }
            if ["lighten", "darken"].contains(call.name), call.arguments.count == 1,
               let amount = numericFilterArgument(call.arguments[0], context: context) {
                let target = call.name == "lighten"
                    ? BlockColorChannels(red: 255, green: 255, blue: 255, alpha: color.alpha)
                    : BlockColorChannels(red: 0, green: 0, blue: 0, alpha: color.alpha)
                color = color.mixed(with: target, amount: amount / 100)
                continue
            }
            if call.name == "withAlpha", call.arguments.count == 1,
               let alpha = numericFilterArgument(call.arguments[0], context: context) {
                color = color.withAlpha(alpha)
                includesOpacity = true
                continue
            }
            if call.name == "mix", call.arguments.count == 2,
               let targetValue = colorFilterArgument(call.arguments[0], context: context),
               let target = BlockColorChannels(hex: targetValue),
               let amount = numericFilterArgument(call.arguments[1], context: context) {
                color = color.mixed(with: target, amount: amount / 100)
                continue
            }
            return nil
        }
        return color.formatted(as: format, includesOpacity: includesOpacity)
    }

    private static func filteredDate(
        for key: String,
        filters: [String],
        context: BlockTemplateContext
    ) -> String? {
        guard key.hasPrefix("control.") else { return nil }
        let reference = String(key.dropFirst("control.".count))
        guard case .string(let source)? = context.allProperties["\(reference).__dateSource"],
              var date = BlockDateValue(source) else { return nil }
        for (index, filter) in filters.enumerated() {
            guard let call = filterCall(filter) else { return nil }
            if ["addDays", "addMonths"].contains(call.name), call.arguments.count == 1,
               let amount = integerFilterArgument(call.arguments[0], context: context),
               let adjusted = date.adding(
                call.name == "addDays" ? .day : .month,
                value: amount
               ) {
                date = adjusted
                continue
            }
            if index == filters.indices.last, call.name == "formatDate", call.arguments.count == 1,
               let pattern = stringFilterArgument(call.arguments[0], context: context) {
                return date.formatted(pattern)
            }
            return nil
        }
        return date.isoDate
    }

    private static func filterCall(_ filter: String) -> (name: String, arguments: [String])? {
        guard let match = filterCallExpression.firstMatch(in: filter, range: NSRange(filter.startIndex..., in: filter)),
              let nameRange = Range(match.range(at: 1), in: filter),
              let argumentsRange = Range(match.range(at: 2), in: filter) else { return nil }
        return (String(filter[nameRange]), splitFilterArguments(String(filter[argumentsRange])))
    }

    private static func splitFilterArguments(_ source: String) -> [String] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        for character in source {
            if character == "\"" || character == "'" {
                quote = quote == character ? nil : (quote ?? character)
            }
            if character == ",", quote == nil {
                arguments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        arguments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return arguments
    }

    private static func filterArgument(_ argument: String, context: BlockTemplateContext) -> BlockPackageValue? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'" {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        if trimmed.hasPrefix("control.") {
            return packageValue(for: trimmed, context: context)
        }
        if let number = Double(trimmed) { return .number(number) }
        return nil
    }

    private static func numericFilterArgument(_ argument: String, context: BlockTemplateContext) -> Double? {
        guard let value = filterArgument(argument, context: context) else { return nil }
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string)
        default: return nil
        }
    }

    private static func integerFilterArgument(_ argument: String, context: BlockTemplateContext) -> Int? {
        guard let number = numericFilterArgument(argument, context: context),
              number.rounded(.towardZero) == number else { return nil }
        return Int(exactly: number)
    }

    private static func stringFilterArgument(_ argument: String, context: BlockTemplateContext) -> String? {
        guard let value = filterArgument(argument, context: context) else { return nil }
        if case .string(let string) = value { return string }
        return nil
    }

    private static func colorFilterArgument(_ argument: String, context: BlockTemplateContext) -> String? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("control."),
           case .string(let source)? = context.allProperties["\(trimmed.dropFirst("control.".count)).__colorSource"] {
            return source
        }
        return stringFilterArgument(argument, context: context)
    }

    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func encodeURL(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeSeparator = value.firstIndex(of: ":") {
            let scheme = String(value[..<schemeSeparator])
            if scheme.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#, options: .regularExpression) != nil,
               !["http", "https", "mailto", "tel"].contains(scheme.lowercased()) {
                return nil
            }
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private static func encodeJSON(_ value: BlockPackageValue) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              var result = String(data: data, encoding: .utf8) else { return nil }
        let replacements = [
            ("&", "\\u0026"),
            ("<", "\\u003C"),
            (">", "\\u003E"),
            ("\u{2028}", "\\u2028"),
            ("\u{2029}", "\\u2029")
        ]
        for (source, replacement) in replacements {
            result = result.replacingOccurrences(of: source, with: replacement)
        }
        return result
    }

    static func transformColor(_ value: String, target: Double, amount: Double) -> String {
        if value.hasPrefix("light-dark("), value.hasSuffix(")") {
            let contents = value.dropFirst(11).dropLast()
            var depth = 0
            if let split = contents.indices.first(where: { index in
                let character = contents[index]
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                return character == "," && depth == 0
            }) {
                let light = String(contents[..<split]).trimmingCharacters(in: .whitespaces)
                let dark = String(contents[contents.index(after: split)...]).trimmingCharacters(in: .whitespaces)
                return "light-dark(\(transformColor(light, target: target, amount: amount)), \(transformColor(dark, target: target, amount: amount)))"
            }
        }
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

    private static func renderConditions(in template: String, context: BlockTemplateContext) -> String {
        var result = template
        var remainingPasses = 100
        while let match = conditionBlockExpression.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let wholeRange = Range(match.range(at: 0), in: result),
              let conditionRange = Range(match.range(at: 1), in: result),
              let bodyRange = Range(match.range(at: 2), in: result),
              remainingPasses > 0 {
            remainingPasses -= 1
            let firstCondition = String(result[conditionRange])
            let body = String(result[bodyRange])
            let matches = conditionBranchExpression.matches(in: body, range: NSRange(body.startIndex..., in: body))
            var branches: [(condition: String?, body: String)] = []
            var condition: String? = firstCondition
            var start = body.startIndex
            for branchMatch in matches {
                guard let tagRange = Range(branchMatch.range(at: 0), in: body) else { continue }
                branches.append((condition, String(body[start..<tagRange.lowerBound])))
                condition = Range(branchMatch.range(at: 2), in: body).map { String(body[$0]) }
                start = tagRange.upperBound
            }
            branches.append((condition, String(body[start...])))
            let replacement = branches.first { branch in
                guard let condition = branch.condition else { return true }
                return conditionIsTrue(condition, context: context)
            }?.body ?? ""
            result.replaceSubrange(wholeRange, with: replacement)
        }
        return result
    }

    private static func conditionIsTrue(_ expression: String, context: BlockTemplateContext) -> Bool {
        guard let node = try? BlockTemplateExpression.parse(expression),
              let value = try? BlockTemplateExpression.evaluate(
                node,
                properties: context.allProperties,
                environment: context.environment
              ) else { return false }
        return value.isTruthy
    }

    private static func isTruthy(_ value: BlockPackageValue?) -> Bool {
        switch value {
        case .boolean(let value): value
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array(let values): !values.isEmpty
        case .object(let values): !values.isEmpty
        case nil: false
        }
    }

    private static func stringValue(_ value: BlockPackageValue?) -> String? {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueString).joined(separator: ", ")
        case .object: nil
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
