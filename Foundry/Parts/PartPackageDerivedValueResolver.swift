import Foundation

nonisolated enum PartPackageDerivedValueResolver {
    static func resolve(
        _ values: [String: PartPackageValue],
        properties: [PartPackageProperty]
    ) -> [String: PartPackageValue] {
        var result = values

        for property in properties where property.control.type == .button {
            guard let stored = result[property.id] else { continue }
            result[property.id] = buttonValue(stored, control: property.control)
        }

        for property in properties where property.control.type == .color {
            guard let stored = result[property.id] else { continue }
            addColorChannels(for: property.id, stored: stored, control: property.control, to: &result)
            result[property.id] = colorValue(stored, control: property.control)
        }

        for property in properties where property.control.type == .date {
            guard let stored = result[property.id] else { continue }
            addDateValues(for: property.id, stored: stored, to: &result)
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
        _ stored: PartPackageValue,
        control: PartPackageControl
    ) -> PartPackageValue {
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

    private static func colorValue(
        _ stored: PartPackageValue,
        control: PartPackageControl
    ) -> PartPackageValue {
        switch stored {
        case .string(let value):
            guard let color = PartColorChannels(hex: value) else { return stored }
            return .string(color.formatted(
                as: control.outputFormat ?? .hex,
                includesOpacity: control.opacity == true
            ))
        case .array(let values):
            return .array(values.map { colorValue($0, control: control) })
        default:
            return stored
        }
    }

    private static func addColorChannels(
        for propertyID: String,
        stored: PartPackageValue,
        control: PartPackageControl,
        to values: inout [String: PartPackageValue]
    ) {
        switch stored {
        case .string(let value):
            guard let color = PartColorChannels(hex: value) else { return }
            addColorValues(color, reference: propertyID, control: control, to: &values)
        case .array(let colors):
            for (index, value) in colors.enumerated() {
                guard case .string(let hex) = value,
                      let color = PartColorChannels(hex: hex) else { continue }
                addColorValues(color, reference: "\(propertyID)[\(index)]", control: control, to: &values)
            }
        default:
            return
        }
    }

    private static func addColorValues(
        _ color: PartColorChannels,
        reference: String,
        control: PartPackageControl,
        to values: inout [String: PartPackageValue]
    ) {
        for (name, value) in color.derivedValues {
            values["\(reference).\(name)"] = value
        }
        values["\(reference).__colorSource"] = .string(color.hex(includesOpacity: true, includesHash: true))
        values["\(reference).__colorFormat"] = .string((control.outputFormat ?? .hex).rawValue)
        values["\(reference).__colorOpacity"] = .boolean(control.opacity == true)
    }

    /// Derived values for a theme colour, which is a light/dark pair rather than one
    /// fixed colour. Everything numeric lives behind `.light`/`.dark` qualification —
    /// a bare number baked into a static file cannot follow an appearance switch.
    /// Colour-valued outputs (`contrastColor`, filter sources) stay unqualified: on a
    /// dual-appearance site they combine via `light-dark()`, which the browser
    /// resolves live, exactly like the control's main output.
    static func addThemeColorValues(
        for propertyID: String,
        light: PartColorChannels?,
        dark: PartColorChannels?,
        primary: SiteAppearance,
        combinesAppearances: Bool,
        includesOpacity: Bool,
        to values: inout [String: PartPackageValue]
    ) {
        let fragmentFormats: [PartPackageControl.ColorOutputFormat] = [
            .hexValue, .rgbValues, .rgbaValues, .hslValues, .hslaValues
        ]
        for (appearance, color) in [(SiteAppearance.light, light), (.dark, dark)] {
            guard let color else { continue }
            let reference = "\(propertyID).\(appearance.rawValue)"
            values[reference] = .string(color.formatted(as: .hex, includesOpacity: includesOpacity))
            for (name, value) in color.derivedValues {
                values["\(reference).\(name)"] = value
            }
            for format in fragmentFormats {
                values["\(reference).\(format.rawValue)"] = .string(
                    color.formatted(as: format, includesOpacity: includesOpacity)
                )
            }
            values["\(reference).__colorSource"] = .string(color.hex(includesOpacity: true, includesHash: true))
            values["\(reference).__colorFormat"] = .string(PartPackageControl.ColorOutputFormat.hex.rawValue)
            values["\(reference).__colorOpacity"] = .boolean(includesOpacity)
        }

        let primaryColor = primary == .light ? light : dark
        guard let primaryColor else { return }

        if combinesAppearances, let light, let dark,
           case .string(let lightContrast)? = light.derivedValues["contrastColor"],
           case .string(let darkContrast)? = dark.derivedValues["contrastColor"] {
            values["\(propertyID).contrastColor"] = .string(
                lightContrast == darkContrast
                    ? lightContrast
                    : "light-dark(\(lightContrast), \(darkContrast))"
            )
        } else if case .string(let contrast)? = primaryColor.derivedValues["contrastColor"] {
            values["\(propertyID).contrastColor"] = .string(contrast)
        }

        values["\(propertyID).__colorSource"] = .string(primaryColor.hex(includesOpacity: true, includesHash: true))
        values["\(propertyID).__colorFormat"] = .string(PartPackageControl.ColorOutputFormat.hex.rawValue)
        values["\(propertyID).__colorOpacity"] = .boolean(includesOpacity)
        if combinesAppearances, primary == .light, let dark,
           dark.hex(includesOpacity: true, includesHash: true) != primaryColor.hex(includesOpacity: true, includesHash: true) {
            values["\(propertyID).__colorSourceDark"] = .string(dark.hex(includesOpacity: true, includesHash: true))
        }
    }

    private static func addDateValues(
        for propertyID: String,
        stored: PartPackageValue,
        to values: inout [String: PartPackageValue]
    ) {
        switch stored {
        case .string(let value):
            guard let date = PartDateValue(value) else { return }
            addDateValues(date, reference: propertyID, to: &values)
        case .array(let dates):
            for (index, value) in dates.enumerated() {
                guard case .string(let string) = value,
                      let date = PartDateValue(string) else { continue }
                addDateValues(date, reference: "\(propertyID)[\(index)]", to: &values)
            }
        default:
            return
        }
    }

    private static func addDateValues(
        _ date: PartDateValue,
        reference: String,
        to values: inout [String: PartPackageValue]
    ) {
        for (name, value) in date.derivedValues {
            values["\(reference).\(name)"] = value
        }
        values["\(reference).__dateSource"] = .string(date.isoDate)
    }

    private static func mathValue(
        control: PartPackageControl,
        values: [String: PartPackageValue]
    ) -> PartPackageValue? {
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
        _ argument: PartPackageValue?,
        values: [String: PartPackageValue]
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

nonisolated struct PartDateValue {
    let isoDate: String
    let date: Date
    let parts: DateComponents

    init?(_ value: String) {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = Self.formatter.date(from: value),
              Self.formatter.string(from: date) == value else { return nil }
        self.isoDate = value
        self.date = date
        self.parts = Self.calendar.dateComponents(
            [.year, .month, .day, .weekday],
            from: date
        )
    }

    var derivedValues: [String: PartPackageValue] {
        [
            "year": .number(Double(parts.year ?? 0)),
            "month": .number(Double(parts.month ?? 0)),
            "day": .number(Double(parts.day ?? 0)),
            "monthName": .string(formatted("MMMM")),
            "weekday": .string(formatted("EEEE"))
        ]
    }

    func formatted(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    func adding(_ unit: Calendar.Component, value: Int) -> PartDateValue? {
        guard let adjusted = Self.calendar.date(byAdding: unit, value: value, to: date) else { return nil }
        return PartDateValue(Self.string(from: adjusted))
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

nonisolated struct PartColorChannels {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double

    init(red: Int, green: Int, blue: Int, alpha: Double) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
        self.alpha = min(max(alpha, 0), 1)
    }

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        let digits = String(value.dropFirst())
        guard [6, 8].contains(digits.count), let rgba = UInt64(digits, radix: 16) else { return nil }
        let rgb = digits.count == 8 ? rgba >> 8 : rgba
        red = Int((rgb >> 16) & 0xFF)
        green = Int((rgb >> 8) & 0xFF)
        blue = Int(rgb & 0xFF)
        alpha = digits.count == 8 ? Double(rgba & 0xFF) / 255 : 1
    }

    func formatted(
        as format: PartPackageControl.ColorOutputFormat,
        includesOpacity: Bool
    ) -> String {
        let effectiveAlpha = includesOpacity ? alpha : 1
        let alphaValue = decimal(effectiveAlpha)
        let hex = String(format: "%02X%02X%02X", red, green, blue)
        let hexAlpha = String(format: "%02X", Int((effectiveAlpha * 255).rounded()))
        let hsl = hslComponents
        let hue = decimal(hsl.hue)
        let saturation = decimal(hsl.saturation)
        let lightness = decimal(hsl.lightness)

        switch format {
        case .hex:
            return "#\(hex)\(includesOpacity ? hexAlpha : "")"
        case .hexValue:
            return "\(hex)\(includesOpacity ? hexAlpha : "")"
        case .rgb:
            return includesOpacity
                ? "rgb(\(red) \(green) \(blue) / \(alphaValue))"
                : "rgb(\(red) \(green) \(blue))"
        case .rgba:
            return "rgba(\(red), \(green), \(blue), \(alphaValue))"
        case .rgbValues:
            return "\(red), \(green), \(blue)"
        case .rgbaValues:
            return "\(red), \(green), \(blue), \(alphaValue)"
        case .hsl:
            return includesOpacity
                ? "hsl(\(hue) \(saturation)% \(lightness)% / \(alphaValue))"
                : "hsl(\(hue) \(saturation)% \(lightness)%)"
        case .hsla:
            return "hsla(\(hue), \(saturation)%, \(lightness)%, \(alphaValue))"
        case .hslValues:
            return "\(hue), \(saturation)%, \(lightness)%"
        case .hslaValues:
            return "\(hue), \(saturation)%, \(lightness)%, \(alphaValue)"
        }
    }

    var derivedValues: [String: PartPackageValue] {
        let hsl = hslComponents
        return [
            "red": .number(Double(red)),
            "green": .number(Double(green)),
            "blue": .number(Double(blue)),
            "alpha": .number(alpha),
            "hue": .number(hsl.hue),
            "saturation": .number(hsl.saturation),
            "lightness": .number(hsl.lightness),
            "relativeLuminance": .number(relativeLuminance),
            "contrastColor": .string(contrastRatio(withLuminance: 0) >= contrastRatio(withLuminance: 1) ? "#000000" : "#FFFFFF"),
            "contrastRatioWithBlack": .number(contrastRatio(withLuminance: 0)),
            "contrastRatioWithWhite": .number(contrastRatio(withLuminance: 1))
        ]
    }

    func hex(includesOpacity: Bool, includesHash: Bool) -> String {
        let prefix = includesHash ? "#" : ""
        let alphaHex = includesOpacity ? String(format: "%02X", Int((alpha * 255).rounded())) : ""
        return prefix + String(format: "%02X%02X%02X", red, green, blue) + alphaHex
    }

    func mixed(with other: PartColorChannels, amount: Double) -> PartColorChannels {
        let amount = min(max(amount, 0), 1)
        return PartColorChannels(
            red: Int((Double(red) + (Double(other.red) - Double(red)) * amount).rounded()),
            green: Int((Double(green) + (Double(other.green) - Double(green)) * amount).rounded()),
            blue: Int((Double(blue) + (Double(other.blue) - Double(blue)) * amount).rounded()),
            alpha: alpha + (other.alpha - alpha) * amount
        )
    }

    func withAlpha(_ alpha: Double) -> PartColorChannels {
        PartColorChannels(red: red, green: green, blue: blue, alpha: alpha)
    }

    private var relativeLuminance: Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func contrastRatio(withLuminance other: Double) -> Double {
        (max(relativeLuminance, other) + 0.05) / (min(relativeLuminance, other) + 0.05)
    }

    private var hslComponents: (hue: Double, saturation: Double, lightness: Double) {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }
        return (hue < 0 ? hue + 360 : hue, saturation * 100, lightness * 100)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...3))
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

private nonisolated extension PartPackageValue {
    var arrayValue: [PartPackageValue]? {
        if case .array(let values) = self { values } else { nil }
    }
}

private nonisolated extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
