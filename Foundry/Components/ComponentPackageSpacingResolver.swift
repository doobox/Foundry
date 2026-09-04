import Foundation

nonisolated enum ComponentPackageSpacingResolver {
    private static let sideCount = 4

    static func resolve(
        _ value: ComponentPackageSpacingValue,
        theme: Theme,
        kind: ComponentSpacingKind
    ) -> String {
        let sources = padded(
            value.sources,
            with: "none"
        )
        let customValues = padded(
            value.customValues,
            with: 0
        )

        return zip(sources, customValues).map { source, customValue in
            switch source {
            case "none":
                return "0"
            case "auto" where kind.permitsAuto:
                return "auto"
            case ComponentThemeValueSelection.manualCustom:
                let lowerBound = kind == .padding ? 0 : -10_000
                let value = min(max(customValue, Double(lowerBound)), 10_000)
                return "\(cssNumber(value))px"
            default:
                return theme.spacingCSSVariable(for: source) ?? "0"
            }
        }.joined(separator: " ")
    }

    private static func padded<Value>(_ values: [Value], with fallback: Value) -> [Value] {
        Array((values + Array(repeating: fallback, count: sideCount)).prefix(sideCount))
    }

    private static func cssNumber(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
    }
}
