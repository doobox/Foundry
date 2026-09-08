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

        return result
    }

    private static func buttonValue(
        _ stored: ComponentPackageValue,
        control: ComponentPackageControl
    ) -> ComponentPackageValue {
        if control.selectionMode == .single, case .array(let values) = stored {
            guard let selectedIndex = values.firstIndex(where: {
                if case .boolean(true) = $0 { true } else { false }
            }) else { return control.trueValue?.arrayValue?.first ?? control.trueValue ?? .number(0) }
            if let mappedValues = control.trueValue?.arrayValue {
                return mappedValues[safe: selectedIndex] ?? .boolean(true)
            }
            return control.trueValue ?? .number(Double(selectedIndex))
        }
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
