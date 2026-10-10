import Foundation

nonisolated enum PartPackageTransformsResolver {
    static func declarations(values: [String: PartPackageValue], declared: Set<String>, hovered: Bool) -> [String] {
        let mode = values["transformsMode"]?.stringValue ?? "none"
        guard mode == "static" || mode == "hover" else {
            return ["transform: none;", "transform-origin: center;"]
        }
        let prefix = hovered && mode == "hover" ? "transformsHover" : "transforms"
        func number(_ suffix: String, neutral: Double = 0, range: ClosedRange<Double>) -> Double {
            guard declared.contains(prefix + suffix), case .number(let value)? = values[prefix + suffix],
                  value.isFinite else { return neutral }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        func length(_ suffix: String) -> String {
            guard declared.contains(prefix + suffix), case .string(let raw)? = values[prefix + suffix] else { return "0px" }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Deliberately accept lengths, not arbitrary CSS declarations or functions.
            let pattern = #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:px|%|em|rem|vw|vh|vmin|vmax|svw|svh|lvw|lvh|dvw|dvh|ch|ex|cm|mm|in|pt|pc)?$"#
            guard value.range(of: pattern, options: .regularExpression) != nil else { return "0px" }
            let digits = String(value.prefix { "+-.0123456789".contains($0) })
            guard let amount = Double(digits), amount.isFinite else { return "0px" }
            if amount == 0 { return "0px" }
            guard digits.count < value.count else { return "0px" }
            return value
        }
        let scale = number("Scale", neutral: 100, range: 0...1000)
        let rotate = number("Rotate", range: -360...360)
        let skewX = number("SkewX", range: -89...89)
        let skewY = number("SkewY", range: -89...89)
        let x = length("TranslateX"), y = length("TranslateY")
        let rawOrigin = declared.contains(prefix + "Origin") ? values[prefix + "Origin"]?.stringValue : nil
        let origins = ["center", "top left", "top", "top right", "left", "right", "bottom left", "bottom", "bottom right"]
        let origin = rawOrigin.flatMap { origins.contains($0) ? $0 : nil } ?? "center"
        let neutral = scale == 100 && rotate == 0 && skewX == 0 && skewY == 0 && x == "0px" && y == "0px"
        let transform = neutral ? "none" : "translate(\(x), \(y)) rotate(\(formatted(rotate))deg) skew(\(formatted(skewX))deg, \(formatted(skewY))deg) scale(\(formatted(scale / 100)))"
        return ["transform: \(transform);", "transform-origin: \(origin);"]
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.fractionLength(0...4)))
    }
}
