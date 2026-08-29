import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }

        let digits = String(value.dropFirst())
        guard digits.count == 6, let rgb = UInt64(digits, radix: 16) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
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
}
