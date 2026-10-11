import Foundation

/// A fixed hex colour or an appearance-aware pair. One supplied mode serves both.
nonisolated struct PartIconColour: Codable, Equatable, Hashable, Sendable {
    let light: String
    let dark: String

    init(light: String, dark: String? = nil) {
        self.light = light
        self.dark = dark ?? light
    }

    static let neutral = Self(light: "#8E8E93", dark: "#98989D")
    static let white = Self(light: "#FFFFFF")

    var cacheKey: String { "\(light):\(dark)" }

    static func isValidHex(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (bytes.count == 7 || bytes.count == 9) && bytes.first == 35 &&
            bytes.dropFirst().allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    private enum CodingKeys: String, CodingKey { case light, dark }

    init(from decoder: Decoder) throws {
        if let hex = try? decoder.singleValueContainer().decode(String.self) {
            guard Self.isValidHex(hex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected #RRGGBB or #RRGGBBAA."))
            }
            self.init(light: hex)
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let light = try values.decodeIfPresent(String.self, forKey: .light)
            let dark = try values.decodeIfPresent(String.self, forKey: .dark)
            guard let first = light ?? dark,
                  Self.isValidHex(first),
                  dark.map(Self.isValidHex) ?? true else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Supply light and/or dark using #RRGGBB or #RRGGBBAA."))
            }
            self.init(light: first, dark: dark)
        }
    }

    func encode(to encoder: Encoder) throws {
        if light == dark {
            var value = encoder.singleValueContainer()
            try value.encode(light)
        } else {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(light, forKey: .light)
            try values.encode(dark, forKey: .dark)
        }
    }
}
