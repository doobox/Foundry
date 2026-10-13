import AppKit

extension PartIconSpecification {
    var groupColour: NSColor {
        switch group {
        case "Accessibility": .systemTeal
        case "Animation": .systemPink
        case "CMS": .systemIndigo
        case "Content", "Navigation": .systemBlue
        case "Dynamic", "Utility": .systemPurple
        case "Ecommerce": .systemGreen
        case "Forms": .systemCyan
        case "Interactive": .systemOrange
        case "Media": .systemMint
        case "Security": .systemRed
        case "SEO": .systemBrown
        default: .systemGray
        }
    }

    var tileBackgroundColour: NSColor {
        NSColor(name: nil) { appearance in
            var resolved = groupColour
            appearance.performAsCurrentDrawingAppearance {
                resolved = groupColour.usingColorSpace(.sRGB) ?? groupColour
            }
            guard let rgb = resolved.usingColorSpace(.sRGB) else { return resolved }
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let addition: CGFloat = dark ? 0 : 0.25
            return NSColor(srgbRed: rgb.redComponent * 0.75 + addition,
                           green: rgb.greenComponent * 0.75 + addition,
                           blue: rgb.blueComponent * 0.75 + addition,
                           alpha: rgb.alphaComponent)
        }
    }

    var tileForegroundColour: NSColor {
        .white
    }
}
