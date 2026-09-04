import Foundation

nonisolated enum ComponentPackageEnableEvaluator {
    static func isVisible(
        _ condition: ComponentPackageEnable?,
        for component: ComponentNode,
        at breakpoint: ResponsiveBreakpoint
    ) -> Bool {
        guard let condition,
              let reference = reference(condition.id),
              var actual = componentProperty(reference.key, component: component, breakpoint: breakpoint) else {
            return condition == nil
        }

        if let index = reference.index {
            guard case .array(let values) = actual, values.indices.contains(index) else { return false }
            actual = values[index]
        }

        return evaluate(actual, operation: condition.operation, expected: condition.value)
    }

    static func evaluate(
        _ actual: ComponentProperty.Value,
        operation: String,
        expected: ComponentPackageValue?
    ) -> Bool {
        let operation = canonicalOperation(operation)
        if operation == "isEmpty" || operation == "isNotEmpty" {
            let result = isEmpty(actual)
            return operation == "isEmpty" ? result : !result
        }

        guard let expected, let comparable = packageValue(actual) else { return false }
        switch operation {
        case "==": return comparable == expected
        case "!=": return comparable != expected
        case "<", "<=", ">", ">=":
            guard case .number(let lhs) = comparable, case .number(let rhs) = expected else { return false }
            switch operation {
            case "<": return lhs < rhs
            case "<=": return lhs <= rhs
            case ">": return lhs > rhs
            default: return lhs >= rhs
            }
        case "contains", "notContains", "containsInsensitive", "notContainsInsensitive",
             "matches", "notMatches", "matchesInsensitive", "notMatchesInsensitive":
            guard case .string(let lhs) = comparable, case .string(let rhs) = expected else { return false }
            return stringComparison(lhs, rhs, operation: operation)
        case "containsValue", "notContainsValue":
            guard case .array(let values) = comparable else { return false }
            let contains = values.contains(expected)
            return operation == "containsValue" ? contains : !contains
        default:
            return false
        }
    }

    static func canonicalOperation(_ operation: String) -> String {
        switch operation {
        case "", "=", "==", "equals", "equalTo": "=="
        case "!=", "notEqual", "notEqualTo": "!="
        case "<", "lessThan": "<"
        case "<=", "lessThanOrEqualTo", "lessThanOrEquals": "<="
        case ">", "greaterThan": ">"
        case ">=", "greaterThanOrEqualTo", "greaterThanOrEquals": ">="
        case "doesntcontain": "notContainsInsensitive"
        case "caseInsensitiveMatches": "matchesInsensitive"
        case "caseInsensitiveDoesntMatch": "notMatchesInsensitive"
        default: operation
        }
    }

    private static func reference(_ value: String) -> (key: ComponentProperty.Key, index: Int?)? {
        let expression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)(?:\[([0-9]+)\])?$"#)
        guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let keyRange = Range(match.range(at: 1), in: value) else { return nil }
        let index = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) }
        return (.init(rawValue: String(value[keyRange])), index)
    }

    private static func componentProperty(
        _ key: ComponentProperty.Key,
        component: ComponentNode,
        breakpoint: ResponsiveBreakpoint
    ) -> ComponentProperty.Value? {
        guard component.type.definition.properties.contains(where: { $0.key == key }) else { return nil }
        return component.propertyValue(key, at: breakpoint)
    }

    private static func isEmpty(_ value: ComponentProperty.Value) -> Bool {
        switch value {
        case .string(let value), .url(let value), .color(let value), .choice(let value): value.isEmpty
        case .array(let values): values.isEmpty
        case .link(let link): link.destination == .none
        default: false
        }
    }

    private static func packageValue(_ value: ComponentProperty.Value) -> ComponentPackageValue? {
        switch value {
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.compactMap(packageValue))
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageSpacing(let value): .array(value.sources.map(ComponentPackageValue.string))
        case .link: nil
        }
    }

    private static func stringComparison(_ lhs: String, _ rhs: String, operation: String) -> Bool {
        let insensitive = operation.contains("Insensitive")
        let negative = operation.hasPrefix("not")
        let options: String.CompareOptions = insensitive ? [.caseInsensitive] : []
        let matches: Bool
        if operation.contains("matches") || operation.contains("Matches") {
            matches = wildcardMatch(lhs, pattern: rhs, caseInsensitive: insensitive)
        } else {
            matches = lhs.range(of: rhs, options: options) != nil
        }
        return negative ? !matches : matches
    }

    private static func wildcardMatch(_ value: String, pattern: String, caseInsensitive: Bool) -> Bool {
        var expression = NSRegularExpression.escapedPattern(for: pattern)
        expression = expression.replacingOccurrences(of: #"\*"#, with: ".*")
        expression = expression.replacingOccurrences(of: #"\?"#, with: ".")
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: "^\(expression)$", options: options) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
