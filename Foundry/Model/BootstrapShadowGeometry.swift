import Foundation

/// Preserve Bootstrap's colour/opacity expressions while editing layer geometry.
nonisolated struct BootstrapShadowGeometry: Equatable {
    var x: Double
    var y: Double
    var blur: Double
    var spread: Double
    var unit: String
    var inset: Bool
    var colour: String

    var css: String {
        "\(inset ? "inset " : "")\(x.bootstrapCSSNumber)\(unit) \(y.bootstrapCSSNumber)\(unit) \(blur.bootstrapCSSNumber)\(unit) \(spread.bootstrapCSSNumber)\(unit) \(colour)"
    }

    static func parse(_ value: String) -> [Self] {
        var depth = 0
        var parts: [String] = []
        var current = ""
        for character in value {
            if character == ",", depth == 0 { parts.append(current); current = ""; continue }
            current.append(character)
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
        }
        parts.append(current)
        return parts.compactMap { part in
            var remainder = part.trimmingCharacters(in: .whitespaces)
            let inset = remainder.hasPrefix("inset ")
            if inset { remainder = String(remainder.dropFirst(6)) }
            let regex = try! NSRegularExpression(pattern: #"^(-?(?:\d+(?:\.\d+)?|\.\d+))(rem|px)?\s+"#)
            var numbers: [Double] = []
            var unit = "px"
            while let match = regex.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)), numbers.count < 4 {
                guard let range = Range(match.range(at: 1), in: remainder), let number = Double(remainder[range]) else { return nil }
                numbers.append(number)
                if let unitRange = Range(match.range(at: 2), in: remainder) { unit = String(remainder[unitRange]) }
                remainder = String(remainder.dropFirst(match.range.length))
            }
            guard numbers.count >= 3 else { return nil }
            return Self(x: numbers[0], y: numbers[1], blur: numbers[2], spread: numbers.count > 3 ? numbers[3] : 0, unit: unit, inset: inset, colour: remainder)
        }
    }
}
