import Foundation

nonisolated enum PartTemplateEnvironment: String, Equatable, Sendable {
    case canvas
    case preview
    case published
}

nonisolated struct PartTemplateContext: Sendable {
    let instanceID: UUID
    let packageIdentifier: String
    let properties: [String: PartPackageValue]
    let templateValues: [String: PartPackageValue]
    let slots: [String: String]
    let dropZones: [String: String]
    let partClass: String
    let partAttributes: String
    let assetBasePath: String
    let assetPaths: [String: String]
    let siteBaseURL: String
    let pageURL: String
    let siteRootPath: String
    let siteAssetsPath: String
    let enablesEditorMarkup: Bool
    let environment: PartTemplateEnvironment
    let richTextLinkContext: FoundryRichTextCodec.LinkContext?
    let richTextColourContext: FoundryRichTextCodec.ColourContext?
    let loopMaximums: [String: Int]

    var allProperties: [String: PartPackageValue] {
        properties.merging(templateValues) { current, _ in current }
    }

    init(
        instanceID: UUID,
        packageIdentifier: String,
        properties: [String: PartPackageValue],
        templateValues: [String: PartPackageValue] = [:],
        slots: [String: String],
        dropZones: [String: String] = [:],
        partClass: String = "",
        partAttributes: String = "",
        assetBasePath: String = "",
        assetPaths: [String: String] = [:],
        siteBaseURL: String = "",
        pageURL: String = "",
        siteRootPath: String = "",
        siteAssetsPath: String = "",
        enablesEditorMarkup: Bool = false,
        environment: PartTemplateEnvironment = .published,
        richTextLinkContext: FoundryRichTextCodec.LinkContext? = nil,
        richTextColourContext: FoundryRichTextCodec.ColourContext? = nil,
        loopMaximums: [String: Int]
    ) {
        self.instanceID = instanceID
        self.packageIdentifier = packageIdentifier
        self.properties = properties
        self.templateValues = templateValues
        self.slots = slots
        self.dropZones = dropZones
        self.partClass = partClass
        self.partAttributes = partAttributes
        self.assetBasePath = assetBasePath
        self.assetPaths = assetPaths
        self.siteBaseURL = siteBaseURL
        self.pageURL = pageURL
        self.siteRootPath = siteRootPath
        self.siteAssetsPath = siteAssetsPath
        self.enablesEditorMarkup = enablesEditorMarkup
        self.environment = environment
        self.richTextLinkContext = richTextLinkContext
        self.richTextColourContext = richTextColourContext
        self.loopMaximums = loopMaximums
    }

    init(
        instanceID: UUID,
        packageIdentifier: String,
        properties: [String: PartPackageValue],
        templateValues: [String: PartPackageValue] = [:],
        slots: [String: String],
        dropZones: [String: String] = [:],
        partClass: String = "",
        partAttributes: String = "",
        assetBasePath: String = "",
        assetPaths: [String: String] = [:],
        siteBaseURL: String = "",
        pageURL: String = "",
        siteRootPath: String = "",
        siteAssetsPath: String = "",
        enablesEditorMarkup: Bool = false,
        environment: PartTemplateEnvironment = .published,
        richTextLinkContext: FoundryRichTextCodec.LinkContext? = nil,
        richTextColourContext: FoundryRichTextCodec.ColourContext? = nil
    ) {
        self.init(
            instanceID: instanceID,
            packageIdentifier: packageIdentifier,
            properties: properties,
            templateValues: templateValues,
            slots: slots,
            dropZones: dropZones,
            partClass: partClass,
            partAttributes: partAttributes,
            assetBasePath: assetBasePath,
            assetPaths: assetPaths,
            siteBaseURL: siteBaseURL,
            pageURL: pageURL,
            siteRootPath: siteRootPath,
            siteAssetsPath: siteAssetsPath,
            enablesEditorMarkup: enablesEditorMarkup,
            environment: environment,
            richTextLinkContext: richTextLinkContext,
            richTextColourContext: richTextColourContext,
            loopMaximums: [:]
        )
    }
}

nonisolated struct PartTextPrimitive: Codable, Equatable, Sendable {
    let key: String
    let defaultValue: String
    let isRepeated: Bool
}

nonisolated struct PartHTMLPrimitive: Codable, Equatable, Sendable {
    let key: String
    let defaultValue: String
    let isRepeated: Bool
}

nonisolated struct PartImagePrimitive: Codable, Equatable, Sendable {
    let key: String
    let isRepeated: Bool
    var isSVG: Bool = false
}

nonisolated struct PartVideoPrimitive: Codable, Equatable, Sendable {
    let key: String
    let isRepeated: Bool
}

/// Inline SVG glyphs for the canvas drop zones — a rounded square framing a
/// down arrow for part areas, a photo mark for image wells, and a camera for
/// video wells. Filled with `currentColor` so the zone's label colour applies.
nonisolated enum FoundryDropZoneGlyphs {
    static let part = #"<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><path fill-rule="evenodd" d="M43.629,146.562C29.456,146.562 18.484,142.625 11.21,135.352C3.838,128.046 -0,117.071 -0,102.933L-0,43.629C-0,29.491 3.873,18.48 11.21,11.21C18.413,4.008 29.456,0 43.629,0L103.036,0C117.209,0 128.082,3.905 135.387,11.21C142.827,18.516 146.665,29.491 146.665,43.629L146.665,102.933C146.665,117.071 142.792,128.082 135.387,135.352C128.185,142.554 117.209,146.562 103.036,146.562L43.629,146.562ZM43.629,135.491L103.036,135.491C113.642,135.491 121.932,132.503 127.269,127.269C132.741,121.797 135.594,113.674 135.594,102.933L135.594,43.629C135.594,32.888 132.741,24.765 127.269,19.293C121.864,13.992 113.642,11.07 103.036,11.07L43.629,11.07C32.955,11.07 24.698,14.059 19.36,19.293C13.924,24.765 11.07,32.888 11.07,43.629L11.07,102.933C11.07,113.674 13.924,121.797 19.36,127.269C24.765,132.57 32.955,135.491 43.629,135.491Z"/><path d="M68.262,98.329L67.932,86.478L67.932,38.195C67.932,35.342 70.377,32.862 73.4,32.862C76.32,32.862 78.868,35.342 78.868,38.195L78.868,86.478L78.487,98.346L83.674,92.885L96.98,78.905C97.896,77.817 99.392,77.239 100.717,77.239C103.499,77.239 105.709,79.313 105.709,82.131C105.709,83.591 105.165,84.678 104.078,85.765L77.372,111.764C76.015,113.121 74.757,113.597 73.4,113.597C72.007,113.597 70.75,113.121 69.428,111.764L42.584,85.765C41.599,84.678 40.988,83.591 40.988,82.131C40.988,79.313 43.059,77.239 45.98,77.239C47.27,77.239 48.765,77.817 49.785,78.905L63.055,92.885L68.262,98.329Z"/></svg>"#
    static let image = #"<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><g transform="translate(-9.091185 -0.438)"><path fill-rule="evenodd" d="M52.72,147C38.547,147 27.575,143.063 20.302,135.79C12.929,128.484 9.091,117.509 9.091,103.371L9.091,44.067C9.091,29.929 12.964,18.918 20.302,11.648C27.504,4.446 38.547,0.438 52.72,0.438L112.127,0.438C126.3,0.438 137.173,4.343 144.478,11.648C151.918,18.954 155.756,29.929 155.756,44.067L155.756,103.371C155.756,117.509 151.883,128.52 144.478,135.79C137.276,142.992 126.3,147 112.127,147L52.72,147ZM52.72,135.929L112.127,135.929C122.733,135.929 131.023,132.941 136.36,127.707C141.832,122.235 144.685,114.112 144.685,103.371L144.685,44.067C144.685,33.326 141.832,25.203 136.36,19.731C130.955,14.429 122.733,11.508 112.127,11.508L52.72,11.508C42.046,11.508 33.789,14.497 28.452,19.731C23.015,25.203 20.162,33.326 20.162,44.067L20.162,103.371C20.162,114.112 23.015,122.235 28.452,127.707C33.856,133.008 42.046,135.929 52.72,135.929ZM30.162,98.861L36.146,93.384C39.44,90.328 42.831,88.816 46.511,88.816C50.497,88.816 54.061,90.431 57.458,93.487L72.564,107.297L109.117,74.624C112.964,71.22 116.872,69.57 121.443,69.57C125.95,69.57 130.132,71.323 133.844,74.727L134.685,75.51L134.685,103.371C134.685,110.885 133.154,116.725 129.35,120.574C125.558,124.269 119.584,125.929 112.127,125.929L52.72,125.929C45.241,125.929 39.349,124.33 35.533,120.645C31.704,116.758 30.162,110.906 30.162,103.371L30.162,98.861ZM59.536,74.562C49.036,74.562 40.493,66.018 40.493,55.518C40.493,45.121 49.036,36.475 59.536,36.475C69.933,36.475 78.476,45.121 78.476,55.518C78.476,66.018 69.933,74.562 59.536,74.562Z"/></g></svg>"#
    static let video = #"<svg viewBox="0 0 147 147" width="22" height="22" fill="currentColor"><g transform="translate(-9.091185 -0.438)"><path fill-rule="evenodd" d="M52.72,147C38.547,147 27.575,143.063 20.302,135.79C12.929,128.484 9.091,117.509 9.091,103.371L9.091,44.067C9.091,29.929 12.964,18.918 20.302,11.648C27.504,4.446 38.547,0.438 52.72,0.438L112.127,0.438C126.3,0.438 137.173,4.343 144.478,11.648C151.918,18.954 155.756,29.929 155.756,44.067L155.756,103.371C155.756,117.509 151.883,128.52 144.478,135.79C137.276,142.992 126.3,147 112.127,147L52.72,147ZM52.72,135.929L112.127,135.929C122.733,135.929 131.023,132.941 136.36,127.707C141.832,122.235 144.685,114.112 144.685,103.371L144.685,44.067C144.685,33.326 141.832,25.203 136.36,19.731C130.955,14.429 122.733,11.508 112.127,11.508L52.72,11.508C42.046,11.508 33.789,14.497 28.452,19.731C23.015,25.203 20.162,33.326 20.162,44.067L20.162,103.371C20.162,114.112 23.015,122.235 28.452,127.707C33.856,133.008 42.046,135.929 52.72,135.929ZM49.179,106.225C41.111,106.225 36.382,101.596 36.382,93.599L36.382,54.515C36.382,46.451 41.313,41.889 49.179,41.889L92.062,41.889C100.126,41.889 104.552,46.451 104.552,54.515L104.552,93.599C104.552,101.596 99.856,106.225 91.791,106.225L49.179,106.225ZM108.94,85.11L108.94,62.968L124.322,50.031C125.66,48.934 127.233,48.146 128.674,48.146C131.544,48.146 133.493,50.262 133.493,53.447L133.493,94.599C133.493,97.851 131.544,99.968 128.674,99.968C127.233,99.968 125.728,99.18 124.322,98.015L108.94,85.11Z"/></g></svg>"#
}

nonisolated enum PartTemplateRenderer {
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
    private static let videoExpression = try! NSRegularExpression(pattern: #"\{\{\s*video\(\s*\"[A-Za-z][A-Za-z0-9_-]*\"\s*\)\s*\}\}"#)
    private static let filterCallExpression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)\(\s*(.*?)\s*\)$"#)
    private static let outputEncodingFilters: Set<String> = [
        "escapeHTML", "escapeHTMLAttribute", "encodeURL", "encodeURIComponent", "encodeJSON"
    ]
    private static let conditionBoundaryExpression = try! NSRegularExpression(pattern: #"\{\{\s*(if\s+([^{}]+?)|endif)\s*\}\}"#)
    private static let conditionBranchExpression = try! NSRegularExpression(pattern: #"\{\{\s*(elseif\s+([^{}]+?)|else)\s*\}\}"#)
    private static let keyedTextExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_text\s+key=\"([^\"]+)\"\s+default=\"([^\"]*)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let keyedHTMLExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_html\s+key=\"([^\"]+)\"\s+default=\"([^\"]*)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let keyedImageExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_image\s+key=\"([^\"]+)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let keyedVideoExpression = try! NSRegularExpression(pattern: #"\{\{\s*__foundry_video\s+key=\"([^\"]+)\"(?:\s+repeated=\"(true)\"\s+path=\"([0-9,]+)\")?\s*\}\}"#)
    private static let controlledVideoElementExpression = try! NSRegularExpression(
        pattern: #"<video\b([^>]*?)\bsrc\s*=\s*([\"'])\{\{\s*control\.([A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*?)(\.source|\.href)?\s*\}\}\2([^>]*)>(.*?)</video\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let controlledImageElementExpression = try! NSRegularExpression(
        pattern: #"<img\b([^>]*?)\bsrc\s*=\s*([\"'])\{\{\s*control\.([A-Za-z][A-Za-z0-9_-]*)(\.rendition\.[A-Za-z][A-Za-z0-9_-]*(?:\.href)?|\.href)?\s*\}\}\2([^>]*)>"#,
        options: [.caseInsensitive]
    )

    static func render(_ template: String, context: PartTemplateContext) -> String {
        let loopMaximums = context.loopMaximums.isEmpty
            ? PartRegistry.definition(for: .init(rawValue: context.packageIdentifier)).package?.loopMaximums ?? [:]
            : context.loopMaximums
        let expanded = (try? PartTemplateLoop.expand(
            template,
            properties: context.allProperties,
            maximums: loopMaximums,
            environment: context.environment
        ).template) ?? template
        var result = renderControlledImageElements(in: expanded, context: context)
        result = renderControlledVideoElements(in: result, context: context)
        result = renderText(in: result, context: context)
        result = renderImage(in: result, context: context)
        result = renderVideo(in: result, context: context)
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

    static func textPrimitives(in template: String) -> [PartTextPrimitive] {
        textPrimitives(in: template, loopMaximums: [:])
    }

    static func textPrimitives(in template: String, loopMaximums: [String: Int]) -> [PartTextPrimitive] {
        (try? PartTemplateLoop.declarations(in: template))?.compactMap {
            guard case .text = $0.kind else { return nil }
            return .init(key: $0.key, defaultValue: $0.defaultValue ?? loremParagraph, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func hasImagePrimitive(in template: String) -> Bool {
        imageExpression.firstMatch(in: template, range: NSRange(template.startIndex..., in: template)) != nil
    }

    static func hasVideoPrimitive(in template: String) -> Bool {
        videoExpression.firstMatch(in: template, range: NSRange(template.startIndex..., in: template)) != nil
    }

    static func htmlPrimitives(in template: String) -> [PartHTMLPrimitive] {
        htmlPrimitives(in: template, loopMaximums: [:])
    }

    static func htmlPrimitives(in template: String, loopMaximums: [String: Int]) -> [PartHTMLPrimitive] {
        (try? PartTemplateLoop.declarations(in: template))?.compactMap {
            guard case .html = $0.kind else { return nil }
            return .init(key: $0.key, defaultValue: $0.defaultValue ?? htmlDefault, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func imagePrimitives(in template: String) -> [PartImagePrimitive] {
        (try? PartTemplateLoop.declarations(in: template))?.compactMap {
            switch $0.kind {
            case .image: return .init(key: $0.key, isRepeated: $0.isRepeated)
            case .svg: return .init(key: $0.key, isRepeated: $0.isRepeated, isSVG: true)
            default: return nil
            }
        } ?? []
    }

    static func videoPrimitives(in template: String) -> [PartVideoPrimitive] {
        (try? PartTemplateLoop.declarations(in: template))?.compactMap {
            guard case .video = $0.kind else { return nil }
            return .init(key: $0.key, isRepeated: $0.isRepeated)
        } ?? []
    }

    static func scopedCSS(_ css: String, packageIdentifier: String, instanceID: UUID) -> String {
        let instanceSelector = "[data-foundry-id=\"\(instanceID.uuidString)\"]"
        let parentSelector = "[data-foundry-part]:has(\(instanceSelector)):not(:has([data-foundry-part] \(instanceSelector)))"
        return css.replacingOccurrences(
            of: ":parent",
            with: parentSelector
        ).replacingOccurrences(
            of: ":instance",
            with: instanceSelector
        ).replacingOccurrences(
            of: ":host",
            with: ":is([data-foundry-package=\"\(escapeAttribute(packageIdentifier))\"], .\(packageClass(for: packageIdentifier)))"
        )
    }

    /// An instance's custom CSS, nested inside its own selector so nothing
    /// can reach beyond the part: bare declarations style the part, nested
    /// rules its descendants, and `:instance` becomes `&`. Selectors that
    /// start with a pseudo-class or pseudo-element attach to their parent, so
    /// `:hover { … }` means the part when hovered rather than a hovered
    /// descendant. The doubled selector outranks the part's own rules,
    /// including later breakpoint rules, so the author's CSS always wins.
    /// Closing `</style` sequences are escaped so the text can never end the
    /// surrounding style element.
    static func scopedCustomCSS(_ css: String?, instanceID: UUID) -> String {
        let trimmed = (css ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let selector = "[data-foundry-id=\"\(instanceID.uuidString)\"]"
        let body = attachingLeadingPseudoSelectors(trimmed.replacingOccurrences(of: ":instance", with: "&"))
            .replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
        return "\(selector)\(selector) {\n\(body)\n}"
    }

    /// Prefixes `&` to every selector in a rule prelude that starts with `:`.
    /// Only preludes ending in `{` are rules; declarations end in `;`, and
    /// at-rules such as `@media` are left alone. Comments and strings are
    /// skipped so their contents are never mistaken for selectors.
    ///
    /// Braces are balanced on the way through: a stray `}` would close the
    /// instance wrapper early and let what follows escape the part, and an
    /// unclosed `{` would swallow the next instance's styles in a shared
    /// stylesheet. Unmatched closing braces are dropped and missing ones added.
    private static func attachingLeadingPseudoSelectors(_ css: String) -> String {
        let characters = Array(css)
        var output = ""
        var segment = ""
        var index = 0
        var depth = 0
        func flushRule() {
            let prelude = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prelude.hasPrefix("@") else {
                output += segment
                return
            }
            var parts: [String] = []
            var current = ""
            var depth = 0
            for character in segment {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if character == ",", depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            }
            parts.append(current)
            output += parts.map { part in
                let leading = part.prefix { $0.isWhitespace }
                let rest = part.dropFirst(leading.count)
                return rest.hasPrefix(":") ? leading + "&" + rest : part
            }.joined(separator: ",")
        }
        while index < characters.count {
            let character = characters[index]
            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                var end = index + 2
                while end + 1 < characters.count, !(characters[end] == "*" && characters[end + 1] == "/") { end += 1 }
                end = min(end + 2, characters.count)
                segment += String(characters[index..<end])
                index = end
                continue
            }
            if character == "\"" || character == "'" {
                var end = index + 1
                while end < characters.count, characters[end] != character {
                    if characters[end] == "\\" { end += 1 }
                    end += 1
                }
                end = min(end + 1, characters.count)
                segment += String(characters[index..<end])
                index = end
                continue
            }
            switch character {
            case "{":
                flushRule()
                output.append(character)
                segment = ""
                depth += 1
            case "}":
                output += segment
                segment = ""
                if depth > 0 {
                    output.append(character)
                    depth -= 1
                }
            case ";":
                output += segment
                output.append(character)
                segment = ""
            default:
                segment.append(character)
            }
            index += 1
        }
        output += segment
        output += String(repeating: "\n}", count: depth)
        return output
    }

    static func packageClass(for packageIdentifier: String) -> String {
        "foundry-package-" + packageIdentifier.map { character in
            character.isLetter || character.isNumber || character == "-" ? String(character) : "-"
        }.joined()
    }

    private static func renderText(in template: String, context: PartTemplateContext) -> String {
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

    private static func renderImage(in template: String, context: PartTemplateContext) -> String {
        var result = template
        let keyedMatches = keyedImageExpression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in keyedMatches {
            guard let range = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            let path = indexPath(match, group: 3, in: result)
            if context.allProperties["__foundry_svg." + key] == .boolean(true) {
                result.replaceSubrange(range, with: stringValue(value(context.allProperties[key], at: path)) ?? PartSVGRenderer.fragment(markup: "", key: key, path: path, canvas: context.enablesEditorMarkup))
                continue
            }
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

    private static func renderVideo(in template: String, context: PartTemplateContext) -> String {
        var result = template
        let keyedMatches = keyedVideoExpression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in keyedMatches {
            guard let range = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            let path = indexPath(match, group: 3, in: result)
            result.replaceSubrange(
                range,
                with: renderedVideo(
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

    /// Rewrites a part's own `<video src="{{ control.film }}">`: an unset
    /// video becomes a drop well, and the canvas keeps the poster but never
    /// the source, so the editor never streams a movie.
    private static func renderControlledVideoElements(
        in template: String,
        context: PartTemplateContext
    ) -> String {
        var result = template
        let matches = controlledVideoElementExpression.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let beforeRange = Range(match.range(at: 1), in: result),
                  let keyRange = Range(match.range(at: 3), in: result),
                  let afterRange = Range(match.range(at: 5), in: result),
                  let innerRange = Range(match.range(at: 6), in: result) else { continue }
            let key = String(result[keyRange])
            let before = String(result[beforeRange])
            let after = String(result[afterRange])
            let inner = String(result[innerRange])
            let isSelected = !(stringValue(context.allProperties[key]) ?? "").isEmpty
            if let id = YouTubeVideo.id(from: stringValue(context.allProperties[key]) ?? "") {
                let attributes = (before + after)
                    .replacingOccurrences(of: "poster=\"{{ control.\(key).poster }}\"", with: "")
                    .replacingOccurrences(of: "{{ control.\(key).attributes }}", with: "")
                let media: String
                let posterFirst = stringValue(context.allProperties[key + ".posterFirst"]) != "false"
                let customPoster = stringValue(context.allProperties[key + ".customPoster"]) == "true"
                let poster = stringValue(context.allProperties[key + ".poster"]) ?? YouTubeVideo.poster(for: id)
                let posterSource = context.assetPaths[poster] ?? poster
                let thumbnailAttribute = customPoster ? "" : " data-foundry-youtube-thumbnail=\"\(id)\""
                let image = "<img\(thumbnailAttribute) src=\"\(escapeAttribute(posterSource))\" alt=\"\" style=\"position:absolute;inset:0;display:block;width:100%;height:100%;object-fit:cover\">"
                let playIcon = "<span aria-hidden=\"true\" style=\"position:absolute;inset:0;display:grid;place-items:center;pointer-events:none\"><span style=\"display:grid;place-items:center;width:72px;height:72px;border-radius:50%;background:rgba(0,0,0,.7);color:white;font:32px system-ui\">&#9654;</span></span>"
                let source = YouTubeVideo.embed(for: id, controls: stringValue(context.allProperties[key + ".controls"]) != "false", loops: stringValue(context.allProperties[key + ".loop"]) == "true", start: Double(stringValue(context.allProperties[key + ".startAt"]) ?? "0") ?? 0)
                if context.enablesEditorMarkup {
                    media = image + (posterFirst ? playIcon : "")
                } else if posterFirst {
                    media = "<button type=\"button\" aria-label=\"Play YouTube video\" data-foundry-youtube-play=\"\(escapeAttribute(source))\" style=\"position:absolute;inset:0;display:block;width:100%;height:100%;padding:0;border:0;background:#161616;cursor:pointer\">\(image)\(playIcon)</button><script>\(YouTubePosterPlayback.javaScript)\n\(CanvasYouTubeThumbnails.javaScript)</script><noscript><a href=\"https://www.youtube.com/watch?v=\(id)\">Watch on YouTube</a></noscript>"
                } else {
                    media = "<iframe src=\"\(escapeAttribute(source))\" title=\"YouTube video\" loading=\"lazy\" referrerpolicy=\"strict-origin-when-cross-origin\" allow=\"encrypted-media; picture-in-picture; fullscreen\" allowfullscreen style=\"display:block;width:100%;height:100%;border:0;min-height:200px\"></iframe>"
                }
                let editor = context.enablesEditorMarkup ? " data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(key))\"" : ""
                result.replaceSubrange(wholeRange, with: "<div\(attributes)\(editor)><div style=\"position:relative;overflow:hidden;aspect-ratio:16/9;min-height:200px;background:#161616\">\(media)</div></div>")
                continue
            }
            if !isSelected {
                if context.enablesEditorMarkup {
                    let attributes = addingCSSClass("foundry-video-drop-zone", to: before + after)
                    result.replaceSubrange(
                        wholeRange,
                        with: "<span\(attributes) data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(key))\"><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.video)</span></span>"
                    )
                } else {
                    result.removeSubrange(wholeRange)
                }
                continue
            }
            if context.enablesEditorMarkup {
                if RemoteVideoImport.webURL(stringValue(context.allProperties[key]) ?? "") != nil,
                   (context.allProperties[key + ".poster"]?.stringValue ?? "").isEmpty {
                    let attributes = addingCSSClass("foundry-video-drop-zone", to: before + after)
                    result.replaceSubrange(wholeRange, with: "<span\(attributes) data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(key))\"><span class=\"foundry-drop-label\">Linked video</span></span>")
                    continue
                }
                // No src on the canvas: the author's poster attribute stands in.
                result.replaceSubrange(
                    wholeRange,
                    with: "<video\(before)\(after) data-foundry-video-drop-zone data-foundry-video-property=\"\(escapeAttribute(key))\">\(inner)</video>"
                )
                continue
            }
            let source = stringValue(context.allProperties[key + ".source"])
                ?? stringValue(context.allProperties[key]) ?? ""
            let resolvedSource = context.assetPaths[source] ?? source
            result.replaceSubrange(
                wholeRange,
                with: "<video\(before)src=\"\(escapeAttribute(resolvedSource))\"\(after)>\(inner)</video>"
            )
        }
        return result
    }

    private static func renderControlledImageElements(
        in template: String,
        context: PartTemplateContext
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
                        with: "<span\(attributes) data-foundry-image-drop-zone data-foundry-image-property=\"\(escapeAttribute(key))\"><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.image)</span></span>"
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

    private static func renderHTML(in template: String, context: PartTemplateContext) -> String {
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

    private static func renderedText(_ value: String, context: PartTemplateContext) -> String {
        if var fragment = FoundryRichTextCodec.htmlFragment(from: value) {
            if let colours = context.richTextColourContext {
                fragment = FoundryRichTextCodec.resolvingColours(in: fragment, context: colours)
            }
            return context.richTextLinkContext.map { FoundryRichTextCodec.resolvingLinks(in: fragment, context: $0) } ?? fragment
        }
        return escapeText(value)
    }

    private static func renderedImage(
        source: String,
        key: String,
        marksSelectablePrimitive: Bool,
        indexPath: [Int],
        context: PartTemplateContext
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
            return "<span class=\"foundry-image-drop-zone\" data-foundry-image-drop-zone\(propertyAttribute)\(primitiveAttribute)\(pathAttribute)><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.image)</span></span>"
        }
        let editorAttribute = context.enablesEditorMarkup ? " data-foundry-image-drop-zone\(propertyAttribute)" : ""
        return "<img class=\"fd-image\"\(editorAttribute)\(primitiveAttribute)\(pathAttribute) src=\"\(escapeAttribute(resolvedSource))\" alt=\"\">"
    }

    private static func renderedVideo(
        source: String,
        key: String,
        marksSelectablePrimitive: Bool,
        indexPath: [Int],
        context: PartTemplateContext
    ) -> String {
        let resolvedSource = context.assetPaths[source] ?? source
        let propertyAttribute = context.enablesEditorMarkup ? " data-foundry-video-property=\"\(escapeAttribute(key))\"" : ""
        let primitiveAttribute = context.enablesEditorMarkup && marksSelectablePrimitive
            ? " data-foundry-primitive-property=\"\(escapeAttribute(key))\""
            : ""
        let pathAttribute = context.enablesEditorMarkup && !indexPath.isEmpty
            ? " data-foundry-property-path=\"\(indexPath.map(String.init).joined(separator: ","))\""
            : ""
        if resolvedSource.isEmpty && context.enablesEditorMarkup {
            return "<span class=\"foundry-video-drop-zone\" data-foundry-video-drop-zone\(propertyAttribute)\(primitiveAttribute)\(pathAttribute)><span class=\"foundry-drop-label\">\(FoundryDropZoneGlyphs.video)</span></span>"
        }
        if let id = YouTubeVideo.id(from: source) {
            if context.enablesEditorMarkup {
                return "<span class=\"fd-video\" data-foundry-video-drop-zone\(propertyAttribute)\(primitiveAttribute)\(pathAttribute) style=\"display:block;position:relative;overflow:hidden;aspect-ratio:16/9;background:#161616\"><img data-foundry-youtube-thumbnail=\"\(id)\" src=\"\(YouTubeVideo.poster(for: id))\" alt=\"YouTube video thumbnail\" style=\"position:absolute;inset:0;width:100%;height:100%;object-fit:cover\"></span>"
            }
            return "<iframe class=\"fd-video\" src=\"\(escapeAttribute(YouTubeVideo.embed(for: id, controls: true, loops: false, start: 0)))\" title=\"YouTube video\" loading=\"lazy\" referrerpolicy=\"strict-origin-when-cross-origin\" allowfullscreen style=\"width:100%;aspect-ratio:16/9;min-height:200px;border:0\"></iframe>"
        }
        if context.enablesEditorMarkup {
            // On the canvas the movie itself is never loaded; the element shows
            // the generated poster frame and doubles as the replacement target.
            let poster = context.allProperties[key + ".poster"]?.stringValue ?? ""
            let posterAttribute = poster.isEmpty ? "" : " poster=\"\(escapeAttribute(poster))\""
            return "<video class=\"fd-video\" data-foundry-video-drop-zone\(propertyAttribute)\(primitiveAttribute)\(pathAttribute)\(posterAttribute) controls playsinline></video>"
        }
        if resolvedSource.isEmpty { return "" }
        return "<video class=\"fd-video\" src=\"\(escapeAttribute(resolvedSource))\" controls playsinline></video>"
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

    private static func value(_ value: PartPackageValue?, at path: [Int]) -> PartPackageValue? {
        path.reduce(value) { current, index in
            guard case .array(let values) = current, values.indices.contains(index) else { return nil }
            return values[index]
        }
    }

    private static func value(forExpression expression: String, context: PartTemplateContext) -> String {
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
        let parts = PartTemplateExpression.templateParts(expression)
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
        let simpleValue = #"^(?:instance\.id|package\.id|site\.baseURL|page\.url|path\.(?:siteRoot|siteAssets)|part\.(?:class|attributes)|controlGroup\.background|control\.[A-Za-z][A-Za-z0-9_.-]*(?:\[[0-9]+\])?)$"#
        var result: String
        if key.range(of: simpleValue, options: .regularExpression) != nil {
            result = value(for: key, context: context)
        } else if let node = try? PartTemplateExpression.parse(key),
                  let evaluated = try? PartTemplateExpression.evaluate(
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
        context: PartTemplateContext
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

    private static func value(for key: String, context: PartTemplateContext) -> String {
        if key == "instance.id" {
            return context.instanceID.uuidString
        }
        if key == "package.id" { return escape(context.packageIdentifier) }
        if key == "site.baseURL" { return escapeAttribute(context.siteBaseURL) }
        if key == "page.url" { return escapeAttribute(context.pageURL) }
        if key == "path.siteRoot" { return escapeAttribute(context.siteRootPath) }
        if key == "path.siteAssets" { return escapeAttribute(context.siteAssetsPath) }
        if key == "part.class" {
            return escapeAttribute(context.partClass)
        }
        if key == "part.attributes" { return context.partAttributes }
        guard key.hasPrefix("control.") else { return "" }
        let reference = String(key.dropFirst("control.".count))
        if !reference.contains("["),
           case .string(let element)? = context.allProperties[reference + ".element"] {
            return element
        }
        let value: PartPackageValue
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
        // A control group's composed values are finished CSS declarations and
        // markup, so they reach the template unescaped: escaping would turn
        // `url("…")` into `url(&quot;…&quot;)` and the background video element
        // into visible text. The resolvers escape the paths they compose them
        // from.
        if context.allProperties["__foundry_raw." + reference] == .boolean(true),
           case .string(let composed) = value {
            return composed
        }
        switch value {
        case .string(let value):
            let resolved = reference.hasSuffix(".href") ? context.assetPaths[value] ?? value : value
            return escape(resolved)
        case .number(let value): return value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): return value ? "true" : "false"
        case .array(let values): return values.map(packageValueString).joined(separator: ", ")
        case .object: return ""
        }
    }

    private static func assetPath(_ path: String, context: PartTemplateContext) -> String {
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


    private static func packageValueString(_ value: PartPackageValue) -> String {
        switch value {
        case .string(let value): escape(value)
        case .number(let value): value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueString).joined(separator: ", ")
        case .object: ""
        }
    }

    private static func packageValueRawString(_ value: PartPackageValue) -> String {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(packageValueRawString).joined(separator: ", ")
        case .object: ""
        }
    }

    private static func packageValue(for key: String, context: PartTemplateContext) -> PartPackageValue? {
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

    private static func apply(filter: String, to value: String, context: PartTemplateContext) -> String {
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
        context: PartTemplateContext
    ) -> String? {
        guard key.hasPrefix("control.") else { return nil }
        let reference = String(key.dropFirst("control.".count))
        guard case .string(let source)? = context.allProperties["\(reference).__colorSource"],
              case .string(let formatName)? = context.allProperties["\(reference).__colorFormat"],
              let format = PartPackageControl.ColorOutputFormat(rawValue: formatName),
              let color = PartColorChannels(hex: source) else { return nil }
        let declaredOpacity = context.allProperties["\(reference).__colorOpacity"] == .boolean(true)

        guard let light = applyColorFilters(filters, to: color, declaredOpacity: declaredOpacity, format: format, context: context) else { return nil }
        // A framework colour on a dual-appearance site carries a second source; the
        // filtered result stays appearance-aware the same way the base colour does.
        if case .string(let darkSource)? = context.allProperties["\(reference).__colorSourceDark"],
           let darkColor = PartColorChannels(hex: darkSource),
           let dark = applyColorFilters(filters, to: darkColor, declaredOpacity: declaredOpacity, format: format, context: context, prefersDarkArguments: true) {
            return light == dark ? light : "light-dark(\(light), \(dark))"
        }
        return light
    }

    private static func applyColorFilters(
        _ filters: [String],
        to source: PartColorChannels,
        declaredOpacity: Bool,
        format: PartPackageControl.ColorOutputFormat,
        context: PartTemplateContext,
        prefersDarkArguments: Bool = false
    ) -> String? {
        var color = source
        var includesOpacity = declaredOpacity

        for filter in filters {
            guard let call = filterCall(filter) else { return nil }
            if ["lighten", "darken"].contains(call.name), call.arguments.count == 1,
               let amount = numericFilterArgument(call.arguments[0], context: context) {
                let target = call.name == "lighten"
                    ? PartColorChannels(red: 255, green: 255, blue: 255, alpha: color.alpha)
                    : PartColorChannels(red: 0, green: 0, blue: 0, alpha: color.alpha)
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
               let targetValue = colorFilterArgument(call.arguments[0], context: context, prefersDark: prefersDarkArguments),
               let target = PartColorChannels(hex: targetValue),
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
        context: PartTemplateContext
    ) -> String? {
        guard key.hasPrefix("control.") else { return nil }
        let reference = String(key.dropFirst("control.".count))
        guard case .string(let source)? = context.allProperties["\(reference).__dateSource"],
              var date = PartDateValue(source) else { return nil }
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

    private static func filterArgument(_ argument: String, context: PartTemplateContext) -> PartPackageValue? {
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

    private static func numericFilterArgument(_ argument: String, context: PartTemplateContext) -> Double? {
        guard let value = filterArgument(argument, context: context) else { return nil }
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string)
        default: return nil
        }
    }

    private static func integerFilterArgument(_ argument: String, context: PartTemplateContext) -> Int? {
        guard let number = numericFilterArgument(argument, context: context),
              number.rounded(.towardZero) == number else { return nil }
        return Int(exactly: number)
    }

    private static func stringFilterArgument(_ argument: String, context: PartTemplateContext) -> String? {
        guard let value = filterArgument(argument, context: context) else { return nil }
        if case .string(let string) = value { return string }
        return nil
    }

    private static func colorFilterArgument(
        _ argument: String,
        context: PartTemplateContext,
        prefersDark: Bool = false
    ) -> String? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("control.") {
            let reference = trimmed.dropFirst("control.".count)
            if prefersDark, case .string(let darkSource)? = context.allProperties["\(reference).__colorSourceDark"] {
                return darkSource
            }
            if case .string(let source)? = context.allProperties["\(reference).__colorSource"] {
                return source
            }
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

    private static func encodeJSON(_ value: PartPackageValue) -> String? {
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
        // CSS wants a dot and no grouping whatever the user's region; the
        // default formatter follows the region and wrote "0,819" in German.
        let alpha = min(max(alpha, 0), 1).formatted(
            .number.grouping(.never).precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US_POSIX"))
        )
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

    private static func renderConditions(in template: String, context: PartTemplateContext) -> String {
        var result = template
        var remainingPasses = 100
        while remainingPasses > 0 {
            let boundaries = conditionBoundaryExpression.matches(in: result, range: NSRange(result.startIndex..., in: result))
            var opening: NSTextCheckingResult?
            var closing: NSTextCheckingResult?
            for boundary in boundaries {
                guard let keywordRange = Range(boundary.range(at: 1), in: result) else { continue }
                if result[keywordRange].hasPrefix("if") {
                    opening = boundary
                } else if opening != nil {
                    closing = boundary
                    break
                }
            }
            guard let opening, let closing,
                  let openingRange = Range(opening.range(at: 0), in: result),
                  let conditionRange = Range(opening.range(at: 2), in: result),
                  let closingRange = Range(closing.range(at: 0), in: result) else { break }
            remainingPasses -= 1
            let firstCondition = String(result[conditionRange])
            let body = String(result[openingRange.upperBound..<closingRange.lowerBound])
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
            result.replaceSubrange(openingRange.lowerBound..<closingRange.upperBound, with: replacement)
        }
        return result
    }

    private static func conditionIsTrue(_ expression: String, context: PartTemplateContext) -> Bool {
        guard let node = try? PartTemplateExpression.parse(expression),
              let value = try? PartTemplateExpression.evaluate(
                node,
                properties: context.allProperties,
                environment: context.environment
              ) else { return false }
        return value.isTruthy
    }

    private static func isTruthy(_ value: PartPackageValue?) -> Bool {
        switch value {
        case .boolean(let value): value
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array(let values): !values.isEmpty
        case .object(let values): !values.isEmpty
        case nil: false
        }
    }

    private static func stringValue(_ value: PartPackageValue?) -> String? {
        switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
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
