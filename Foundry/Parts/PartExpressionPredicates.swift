import Foundation

nonisolated enum PartExpressionPredicates {
    static let binaryFunctionNames: Set<String> = [
        "contains", "notContains", "containsInsensitive", "notContainsInsensitive",
        "matches", "notMatches", "matchesInsensitive", "notMatchesInsensitive",
        "containsValue", "notContainsValue"
    ]

    static let unaryFunctionNames: Set<String> = ["isEmpty", "isNotEmpty"]

    static func evaluate(_ name: String, lhs: PartPackageValue, rhs: PartPackageValue? = nil) -> Bool? {
        if unaryFunctionNames.contains(name) {
            let result = isEmpty(lhs)
            return name == "isEmpty" ? result : !result
        }

        guard let rhs else { return nil }
        switch name {
        case "contains", "notContains", "containsInsensitive", "notContainsInsensitive",
             "matches", "notMatches", "matchesInsensitive", "notMatchesInsensitive":
            guard case .string(let lhs) = lhs, case .string(let rhs) = rhs else { return nil }
            return stringComparison(lhs, rhs, operation: name)
        case "containsValue", "notContainsValue":
            guard case .array(let values) = lhs else { return nil }
            let contains = values.contains(rhs)
            return name == "containsValue" ? contains : !contains
        default:
            return nil
        }
    }

    static func isEmpty(_ value: PartPackageValue) -> Bool {
        switch value {
        case .string(let value): value.isEmpty
        case .array(let values): values.isEmpty
        case .object(let values): values.isEmpty
        case .number, .boolean: false
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
