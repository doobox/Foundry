import Foundation

/// Reports contrast for resolved swatches; never chooses or changes theme tokens.
nonisolated enum BootstrapColourContrast {
    static func ratio(_ first: String, _ second: String) -> Double? {
        func luminance(_ hex: String) -> Double? {
            guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
            func linear(_ byte: UInt32) -> Double {
                let channel = Double(byte) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear((value >> 16) & 255) + 0.7152 * linear((value >> 8) & 255) + 0.0722 * linear(value & 255)
        }
        guard let a = luminance(first), let b = luminance(second) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
