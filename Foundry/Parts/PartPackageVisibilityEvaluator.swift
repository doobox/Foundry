import Foundation

nonisolated enum PartPackageVisibilityEvaluator {
    static func isVisible(
        _ condition: PartPackageVisibilityCondition?,
        for part: PartNode,
        at breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens = .standard
    ) -> Bool {
        guard let condition else { return true }
        if let all = condition.all {
            return !all.isEmpty && all.allSatisfy { isVisible($0, for: part, at: breakpoint, screens: screens) }
        }
        if let any = condition.any {
            return !any.isEmpty && any.contains { isVisible($0, for: part, at: breakpoint, screens: screens) }
        }
        guard let id = condition.id,
              let reference = reference(id),
              var actual = partProperty(reference.key, part: part, breakpoint: breakpoint, screens: screens) else {
            return false
        }

        if let index = reference.index {
            guard case .array(let values) = actual, values.indices.contains(index) else { return false }
            actual = values[index]
        }

        return evaluate(actual, operation: condition.operation, expected: condition.value)
    }

    static func evaluate(
        _ actual: PartProperty.Value,
        operation: String,
        expected: PartPackageValue?
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
            return PartExpressionPredicates.evaluate(operation, lhs: comparable, rhs: expected) ?? false
        case "containsValue", "notContainsValue":
            return PartExpressionPredicates.evaluate(operation, lhs: comparable, rhs: expected) ?? false
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
        default: operation
        }
    }

    private static func reference(_ value: String) -> (key: PartProperty.Key, index: Int?)? {
        let expression = try! NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)(?:\[([0-9]+)\])?$"#)
        guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let keyRange = Range(match.range(at: 1), in: value) else { return nil }
        let index = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) }
        return (.init(rawValue: String(value[keyRange])), index)
    }

    private static func partProperty(
        _ key: PartProperty.Key,
        part: PartNode,
        breakpoint: ResponsiveBreakpoint,
        screens: ScreenTokens
    ) -> PartProperty.Value? {
        guard part.type.definition.properties.contains(where: { $0.key == key }) else { return nil }
        return part.propertyValue(key, at: breakpoint, screens: screens)
    }

    private static func isEmpty(_ value: PartProperty.Value) -> Bool {
        if let comparable = packageValue(value) {
            return PartExpressionPredicates.isEmpty(comparable)
        }
        switch value {
        case .link(let link): return link.destination == .none
        default: return false
        }
    }

    private static func packageValue(_ value: PartProperty.Value) -> PartPackageValue? {
        switch value {
        case .string(let value), .url(let value), .color(let value), .choice(let value): .string(value)
        case .number(let value): .number(value)
        case .boolean(let value): .boolean(value)
        case .token(let value): .string(value.rawValue)
        case .array(let values): .array(values.compactMap(packageValue))
        case .packageColor(let value): .string(value.source)
        case .packageFontSize(let value): .string(value.source)
        case .packageShadow(let value): .string(value.source)
        case .link, .frameworkSpacing, .frameworkPadding, .frameworkMargin, .frameworkBorderWidth, .frameworkRadius: nil
        }
    }

}
