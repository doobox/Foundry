import Foundation

nonisolated enum PartPackageFiltersResolver {
    static func declarations(
        values: [String: PartPackageValue],
        declared: Set<String>,
        hovered: Bool
    ) -> [String] {
        let mode = values["filtersMode"]?.stringValue ?? "none"
        guard mode == "static" || mode == "hover" else {
            return ["filter: none;", "backdrop-filter: none;", "-webkit-backdrop-filter: none;"]
        }
        let prefix = hovered && mode == "hover" ? "filtersHover" : "filters"
        let specifications: [(String, String, Double, Double, String)] = [
            ("Blur", "blur", 0, 100, "px"),
            ("Brightness", "brightness", 100, 200, "%"),
            ("Contrast", "contrast", 100, 200, "%"),
            ("Saturate", "saturate", 100, 200, "%"),
            ("Grayscale", "grayscale", 0, 100, "%"),
            ("Sepia", "sepia", 0, 100, "%"),
            ("Invert", "invert", 0, 100, "%"),
            ("HueRotate", "hue-rotate", 0, 360, "deg")
        ]
        var hasEffect = false
        var functions: [String] = []
        for (suffix, function, neutral, maximum, unit) in specifications where declared.contains(prefix + suffix) {
            let amount = number(values[prefix + suffix], fallback: neutral, maximum: maximum)
            hasEffect = hasEffect || amount != neutral
            functions.append("\(function)(\(formatted(amount))\(unit))")
        }
        if declared.contains(prefix + "Shadow"),
           case .string(let shadow)? = values[prefix + "Shadow"],
           shadow.hasPrefix("drop-shadow(") {
            hasEffect = true
            functions.append(shadow)
        }
        let blur = declared.contains(prefix + "BackdropBlur")
            ? number(values[prefix + "BackdropBlur"], fallback: 0, maximum: 100) : 0
        let backdrop = blur == 0 ? "none" : "blur(\(formatted(blur))px)"
        return [
            "filter: \(hasEffect ? functions.joined(separator: " ") : "none");",
            "backdrop-filter: \(backdrop);",
            "-webkit-backdrop-filter: \(backdrop);"
        ]
    }

    private static func number(_ value: PartPackageValue?, fallback: Double, maximum: Double) -> Double {
        guard case .number(let amount)? = value, amount.isFinite else { return fallback }
        return min(max(amount, 0), maximum)
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.fractionLength(0...4)))
    }
}
