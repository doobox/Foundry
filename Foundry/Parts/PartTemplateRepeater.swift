import Foundation

nonisolated enum PartTemplateLoop {
    static let maximumIterationCount = 100
    static let maximumExpandedIterationCount = 10_000

    enum PrimitiveKind: Sendable {
        case text
        case html
        case image
        case svg
        case video
    }

    struct PrimitiveDeclaration: Sendable {
        let kind: PrimitiveKind
        let key: String
        let defaultValue: String?
        let isRepeated: Bool
    }

    struct Expansion: Sendable {
        let template: String
    }

    enum LoopError: Error, CustomStringConvertible {
        case unexpectedEnd
        case missingEnd
        case invalidCount(String)
        case expansionLimitExceeded

        var description: String {
            switch self {
            case .unexpectedEnd: "An endloop directive does not have a matching loop."
            case .missingEnd: "Every loop directive requires one endloop."
            case .invalidCount(let value): "Invalid loop count '\(value)'. Use an integer from 0 through \(maximumIterationCount), or a bounded numeric control."
            case .expansionLimitExceeded: "Nested loop blocks may expand to at most \(maximumExpandedIterationCount) total iterations."
            }
        }
    }

    static func declarations(in template: String) throws -> [PrimitiveDeclaration] {
        var parser = Parser(template)
        let nodes = try parser.nodes(expectsEnd: false)
        var state = PreparationState()
        _ = prepare(nodes, depth: 0, state: &state)
        return state.declarations
    }

    static func expand(
        _ template: String,
        properties: [String: PartPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool = false,
        environment: PartTemplateEnvironment = .published
    ) throws -> Expansion {
        var parser = Parser(template)
        let parsed = try parser.nodes(expectsEnd: false)
        var preparation = PreparationState()
        let nodes = prepare(parsed, depth: 0, state: &preparation)
        var expandedIterationCount = 0
        let output = try render(
            nodes,
            properties: properties,
            maximums: maximums,
            usingMaximumCounts: usingMaximumCounts,
            environment: environment,
            loopStack: [],
            expandedIterationCount: &expandedIterationCount
        )
        return .init(template: output)
    }

    private indirect enum Node {
        case text(String)
        case loop(String, [Node])
    }

    private struct LoopFrame {
        let source: String
        let itemLabel: String?
        let index: Int
        let emissionIndex: Int
        let pathIndex: Int
        let count: Int
        let alias: String?
        let item: PartPackageValue?
    }

    private struct PreparationState {
        var declarations: [PrimitiveDeclaration] = []
    }

    private static func prepare(
        _ nodes: [Node],
        depth: Int,
        state: inout PreparationState
    ) -> [Node] {
        nodes.map { node in
            switch node {
            case .text(let source):
                var result = replacePrimitives(in: source, expression: textExpression) { name, defaultValue in
                    state.declarations.append(.init(kind: .text, key: name, defaultValue: defaultValue, isRepeated: depth > 0))
                    return token(name: "__foundry_text", key: name, value: defaultValue, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: htmlExpression) { name, defaultValue in
                    state.declarations.append(.init(kind: .html, key: name, defaultValue: defaultValue, isRepeated: depth > 0))
                    return token(name: "__foundry_html", key: name, value: defaultValue, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: imageExpression) { name, _ in
                    state.declarations.append(.init(kind: .image, key: name, defaultValue: nil, isRepeated: depth > 0))
                    return token(name: "__foundry_image", key: name, value: nil, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: videoExpression) { name, _ in
                    state.declarations.append(.init(kind: .video, key: name, defaultValue: nil, isRepeated: depth > 0))
                    return token(name: "__foundry_video", key: name, value: nil, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: svgExpression) { name, _ in
                    state.declarations.append(.init(kind: .svg, key: name, defaultValue: nil, isRepeated: depth > 0))
                    return token(name: "__foundry_image", key: name, value: nil, isRepeated: depth > 0)
                }
                return .text(result)
            case .loop(let source, let children):
                return .loop(source, prepare(children, depth: depth + 1, state: &state))
            }
        }
    }

    private static func render(
        _ nodes: [Node],
        properties: [String: PartPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool,
        environment: PartTemplateEnvironment,
        loopStack: [LoopFrame],
        expandedIterationCount: inout Int
    ) throws -> String {
        var output = ""
        for node in nodes {
            switch node {
            case .text(let source):
                output += annotatePrimitivePaths(
                    in: replacingLoopValues(in: source, stack: loopStack, environment: environment),
                    path: loopStack.map(\.pathIndex)
                )
            case .loop(let source, let children):
                let directive = LoopDirective(source)
                let iterationProperties = propertiesForFrames(loopStack, base: properties)
                let sourceItems = collection(for: directive.source, properties: iterationProperties)
                let candidates: [(pathIndex: Int, item: PartPackageValue?)]
                if let sourceItems {
                    candidates = sourceItems.enumerated().compactMap { pathIndex, item in
                        guard let predicate = directive.predicate else { return (pathIndex, item) }
                        let frame = LoopFrame(
                            source: directive.source,
                            itemLabel: collectionItemLabel(for: directive.source, properties: iterationProperties),
                            index: pathIndex,
                            emissionIndex: pathIndex,
                            pathIndex: pathIndex,
                            count: sourceItems.count,
                            alias: directive.alias,
                            item: item
                        )
                        return predicateIsTrue(
                            predicate,
                            properties: propertiesForFrames(loopStack + [frame], base: properties),
                            environment: environment
                        ) ? (pathIndex, item) : nil
                    }
                } else {
                    let maximum = try maximumCount(for: directive.source, maximums: maximums)
                    let sourceCount = usingMaximumCounts
                        ? maximum
                        : currentCount(for: directive.source, properties: iterationProperties, maximum: maximum)
                    candidates = (0..<sourceCount).compactMap { pathIndex in
                        let frame = LoopFrame(
                            source: directive.source,
                            itemLabel: collectionItemLabel(for: directive.source, properties: iterationProperties),
                            index: pathIndex,
                            emissionIndex: pathIndex,
                            pathIndex: pathIndex,
                            count: sourceCount,
                            alias: directive.alias,
                            item: nil
                        )
                        guard let predicate = directive.predicate else { return (pathIndex, nil) }
                        return predicateIsTrue(
                            predicate,
                            properties: propertiesForFrames(loopStack + [frame], base: properties),
                            environment: environment
                        ) ? (pathIndex, nil) : nil
                    }
                }
                let normalizedCandidates = candidates.enumerated().map {
                    (index: $0.offset, pathIndex: $0.element.pathIndex, item: $0.element.item)
                }
                let orderedCandidates = directive.isReversed
                    ? Array(normalizedCandidates.reversed())
                    : normalizedCandidates
                let iterations = Array(orderedCandidates.prefix(maximumIterationCount))
                for (emissionIndex, candidate) in iterations.enumerated() {
                    let frame = LoopFrame(
                        source: directive.source,
                        itemLabel: collectionItemLabel(for: directive.source, properties: iterationProperties),
                        index: emissionIndex,
                        emissionIndex: emissionIndex,
                        pathIndex: candidate.pathIndex,
                        count: iterations.count,
                        alias: directive.alias,
                        item: candidate.item
                    )
                    let nextStack = loopStack + [frame]
                    expandedIterationCount += 1
                    guard expandedIterationCount <= maximumExpandedIterationCount else {
                        throw LoopError.expansionLimitExceeded
                    }
                    output += try render(
                        children,
                        properties: properties,
                        maximums: maximums,
                        usingMaximumCounts: usingMaximumCounts,
                        environment: environment,
                        loopStack: nextStack,
                        expandedIterationCount: &expandedIterationCount
                    )
                }
            }
        }
        return output
    }

    private struct LoopDirective {
        let source: String
        let alias: String?
        let predicate: String?
        let isReversed: Bool

        init(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            isReversed = trimmed.hasSuffix(" reversed")
            let body = isReversed
                ? String(trimmed.dropLast(" reversed".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            let predicateParts = body.components(separatedBy: " where ")
            let sourceAndAlias = predicateParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let aliasParts = sourceAndAlias.components(separatedBy: " as ")
            source = aliasParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            alias = aliasParts.count == 2 ? aliasParts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            predicate = predicateParts.count > 1
                ? predicateParts.dropFirst().joined(separator: " where ").trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        }
    }

    private static func collection(
        for source: String,
        properties: [String: PartPackageValue]
    ) -> [PartPackageValue]? {
        let key = source.hasPrefix("control.") ? String(source.dropFirst("control.".count)) : source
        if case .array(let values) = resolvedValue(key, properties: properties) { return values }
        if !source.hasPrefix("control."), source.contains(".") { return [] }
        return nil
    }

    private static func collectionItemLabel(
        for source: String,
        properties: [String: PartPackageValue]
    ) -> String? {
        guard source.hasPrefix("control.") else { return nil }
        let key = String(source.dropFirst("control.".count))
        return properties["__foundry_collection_label." + key]?.stringValue
    }

    private static func resolvedValue(
        _ key: String,
        properties: [String: PartPackageValue]
    ) -> PartPackageValue? {
        if let value = properties[key] { return value }
        let parts = key.split(separator: ".")
        for splitIndex in stride(from: parts.count - 1, through: 0, by: -1) {
            let root = parts[0...splitIndex].joined(separator: ".")
            if let value = properties[root]?.value(at: parts.dropFirst(splitIndex + 1)) { return value }
        }
        return nil
    }

    private static func propertiesForFrames(
        _ frames: [LoopFrame],
        base: [String: PartPackageValue]
    ) -> [String: PartPackageValue] {
        var result = base
        for frame in frames {
            guard let item = frame.item else { continue }
            result["loop.item"] = item
            if let alias = frame.alias { result[alias] = item }
        }
        return result
    }

    private static func predicateIsTrue(
        _ predicate: String,
        properties: [String: PartPackageValue],
        environment: PartTemplateEnvironment
    ) -> Bool {
        guard let expression = try? PartTemplateExpression.parse(predicate),
              let value = try? PartTemplateExpression.evaluate(
                expression, properties: properties, environment: environment
              ) else { return false }
        return value.isTruthy
    }

    private static func maximumCount(for source: String, maximums: [String: Int]) throws -> Int {
        if let literal = Int(source), (0...maximumIterationCount).contains(literal) { return literal }
        if source.hasPrefix("control."),
           let maximum = maximums[String(source.dropFirst("control.".count))],
           (0...maximumIterationCount).contains(maximum) { return maximum }
        throw LoopError.invalidCount(source)
    }

    private static func currentCount(
        for source: String,
        properties: [String: PartPackageValue],
        maximum: Int
    ) -> Int {
        guard source.hasPrefix("control."),
              case .number(let value) = properties[String(source.dropFirst("control.".count))],
              value.isFinite else { return Int(source) ?? 0 }
        return min(max(Int(value.rounded(.down)), 0), maximum)
    }

    private static func annotatePrimitivePaths(in source: String, path: [Int]) -> String {
        guard !path.isEmpty else { return source }
        return source.replacingOccurrences(
            of: #" repeated="true""#,
            with: #" repeated="true" path="\#(path.map(String.init).joined(separator: ","))""#
        )
    }

    private static func replacingLoopValues(
        in source: String,
        stack: [LoopFrame],
        environment: PartTemplateEnvironment
    ) -> String {
        guard let current = stack.last else { return source }
        var result = source
        let collectionAttributes: String
        if environment == .canvas, current.source.hasPrefix("control.") {
            let key = String(current.source.dropFirst("control.".count))
            let path = stack.map(\.pathIndex).map(String.init).joined(separator: ",")
            let label = (current.itemLabel ?? "Item")
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            collectionAttributes = "data-foundry-collection-property=\"\(key)\" data-foundry-collection-label=\"\(label)\" data-foundry-property-path=\"\(path)\""
        } else {
            collectionAttributes = ""
        }
        result = result.replacingOccurrences(of: "{{ loop.attributes }}", with: collectionAttributes)
        let values: [(String, String)] = [
            ("loop.sourceIndex", String(current.pathIndex)),
            ("loop.sourcePosition", String(current.pathIndex + 1)),
            ("loop.index", String(current.index)),
            ("loop.position", String(current.index + 1)),
            ("loop.count", String(current.count)),
            ("loop.first", current.emissionIndex == 0 ? "true" : "false"),
            ("loop.last", current.emissionIndex == current.count - 1 ? "true" : "false")
        ]
        for (key, value) in values { result = result.replacingOccurrences(of: key, with: value) }
        if stack.count > 1 {
            let parent = stack[stack.count - 2]
            result = result.replacingOccurrences(of: "loop.parent.sourceIndex", with: String(parent.pathIndex))
            result = result.replacingOccurrences(of: "loop.parent.sourcePosition", with: String(parent.pathIndex + 1))
            result = result.replacingOccurrences(of: "loop.parent.index", with: String(parent.index))
            result = result.replacingOccurrences(of: "loop.parent.position", with: String(parent.index + 1))
            result = result.replacingOccurrences(of: "loop.parent.count", with: String(parent.count))
            result = result.replacingOccurrences(of: "loop.parent.first", with: parent.emissionIndex == 0 ? "true" : "false")
            result = result.replacingOccurrences(of: "loop.parent.last", with: parent.emissionIndex == parent.count - 1 ? "true" : "false")
        }
        let properties = propertiesForFrames(stack, base: [:])
        result = replacingIterationValuesInConditions(in: result, properties: properties)
        let expression = try! NSRegularExpression(
            pattern: #"\{\{\s*((?:loop\.item|[A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\}\}"#
        )
        for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range(at: 0), in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            guard let value = resolvedValue(key, properties: properties) else { continue }
            if key.hasSuffix(".attributes"), case .string(let attributes) = value {
                result.replaceSubrange(range, with: attributes)
            } else {
                result.replaceSubrange(range, with: escapedOutput(value))
            }
        }
        return result
    }

    private static func replacingIterationValuesInConditions(
        in source: String,
        properties: [String: PartPackageValue]
    ) -> String {
        var result = source
        let directive = try! NSRegularExpression(pattern: #"\{\{\s*(?:if|elseif)\s+([^{}]+?)\s*\}\}"#)
        let variable = try! NSRegularExpression(pattern: #"\b(?:loop\.item|[A-Za-z_][A-Za-z0-9_]*)(?:\.[A-Za-z_][A-Za-z0-9_]*)*\b"#)
        for match in directive.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let conditionRange = Range(match.range(at: 1), in: result) else { continue }
            var condition = String(result[conditionRange])
            for variableMatch in variable.matches(in: condition, range: NSRange(condition.startIndex..., in: condition)).reversed() {
                guard let range = Range(variableMatch.range, in: condition),
                      let value = resolvedValue(String(condition[range]), properties: properties) else { continue }
                condition.replaceSubrange(range, with: expressionLiteral(value))
            }
            result.replaceSubrange(conditionRange, with: condition)
        }
        return result
    }

    private static func expressionLiteral(_ value: PartPackageValue) -> String {
        switch value {
        case .string(let value):
            return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case .number(let value):
            return value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value):
            return value ? "true" : "false"
        case .array(let values):
            return values.isEmpty ? "false" : "true"
        case .object(let values):
            return values.isEmpty ? "false" : "true"
        }
    }

    private static func escapedOutput(_ value: PartPackageValue) -> String {
        let result: String = switch value {
        case .string(let value): value
        case .number(let value): value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        case .boolean(let value): value ? "true" : "false"
        case .array, .object: ""
        }
        return result
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func replacePrimitives(
        in source: String,
        expression: NSRegularExpression,
        replacement: (String, String?) -> String
    ) -> String {
        var result = source
        let replacements = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range(at: 0), in: result) else { return nil }
            guard let nameRange = Range(match.range(at: 1), in: result) else { return nil }
            let name = String(result[nameRange])
            let value = match.numberOfRanges > 2
                ? Range(match.range(at: 2), in: result).map { decodeStringLiteral(String(result[$0])) }
                : nil
            return (range, replacement(name, value))
        }
        for (range, value) in replacements.reversed() { result.replaceSubrange(range, with: value) }
        return result
    }

    private static func token(name: String, key: String, value: String?, isRepeated: Bool) -> String {
        let encoded = value.map { Data($0.utf8).base64EncodedString() } ?? "~"
        let defaultMarker = name == "__foundry_image" || name == "__foundry_video" ? "" : " default=\"\(encoded)\""
        let repeatedMarker = isRepeated ? " repeated=\"true\"" : ""
        return "{{ \(name) key=\"\(key)\"\(defaultMarker)\(repeatedMarker) }}"
    }

    private static func decodeStringLiteral(_ source: String) -> String {
        let json = "\"\(source)\""
        return (try? JSONDecoder().decode(String.self, from: Data(json.utf8))) ?? source
    }

    private static let directiveExpression = try! NSRegularExpression(pattern: #"\{\{\s*(loop\s+([^{}]+?)|endloop)\s*\}\}"#)
    private static let imageExpression = try! NSRegularExpression(pattern: #"\{\{\s*image\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*\}\}"#)
    private static let svgExpression = try! NSRegularExpression(pattern: #"\{\{\s*svg\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*\}\}"#)
    private static let videoExpression = try! NSRegularExpression(pattern: #"\{\{\s*video\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*\)\s*\}\}"#)
    private static let textExpression = try! NSRegularExpression(pattern: #"\{\{\s*text\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*(?:,\s*default\s*:\s*\"((?:\\.|[^\"\\])*)\"\s*)?\)\s*\}\}"#)
    private static let htmlExpression = try! NSRegularExpression(pattern: #"\{\{\s*html\(\s*\"([A-Za-z][A-Za-z0-9_-]*)\"\s*(?:,\s*default\s*:\s*\"((?:\\.|[^\"\\])*)\"\s*)?\)\s*\}\}"#)

    private struct Parser {
        let source: String
        var location = 0

        init(_ source: String) { self.source = source }

        mutating func nodes(expectsEnd: Bool) throws -> [Node] {
            var result: [Node] = []
            while location < source.utf16.count {
                let searchRange = NSRange(location: location, length: source.utf16.count - location)
                guard let match = directiveExpression.firstMatch(in: source, range: searchRange) else {
                    result.append(.text(substring(searchRange)))
                    location = source.utf16.count
                    break
                }
                if match.range.location > location {
                    result.append(.text(substring(NSRange(location: location, length: match.range.location - location))))
                }
                location = NSMaxRange(match.range)
                let directive = substring(match.range(at: 1))
                if directive == "endloop" {
                    if expectsEnd { return result }
                    throw LoopError.unexpectedEnd
                }
                result.append(.loop(substring(match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines), try nodes(expectsEnd: true)))
            }
            if expectsEnd { throw LoopError.missingEnd }
            return result
        }

        private func substring(_ range: NSRange) -> String {
            Range(range, in: source).map { String(source[$0]) } ?? ""
        }
    }
}
