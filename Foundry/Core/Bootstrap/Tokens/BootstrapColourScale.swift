import Foundation

/// The base is retained as OKLCH, never round-tripped through an sRGB swatch.
/// Scale expressions come directly from the pinned Bootstrap stylesheet.
nonisolated struct BootstrapColourScale: Codable, Hashable, Sendable {
    let base: String

    init?(base: String) {
        let value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = #"(?:\d+(?:\.\d*)?|\.\d+)"#
        let pattern = "^oklch\\(\\s*(\(number))%\\s+(\(number))\\s+(\(number))(?:deg)?\\s*\\)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let numbers = (1...3).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Double(value[range])
        }
        guard numbers.count == 3, numbers.allSatisfy(\.isFinite),
              (0...100).contains(numbers[0]), (0...1).contains(numbers[1]), (0...360).contains(numbers[2]) else { return nil }
        self.base = value
    }

    func expression(at shade: ColourShade) -> String {
        let key = "--bs-blue-\(shade.bootstrapLabel)"
        let reference = BootstrapColourCatalogue.declarations["--bs-blue-500"]!
        return BootstrapColourCatalogue.declarations[key]!.replacingOccurrences(of: reference, with: base)
    }

    static func native(_ hue: String) -> Self? {
        if hue == "black" { return Self(base: "oklch(0% 0 0)") }
        if hue == "white" { return Self(base: "oklch(100% 0 0)") }
        return BootstrapColourCatalogue.declarations["--bs-\(hue)-500"].flatMap { Self(base: $0) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let scale = Self(base: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected oklch(L% C H), with L 0–100, C 0–1 and H 0–360.")
        }
        self = scale
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base)
    }
}
