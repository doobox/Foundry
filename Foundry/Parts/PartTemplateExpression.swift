import Foundation

nonisolated enum PartTemplateExpression {
    indirect enum Node: Equatable, Sendable {
        case number(Double)
        case string(String)
        case boolean(Bool)
        case variable(String)
        case unary(String, Node)
        case binary(String, Node, Node)
        case call(String, [Node])
    }

    enum Value: Equatable, Sendable {
        case number(Double)
        case string(String)
        case boolean(Bool)
        case array([PartPackageValue])
        case object([String: PartPackageValue])
        case missing

        var isTruthy: Bool {
            switch self {
            case .number(let value): value != 0
            case .string(let value): !value.isEmpty
            case .boolean(let value): value
            case .array(let values): !values.isEmpty
            case .object(let values): !values.isEmpty
            case .missing: false
            }
        }

        var output: String {
            switch self {
            case .number(let value): value.formatted(.number.grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            case .string(let value): value
            case .boolean(let value): value ? "true" : "false"
            case .array(let values): values.map(valueOutput).joined(separator: ", ")
            case .object: ""
            case .missing: ""
            }
        }
    }

    struct ExpressionError: Error, Equatable, Sendable, CustomStringConvertible {
        let description: String
    }

    private enum Token: Equatable {
        case number(Double), string(String), identifier(String), symbol(String), end
    }

    static func parse(_ source: String) throws -> Node {
        var parser = try Parser(source)
        let expression = try parser.parseExpression()
        guard parser.current == .end else { throw ExpressionError(description: "Unexpected token after the expression.") }
        return expression
    }

    static func templateParts(_ source: String) -> [String] {
        let characters = Array(source)
        var parts: [String] = []
        var start = 0
        var quote: Character?
        var depth = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                if character == "\\" { index += 2; continue }
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if character == "|", depth == 0 {
                let previousIsPipe = index > 0 && characters[index - 1] == "|"
                let nextIsPipe = index + 1 < characters.count && characters[index + 1] == "|"
                if !previousIsPipe && !nextIsPipe {
                    parts.append(String(characters[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = index + 1
                }
            }
            index += 1
        }
        parts.append(String(characters[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    static func references(in node: Node, groupNamespaces: Set<String> = []) -> [String] {
        switch node {
        case .variable(let name):
            guard name.hasPrefix("control.") else { return [] }
            let reference = String(name.dropFirst("control.".count))
            let parts = String(reference.prefix { $0 != "[" }).split(separator: ".")
            let count = parts.first.map { groupNamespaces.contains(String($0)) } == true ? 2 : 1
            return [parts.prefix(count).joined(separator: ".")]
        case .unary(_, let value): return references(in: value, groupNamespaces: groupNamespaces)
        case .binary(_, let lhs, let rhs): return references(in: lhs, groupNamespaces: groupNamespaces) + references(in: rhs, groupNamespaces: groupNamespaces)
        case .call(_, let arguments): return arguments.flatMap { references(in: $0, groupNamespaces: groupNamespaces) }
        default: return []
        }
    }

    static func validate(_ node: Node) throws {
        switch node {
        case .number, .string, .boolean:
            return
        case .variable(let name):
            guard ["canvas", "preview", "published"].contains(name) ||
                    name.hasPrefix("control.") || name.hasPrefix("navigation.") || name.contains(".") else {
                throw ExpressionError(description: "Unknown value '\(name)'.")
            }
        case .unary(_, let value):
            try validate(value)
        case .binary(_, let lhs, let rhs):
            try validate(lhs)
            try validate(rhs)
        case .call(let name, let arguments):
            let argumentCounts = [
                "abs": 1, "round": 1, "floor": 1, "ceil": 1,
                "min": 2, "max": 2, "clamp": 3,
                "contains": 2, "notContains": 2,
                "containsInsensitive": 2, "notContainsInsensitive": 2,
                "matches": 2, "notMatches": 2,
                "matchesInsensitive": 2, "notMatchesInsensitive": 2,
                "containsValue": 2, "notContainsValue": 2,
                "isEmpty": 1, "isNotEmpty": 1
            ]
            guard argumentCounts[name] == arguments.count else {
                throw ExpressionError(description: "Unknown function or incorrect number of arguments for '\(name)'.")
            }
            try arguments.forEach(validate)
        }
    }

    static func evaluate(
        _ node: Node,
        properties: [String: PartPackageValue],
        environment: PartTemplateEnvironment
    ) throws -> Value {
        switch node {
        case .number(let value): return .number(value)
        case .string(let value): return .string(value)
        case .boolean(let value): return .boolean(value)
        case .variable("canvas"): return .boolean(environment == .canvas)
        case .variable("preview"): return .boolean(environment == .preview)
        case .variable("published"): return .boolean(environment == .published)
        case .variable(let name): return resolve(name, properties: properties)
        case .unary("!", let expression):
            return .boolean(!(try evaluate(expression, properties: properties, environment: environment)).isTruthy)
        case .unary("-", let expression):
            return .number(-(try number(evaluate(expression, properties: properties, environment: environment))))
        case .unary:
            throw ExpressionError(description: "Unknown unary operator.")
        case .binary("&&", let lhs, let rhs):
            let left = try evaluate(lhs, properties: properties, environment: environment)
            return left.isTruthy ? .boolean(try evaluate(rhs, properties: properties, environment: environment).isTruthy) : .boolean(false)
        case .binary("||", let lhs, let rhs):
            let left = try evaluate(lhs, properties: properties, environment: environment)
            return left.isTruthy ? .boolean(true) : .boolean(try evaluate(rhs, properties: properties, environment: environment).isTruthy)
        case .binary(let operation, let lhs, let rhs):
            let left = try evaluate(lhs, properties: properties, environment: environment)
            let right = try evaluate(rhs, properties: properties, environment: environment)
            return try binary(operation, left, right)
        case .call(let name, let arguments):
            return try call(name, arguments: arguments.map { try evaluate($0, properties: properties, environment: environment) })
        }
    }

    private static func resolve(_ name: String, properties: [String: PartPackageValue]) -> Value {
        let reference = name.hasPrefix("control.") ? String(name.dropFirst("control.".count)) : name
        if let bracket = reference.lastIndex(of: "["), reference.hasSuffix("]"),
           let index = Int(reference[reference.index(after: bracket)..<reference.index(before: reference.endIndex)]),
           case .array(let values) = properties[String(reference[..<bracket])], values.indices.contains(index) {
            return value(values[index])
        }
        if let exact = properties[reference] { return value(exact) }
        let parts = reference.split(separator: ".")
        for splitIndex in stride(from: parts.count - 1, through: 0, by: -1) {
            let root = parts[0...splitIndex].joined(separator: ".")
            guard let rootValue = properties[root],
                  let nested = rootValue.value(at: parts.dropFirst(splitIndex + 1)) else { continue }
            return value(nested)
        }
        return .missing
    }

    private static func value(_ value: PartPackageValue) -> Value {
        switch value {
        case .number(let value): .number(value)
        case .string(let value): .string(value)
        case .boolean(let value): .boolean(value)
        case .array(let values): .array(values)
        case .object(let values): .object(values)
        }
    }

    private static func number(_ value: Value) throws -> Double {
        guard case .number(let number) = value else { throw ExpressionError(description: "Arithmetic requires Number values.") }
        return number
    }

    private static func binary(_ operation: String, _ lhs: Value, _ rhs: Value) throws -> Value {
        switch operation {
        case "+": return .number(try number(lhs) + number(rhs))
        case "-": return .number(try number(lhs) - number(rhs))
        case "*": return .number(try number(lhs) * number(rhs))
        case "/":
            let divisor = try number(rhs)
            guard divisor != 0 else { throw ExpressionError(description: "Division by zero.") }
            let dividend = try number(lhs)
            return .number(dividend / divisor)
        case "%":
            let divisor = try number(rhs)
            guard divisor != 0 else { throw ExpressionError(description: "Division by zero.") }
            let dividend = try number(lhs)
            return .number(dividend.truncatingRemainder(dividingBy: divisor))
        case "==": return .boolean(lhs != .missing && rhs != .missing && lhs == rhs)
        case "!=": return .boolean(lhs == .missing || rhs == .missing || lhs != rhs)
        case "<": return .boolean(try number(lhs) < number(rhs))
        case "<=": return .boolean(try number(lhs) <= number(rhs))
        case ">": return .boolean(try number(lhs) > number(rhs))
        case ">=": return .boolean(try number(lhs) >= number(rhs))
        default: throw ExpressionError(description: "Unknown binary operator '\(operation)'.")
        }
    }

    private static func call(_ name: String, arguments: [Value]) throws -> Value {
        if PartExpressionPredicates.binaryFunctionNames.contains(name) ||
            PartExpressionPredicates.unaryFunctionNames.contains(name) {
            guard let lhs = arguments.first.flatMap(packageValue),
                  let result = PartExpressionPredicates.evaluate(
                    name,
                    lhs: lhs,
                    rhs: arguments.count > 1 ? packageValue(arguments[1]) : nil
                  ) else {
                throw ExpressionError(description: "Function '\(name)' received incompatible values.")
            }
            return .boolean(result)
        }

        let numbers = try arguments.map(number)
        switch name {
        case "abs" where numbers.count == 1: return .number(abs(numbers[0]))
        case "round" where numbers.count == 1: return .number(numbers[0].rounded())
        case "floor" where numbers.count == 1: return .number(floor(numbers[0]))
        case "ceil" where numbers.count == 1: return .number(ceil(numbers[0]))
        case "min" where numbers.count == 2: return .number(min(numbers[0], numbers[1]))
        case "max" where numbers.count == 2: return .number(max(numbers[0], numbers[1]))
        case "clamp" where numbers.count == 3:
            guard numbers[1] <= numbers[2] else {
                throw ExpressionError(description: "clamp minimum cannot exceed its maximum.")
            }
            return .number(min(max(numbers[0], numbers[1]), numbers[2]))
        default: throw ExpressionError(description: "Unknown function or incorrect number of arguments for '\(name)'.")
        }
    }

    private static func packageValue(_ value: Value) -> PartPackageValue? {
        switch value {
        case .number(let value): .number(value)
        case .string(let value): .string(value)
        case .boolean(let value): .boolean(value)
        case .array(let values): .array(values)
        case .object(let values): .object(values)
        case .missing: nil
        }
    }

    private static func valueOutput(_ value: PartPackageValue) -> String {
        switch value {
        case .number(let value): value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        case .string(let value): value
        case .boolean(let value): value ? "true" : "false"
        case .array(let values): values.map(valueOutput).joined(separator: ", ")
        case .object: ""
        }
    }

    private struct Parser {
        private var tokens: [Token]
        private var index = 0
        var current: Token { tokens[index] }

        init(_ source: String) throws {
            var lexer = Lexer(source)
            tokens = try lexer.tokens()
        }

        mutating func parseExpression() throws -> Node { try parseOr() }

        private mutating func parseOr() throws -> Node {
            var result = try parseAnd()
            while current == .symbol("||") { advance(); result = .binary("||", result, try parseAnd()) }
            return result
        }
        private mutating func parseAnd() throws -> Node {
            var result = try parseEquality()
            while current == .symbol("&&") { advance(); result = .binary("&&", result, try parseEquality()) }
            return result
        }
        private mutating func parseEquality() throws -> Node {
            var result = try parseComparison()
            while case .symbol(let operation) = current, operation == "==" || operation == "!=" {
                advance(); result = .binary(operation, result, try parseComparison())
            }
            return result
        }
        private mutating func parseComparison() throws -> Node {
            var result = try parseTerm()
            while case .symbol(let operation) = current, ["<", "<=", ">", ">="].contains(operation) {
                advance(); result = .binary(operation, result, try parseTerm())
            }
            return result
        }
        private mutating func parseTerm() throws -> Node {
            var result = try parseFactor()
            while case .symbol(let operation) = current, operation == "+" || operation == "-" {
                advance(); result = .binary(operation, result, try parseFactor())
            }
            return result
        }
        private mutating func parseFactor() throws -> Node {
            var result = try parseUnary()
            while case .symbol(let operation) = current, ["*", "/", "%"].contains(operation) {
                advance(); result = .binary(operation, result, try parseUnary())
            }
            return result
        }

        private mutating func parseUnary() throws -> Node {
            if case .symbol(let operation) = current, operation == "!" || operation == "-" {
                advance()
                return .unary(operation, try parseUnary())
            }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Node {
            switch current {
            case .number(let value): advance(); return .number(value)
            case .string(let value): advance(); return .string(value)
            case .identifier("true"): advance(); return .boolean(true)
            case .identifier("false"): advance(); return .boolean(false)
            case .identifier(let name):
                advance()
                guard current == .symbol("(") else { return .variable(name) }
                advance()
                var arguments: [Node] = []
                if current != .symbol(")") {
                    repeat {
                        arguments.append(try parseExpression())
                        if current != .symbol(",") { break }
                        advance()
                    } while true
                }
                try consume(")")
                return .call(name, arguments)
            case .symbol("("):
                advance()
                let value = try parseExpression()
                try consume(")")
                return value
            default: throw ExpressionError(description: "Expected a value or '('.")
            }
        }

        private mutating func consume(_ symbol: String) throws {
            guard current == .symbol(symbol) else { throw ExpressionError(description: "Expected '\(symbol)'.") }
            advance()
        }

        private mutating func advance() { index += 1 }
    }

    private struct Lexer {
        let characters: [Character]
        var index = 0
        init(_ source: String) { characters = Array(source) }

        mutating func tokens() throws -> [Token] {
            var result: [Token] = []
            while index < characters.count {
                if characters[index].isWhitespace { index += 1; continue }
                if characters[index].isNumber || (characters[index] == "." && peek()?.isNumber == true) {
                    result.append(try number()); continue
                }
                if characters[index] == "\"" || characters[index] == "'" { result.append(try string()); continue }
                if characters[index].isLetter || characters[index] == "_" { result.append(identifier()); continue }
                let pair = String(characters[index...min(index + 1, characters.count - 1)])
                if ["==", "!=", "<=", ">=", "&&", "||"].contains(pair) { result.append(.symbol(pair)); index += 2; continue }
                let character = String(characters[index])
                if ["+", "-", "*", "/", "%", "<", ">", "!", "(", ")", ","].contains(character) {
                    result.append(.symbol(character)); index += 1; continue
                }
                throw ExpressionError(description: "Unexpected character '\(character)'.")
            }
            result.append(.end)
            return result
        }

        private mutating func number() throws -> Token {
            let start = index
            while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
            guard let value = Double(String(characters[start..<index])) else { throw ExpressionError(description: "Invalid number.") }
            return .number(value)
        }

        private mutating func string() throws -> Token {
            let quote = characters[index]
            index += 1
            var value = ""
            while index < characters.count, characters[index] != quote {
                if characters[index] == "\\", let next = peek() {
                    let escaped: Character = next == "n" ? "\n" : next == "t" ? "\t" : next
                    value.append(escaped); index += 2
                } else { value.append(characters[index]); index += 1 }
            }
            guard index < characters.count else { throw ExpressionError(description: "Unterminated String.") }
            index += 1
            return .string(value)
        }

        private mutating func identifier() -> Token {
            let start = index
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || ["_", "-", ".", "[", "]"].contains(characters[index]) { index += 1 }
            return .identifier(String(characters[start..<index]))
        }

        private func peek() -> Character? { index + 1 < characters.count ? characters[index + 1] : nil }
    }
}
