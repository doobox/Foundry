import Foundation

nonisolated enum ComponentPackageDerivedValueResolver {
    static func resolve(
        _ values: [String: ComponentPackageValue],
        properties: [ComponentPackageProperty]
    ) -> [String: ComponentPackageValue] {
        var result = values

        for property in properties where property.control.type == .button {
            guard let stored = result[property.id] else { continue }
            result[property.id] = buttonValue(stored, control: property.control)
        }

        for _ in 0..<properties.count {
            var changed = false
            for property in properties where property.control.type == .math {
                guard let value = mathValue(control: property.control, values: result),
                      result[property.id] != value else { continue }
                result[property.id] = value
                changed = true
            }
            if !changed { break }
        }

        for property in properties where property.control.type == .imageTransform {
            guard let input = property.control.input,
                  case .string(let source) = result[input],
                  !source.isEmpty else {
                result[property.id] = .string("")
                continue
            }
            result[property.id] = .string(transformedImage(source: source, control: property.control))
        }
        return result
    }

    private static func buttonValue(
        _ stored: ComponentPackageValue,
        control: ComponentPackageControl
    ) -> ComponentPackageValue {
        switch stored {
        case .boolean(let isOn):
            return isOn ? (control.trueValue ?? .boolean(true)) : (control.falseValue ?? .boolean(false))
        case .array(let values):
            let trueValues = control.trueValue?.arrayValue
            let falseValues = control.falseValue?.arrayValue
            return .array(values.enumerated().map { index, value in
                guard case .boolean(let isOn) = value else { return value }
                return isOn
                    ? (trueValues?[safe: index] ?? control.trueValue ?? .boolean(true))
                    : (falseValues?[safe: index] ?? control.falseValue ?? .boolean(false))
            })
        default:
            return stored
        }
    }

    private static func mathValue(
        control: ComponentPackageControl,
        values: [String: ComponentPackageValue]
    ) -> ComponentPackageValue? {
        guard let left = number(control.argument1, values: values),
              let right = number(control.argument2, values: values) else { return nil }
        let result: Double
        switch control.operation {
        case "+": result = left + right
        case "-": result = left - right
        case "*": result = left * right
        case "/": result = right == 0 ? 0 : left / right
        case "%": result = right == 0 ? 0 : left.truncatingRemainder(dividingBy: right)
        case "min": result = min(left, right)
        case "max": result = max(left, right)
        default: return nil
        }
        return .number(control.round ?? true ? result.rounded() : result)
    }

    private static func number(
        _ argument: ComponentPackageValue?,
        values: [String: ComponentPackageValue]
    ) -> Double? {
        switch argument {
        case .number(let value): return value
        case .string(let reference):
            if let literal = Double(reference) { return literal }
            guard let value = values[reference] else { return nil }
            switch value {
            case .number(let number): return number
            case .string(let string): return Double(string)
            default: return nil
            }
        default: return nil
        }
    }

    private static func transformedImage(source: String, control: ComponentPackageControl) -> String {
        let width = max(control.maxWidth ?? 320, 1)
        let height = max(control.maxHeight ?? width, 1)
        let scale = max(control.scale ?? 100, 0) / 100
        let imageWidth = width * scale
        let imageHeight = height * scale
        let imageX = (width - imageWidth) / 2
        let imageY = (height - imageHeight) / 2
        let aspect: String
        switch control.scaleMode ?? 0 {
        case 1: aspect = "xMidYMid slice"
        case 2: aspect = "none"
        case 3: aspect = "xMidYMid meet"
        default: aspect = "xMidYMid meet"
        }
        let rotation = control.rotation ?? 0
        let borderWidth = max(control.borderWidth ?? 0, 0)
        let borderColor = xml(control.borderColor ?? "#000000")
        let shadowColor = xml(control.shadowColor ?? "#000000")
        let shadowOpacity = min(max(control.shadowOpacity ?? 0, 0), 1)
        let shadowBlur = max(control.shadowBlur ?? 0, 0)
        let shadowX = control.shadowOffsetX ?? 0
        let shadowY = control.shadowOffsetY ?? 0
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(format(width))" height="\(format(height))" viewBox="0 0 \(format(width)) \(format(height))">
        <defs><filter id="s" x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="\(format(shadowX))" dy="\(format(shadowY))" stdDeviation="\(format(shadowBlur))" flood-color="\(shadowColor)" flood-opacity="\(format(shadowOpacity))"/></filter></defs>
        <g transform="rotate(\(format(rotation)) \(format(width / 2)) \(format(height / 2)))" filter="url(#s)">
        <image href="\(xml(source))" x="\(format(imageX))" y="\(format(imageY))" width="\(format(imageWidth))" height="\(format(imageHeight))" preserveAspectRatio="\(aspect)"/>
        <rect x="\(format(borderWidth / 2))" y="\(format(borderWidth / 2))" width="\(format(width - borderWidth))" height="\(format(height - borderWidth))" fill="none" stroke="\(borderColor)" stroke-width="\(format(borderWidth))"/>
        </g></svg>
        """
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return "data:image/svg+xml," + (svg.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
    }

    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private nonisolated extension ComponentPackageValue {
    var arrayValue: [ComponentPackageValue]? {
        if case .array(let values) = self { values } else { nil }
    }
}

private nonisolated extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
