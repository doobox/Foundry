import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("rgb("), value.hasSuffix(")") {
            let parts = value
                .dropFirst(4)
                .dropLast()
                .split(whereSeparator: { $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard parts.count == 4 else { return nil }
            self.init(
                red: parts[0] / 255,
                green: parts[1] / 255,
                blue: parts[2] / 255,
                opacity: min(max(parts[3], 0), 1)
            )
            return
        }
        guard value.hasPrefix("#") else { return nil }

        let digits = String(value.dropFirst())
        guard [6, 8].contains(digits.count), let rgba = UInt64(digits, radix: 16) else { return nil }

        let rgb = digits.count == 8 ? rgba >> 8 : rgba
        let alpha = digits.count == 8 ? Double(rgba & 0xFF) / 255 : 1

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: alpha
        )
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }

    var hexStringWithAlpha: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
            Int((color.alphaComponent * 255).rounded())
        )
    }

    var cssStringWithAlpha: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let alpha = Double(color.alphaComponent).formatted(
            .number.precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US_POSIX"))
        )
        return String(
            format: "rgb(%d %d %d / %@)",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
            alpha
        )
    }
}
