import Foundation

/// Bootstrap supplies explicit pairs, not an algorithm. Interpolate its native
/// pairs for custom sizes; fluid sizes use their maximum, like the native scale.
nonisolated enum BootstrapTextSize {
    private static let anchors: [(size: Double, height: Double)] = BootstrapEditorSection.sizes.compactMap { name in
        let values = BootstrapColourCatalogue.declarations
        guard let size = values["--bs-font-size-" + name].flatMap(referenceSize),
              let height = values["--bs-line-height-" + name].flatMap(Double.init) else { return nil }
        return (size, height)
    }.sorted { $0.size < $1.size }

    static func lineHeight(for value: String) -> Double {
        guard let size = referenceSize(value), let first = anchors.first, let last = anchors.last else { return 1.5 }
        if size <= first.size { return first.height }
        if size >= last.size { return last.height }
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where size <= upper.size {
            let fraction = (size - lower.size) / (upper.size - lower.size)
            return lower.height + fraction * (upper.height - lower.height)
        }
        return last.height
    }

    private static func referenceSize(_ value: String) -> Double? {
        // Custom editor values are rem; also handle saved px and fluid rem sizes.
        let regex = try! NSRegularExpression(pattern: #"(\d*\.?\d+)(rem|px)"#)
        guard let match = regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).last,
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let number = Double(value[numberRange]), number.isFinite else { return nil }
        return value[unitRange] == "px" ? number / 16 : number
    }
}
