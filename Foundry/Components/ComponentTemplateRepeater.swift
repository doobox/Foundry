import Foundation

nonisolated enum ComponentTemplateRepeater {
    static let maximumIterationCount = 100
    static let maximumExpandedIterationCount = 10_000

    enum PrimitiveKind: Sendable {
        case text
        case html
        case image
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

    enum RepeatError: Error, CustomStringConvertible {
        case unexpectedEnd
        case missingEnd
        case invalidCount(String)
        case expansionLimitExceeded

        var description: String {
            switch self {
            case .unexpectedEnd: "An endrepeat directive does not have a matching repeat."
            case .missingEnd: "Every repeat directive requires one endrepeat."
            case .invalidCount(let value): "Invalid repeat count '\(value)'. Use an integer from 0 through \(maximumIterationCount), or a bounded numeric control."
            case .expansionLimitExceeded: "Nested repeat blocks may expand to at most \(maximumExpandedIterationCount) total iterations."
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
        properties: [String: ComponentPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool = false
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
            repeatStack: [],
            expandedIterationCount: &expandedIterationCount
        )
        return .init(template: output)
    }

    private indirect enum Node {
        case text(String)
        case repeated(String, [Node])
    }

    private struct RepeatFrame {
        let index: Int
        let count: Int
    }

    private struct PreparationState {
        var textIndex = 0
        var htmlIndex = 0
        var imageIndex = 0
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
                var result = replacePrimitives(in: source, expression: textExpression) { defaultValue in
                    state.textIndex += 1
                    let key = "content\(state.textIndex)"
                    state.declarations.append(.init(kind: .text, key: key, defaultValue: defaultValue, isRepeated: depth > 0))
                    return token(name: "__foundry_text", key: key, value: defaultValue, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: htmlExpression) { defaultValue in
                    state.htmlIndex += 1
                    let key = "html\(state.htmlIndex)"
                    state.declarations.append(.init(kind: .html, key: key, defaultValue: defaultValue, isRepeated: depth > 0))
                    return token(name: "__foundry_html", key: key, value: defaultValue, isRepeated: depth > 0)
                }
                result = replacePrimitives(in: result, expression: imageExpression) { _ in
                    state.imageIndex += 1
                    let key = "image\(state.imageIndex)"
                    state.declarations.append(.init(kind: .image, key: key, defaultValue: nil, isRepeated: depth > 0))
                    return token(name: "__foundry_image", key: key, value: nil, isRepeated: depth > 0)
                }
                return .text(result)
            case .repeated(let source, let children):
                return .repeated(source, prepare(children, depth: depth + 1, state: &state))
            }
        }
    }

    private static func render(
        _ nodes: [Node],
        properties: [String: ComponentPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool,
        repeatStack: [RepeatFrame],
        expandedIterationCount: inout Int
    ) throws -> String {
        var output = ""
        for node in nodes {
            switch node {
            case .text(let source):
                output += annotatePrimitivePaths(
                    in: replacingRepeatValues(in: source, stack: repeatStack),
                    path: repeatStack.map(\.index)
                )
            case .repeated(let source, let children):
                let maximum = try maximumCount(for: source, maximums: maximums)
                let count = usingMaximumCounts ? maximum : currentCount(for: source, properties: properties, maximum: maximum)
                for index in 0..<count {
                    expandedIterationCount += 1
                    guard expandedIterationCount <= maximumExpandedIterationCount else {
                        throw RepeatError.expansionLimitExceeded
                    }
                    output += try render(
                        children,
                        properties: properties,
                        maximums: maximums,
                        usingMaximumCounts: usingMaximumCounts,
                        repeatStack: repeatStack + [.init(index: index, count: count)],
                        expandedIterationCount: &expandedIterationCount
                    )
                }
            }
        }
        return output
    }

    private static func maximumCount(for source: String, maximums: [String: Int]) throws -> Int {
        if let literal = Int(source), (0...maximumIterationCount).contains(literal) { return literal }
        if source.hasPrefix("control."),
           let maximum = maximums[String(source.dropFirst("control.".count))],
           (0...maximumIterationCount).contains(maximum) { return maximum }
        throw RepeatError.invalidCount(source)
    }

    private static func currentCount(
        for source: String,
        properties: [String: ComponentPackageValue],
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

    private static func replacingRepeatValues(in source: String, stack: [RepeatFrame]) -> String {
        guard let current = stack.last else { return source }
        var result = source
        let values: [(String, String)] = [
            ("repeat.index", String(current.index)),
            ("repeat.position", String(current.index + 1)),
            ("repeat.count", String(current.count)),
            ("repeat.first", current.index == 0 ? "true" : "false"),
            ("repeat.last", current.index == current.count - 1 ? "true" : "false")
        ]
        for (key, value) in values { result = result.replacingOccurrences(of: key, with: value) }
        if stack.count > 1 {
            let parent = stack[stack.count - 2]
            result = result.replacingOccurrences(of: "repeat.parent.index", with: String(parent.index))
            result = result.replacingOccurrences(of: "repeat.parent.position", with: String(parent.index + 1))
            result = result.replacingOccurrences(of: "repeat.parent.count", with: String(parent.count))
            result = result.replacingOccurrences(of: "repeat.parent.first", with: parent.index == 0 ? "true" : "false")
            result = result.replacingOccurrences(of: "repeat.parent.last", with: parent.index == parent.count - 1 ? "true" : "false")
        }
        return result
    }

    private static func replacePrimitives(
        in source: String,
        expression: NSRegularExpression,
        replacement: (String?) -> String
    ) -> String {
        var result = source
        let replacements = expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range(at: 0), in: result) else { return nil }
            let value = match.numberOfRanges > 1
                ? Range(match.range(at: 1), in: result).map { String(result[$0]) }
                : nil
            return (range, replacement(value))
        }
        for (range, value) in replacements.reversed() { result.replaceSubrange(range, with: value) }
        return result
    }

    private static func token(name: String, key: String, value: String?, isRepeated: Bool) -> String {
        let encoded = value.map { Data($0.utf8).base64EncodedString() } ?? "~"
        let defaultMarker = name == "__foundry_image" ? "" : " default=\"\(encoded)\""
        let repeatedMarker = isRepeated ? " repeated=\"true\"" : ""
        return "{{ \(name) key=\"\(key)\"\(defaultMarker)\(repeatedMarker) }}"
    }

    private static let directiveExpression = try! NSRegularExpression(pattern: #"\{\{\s*(repeat\s+([^{}]+?)|endrepeat)\s*\}\}"#)
    private static let imageExpression = try! NSRegularExpression(pattern: #"\{\{\s*image\s*\}\}"#)
    private static let textExpression = try! NSRegularExpression(pattern: #"\{\{\s*text(?:\s*=\s*\"([^\"]*)\")?\s*\}\}"#)
    private static let htmlExpression = try! NSRegularExpression(pattern: #"\{\{\s*html(?:\s*=\s*\"([^\"]*)\")?\s*\}\}"#)

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
                if directive == "endrepeat" {
                    if expectsEnd { return result }
                    throw RepeatError.unexpectedEnd
                }
                result.append(.repeated(substring(match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines), try nodes(expectsEnd: true)))
            }
            if expectsEnd { throw RepeatError.missingEnd }
            return result
        }

        private func substring(_ range: NSRange) -> String {
            Range(range, in: source).map { String(source[$0]) } ?? ""
        }
    }
}
