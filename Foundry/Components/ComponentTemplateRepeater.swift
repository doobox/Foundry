import Foundation

nonisolated enum ComponentTemplateRepeater {
    static let maximumIterationCount = 100
    static let maximumExpandedIterationCount = 10_000

    struct Expansion: Sendable {
        let template: String
        let imageKeys: [String]
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

    static func expand(
        _ template: String,
        properties: [String: ComponentPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool = false
    ) throws -> Expansion {
        guard repeatStartExpression.firstMatch(
            in: template,
            range: NSRange(template.startIndex..., in: template)
        ) != nil else {
            var state = ExpansionState()
            return .init(
                template: replaceImages(in: template, isRepeated: false, state: &state),
                imageKeys: state.imageKeys
            )
        }
        var parser = Parser(template)
        let nodes = try parser.nodes(expectsEnd: false)
        var state = ExpansionState()
        let output = try render(
            nodes,
            properties: properties,
            maximums: maximums,
            usingMaximumCounts: usingMaximumCounts,
            repeatStack: [],
            emitsOutput: true,
            state: &state
        )
        return .init(template: output, imageKeys: state.imageKeys)
    }

    private struct RepeatFrame {
        let index: Int
        let count: Int
    }

    private indirect enum Node {
        case text(String)
        case repeated(String, [Node])
    }

    private struct ExpansionState {
        var textIndex = 0
        var htmlIndex = 0
        var imageKeys: [String] = []
        var expandedIterationCount = 0
    }

    private static func render(
        _ nodes: [Node],
        properties: [String: ComponentPackageValue],
        maximums: [String: Int],
        usingMaximumCounts: Bool,
        repeatStack: [RepeatFrame],
        emitsOutput: Bool,
        state: inout ExpansionState
    ) throws -> String {
        var output = ""
        for node in nodes {
            switch node {
            case .text(let source):
                let prepared = prepare(source, repeatStack: repeatStack, state: &state)
                if emitsOutput { output += prepared }
            case .repeated(let source, let children):
                let maximum = try maximumCount(for: source, maximums: maximums)
                let active = usingMaximumCounts ? maximum : currentCount(
                    for: source,
                    properties: properties,
                    maximum: maximum
                )
                for index in 0..<maximum {
                    state.expandedIterationCount += 1
                    guard state.expandedIterationCount <= maximumExpandedIterationCount else {
                        throw RepeatError.expansionLimitExceeded
                    }
                    output += try render(
                        children,
                        properties: properties,
                        maximums: maximums,
                        usingMaximumCounts: usingMaximumCounts,
                        repeatStack: repeatStack + [.init(index: index, count: active)],
                        emitsOutput: emitsOutput && index < active,
                        state: &state
                    )
                }
            }
        }
        return output
    }

    private static func maximumCount(for source: String, maximums: [String: Int]) throws -> Int {
        if let literal = Int(source), (0...maximumIterationCount).contains(literal) {
            return literal
        }
        if source.hasPrefix("control."),
           let maximum = maximums[String(source.dropFirst("control.".count))],
           (0...maximumIterationCount).contains(maximum) {
            return maximum
        }
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

    private static func prepare(
        _ source: String,
        repeatStack: [RepeatFrame],
        state: inout ExpansionState
    ) -> String {
        var result = replacingRepeatValues(in: source, stack: repeatStack)
        result = replacePrimitives(in: result, expression: textExpression) { defaultValue in
            state.textIndex += 1
            return token(name: "__foundry_text", key: "content\(state.textIndex)", value: defaultValue, isRepeated: !repeatStack.isEmpty)
        }
        result = replacePrimitives(in: result, expression: htmlExpression) { defaultValue in
            state.htmlIndex += 1
            return token(name: "__foundry_html", key: "html\(state.htmlIndex)", value: defaultValue, isRepeated: !repeatStack.isEmpty)
        }
        return replaceImages(in: result, isRepeated: !repeatStack.isEmpty, state: &state)
    }

    private static func replaceImages(
        in source: String,
        isRepeated: Bool,
        state: inout ExpansionState
    ) -> String {
        var result = source
        let imageReplacements = imageExpression
            .matches(in: result, range: NSRange(result.startIndex..., in: result))
            .compactMap { match -> (Range<String.Index>, String)? in
                guard let range = Range(match.range, in: result),
                      let keyRange = Range(match.range(at: 1), in: result) else { return nil }
                let key = String(result[keyRange])
                state.imageKeys.append(key)
                let repeatedMarker = isRepeated ? " repeated=\"true\"" : ""
                return (range, "{{ __foundry_image key=\"\(key)\"\(repeatedMarker) }}")
            }
        for (range, replacement) in imageReplacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
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
            let parentValues: [(String, String)] = [
                ("repeat.parent.index", String(parent.index)),
                ("repeat.parent.position", String(parent.index + 1)),
                ("repeat.parent.count", String(parent.count)),
                ("repeat.parent.first", parent.index == 0 ? "true" : "false"),
                ("repeat.parent.last", parent.index == parent.count - 1 ? "true" : "false")
            ]
            for (key, value) in parentValues { result = result.replacingOccurrences(of: key, with: value) }
        }
        return result
    }

    private static func replacePrimitives(
        in source: String,
        expression: NSRegularExpression,
        replacement: (String?) -> String
    ) -> String {
        var result = source
        let replacements = expression
            .matches(in: result, range: NSRange(result.startIndex..., in: result))
            .compactMap { match -> (Range<String.Index>, String)? in
                guard let range = Range(match.range(at: 0), in: result) else { return nil }
                let value = Range(match.range(at: 1), in: result).map { String(result[$0]) }
                return (range, replacement(value))
            }
        for (range, value) in replacements.reversed() {
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    private static func token(name: String, key: String, value: String?, isRepeated: Bool) -> String {
        let encoded = value.map { Data($0.utf8).base64EncodedString() } ?? "~"
        let repeatedMarker = isRepeated ? " repeated=\"true\"" : ""
        return "{{ \(name) key=\"\(key)\" default=\"\(encoded)\"\(repeatedMarker) }}"
    }

    private static let directiveExpression = try! NSRegularExpression(
        pattern: #"\{\{\s*(repeat\s+([^{}]+?)|endrepeat)\s*\}\}"#
    )
    private static let repeatStartExpression = try! NSRegularExpression(pattern: #"\{\{\s*repeat\s+"#)
    private static let imageExpression = try! NSRegularExpression(pattern: #"\{\{\s*image\s+([A-Za-z][A-Za-z0-9_.-]*)\s*\}\}"#)
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
                guard let match = Self.match(in: source, range: searchRange) else {
                    result.append(.text(Self.substring(source, range: searchRange)))
                    location = source.utf16.count
                    break
                }
                if match.range.location > location {
                    result.append(.text(Self.substring(source, range: NSRange(location: location, length: match.range.location - location))))
                }
                location = NSMaxRange(match.range)
                let directive = Self.substring(source, range: match.range(at: 1))
                if directive == "endrepeat" {
                    if expectsEnd { return result }
                    throw RepeatError.unexpectedEnd
                }
                let count = Self.substring(source, range: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(.repeated(count, try nodes(expectsEnd: true)))
            }
            if expectsEnd { throw RepeatError.missingEnd }
            return result
        }

        private static func match(in source: String, range: NSRange) -> NSTextCheckingResult? {
            directiveExpression.firstMatch(in: source, range: range)
        }

        private static func substring(_ source: String, range: NSRange) -> String {
            guard let range = Range(range, in: source) else { return "" }
            return String(source[range])
        }
    }
}
