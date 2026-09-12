import AppKit
import SwiftUI

/// Palette editing generator. Its resolved sRGB shades are stored with the theme;
/// rendering and export read those stored values rather than rerunning this algorithm.
/// Oklab matrices: Björn Ottosson's public-domain reference implementation:
/// https://bottosson.github.io/posts/oklab/
enum PreviewPerceptualRamp {
    struct Lab {
        let lightness: Double
        let a: Double
        let b: Double
    }

    static func lab(_ colour: NSColor) -> Lab {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        let r = linear(rgb.redComponent), g = linear(rgb.greenComponent), b = linear(rgb.blueComponent)
        let l = cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
        let m = cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
        let s = cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
        return Lab(lightness: 0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
                   a: 1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
                   b: 0.0259040371*l + 0.7827717662*m - 0.8086757660*s)
    }

    static func colour(base: NSColor, offset: Int) -> Color {
        if offset == 0 { return Color(nsColor: base) }
        let source = lab(base)
        let l = min(1, max(0, source.lightness))
        let room = offset > 0 ? 1 - l : l
        // Equal initial slope on either side; smoothly compress as available lightness runs out.
        // Ends are consequences of step count, not prescribed near-white/near-black targets.
        let distance = room > 1e-9 ? room * -expm1(-0.065 * Double(abs(offset)) / room) : 0
        let targetL = l + (offset > 0 ? distance : -distance)
        let ratio = offset > 0 ? (1 - targetL) / max(1 - l, 1e-9) : targetL / max(l, 1e-9)
        let taper = pow(max(0, min(1, ratio)), 0.35)
        // Scaling a and b together changes OKLCH chroma without rotating hue.
        return mappedColour(Lab(lightness: targetL, a: source.a * taper, b: source.b * taper))
    }

    static func blend(_ start: Color, _ end: Color, amount: Double) -> Color {
        if amount <= 0 { return start }
        if amount >= 1 { return end }
        let first = lab(NSColor(start)), last = lab(NSColor(end))
        return mappedColour(Lab(lightness: first.lightness + (last.lightness - first.lightness) * amount,
                                a: first.a + (last.a - first.a) * amount,
                                b: first.b + (last.b - first.b) * amount))
    }

    private static func mappedColour(_ source: Lab) -> Color {
        var chromaScale = 1.0
        if !inGamut(rgb(source)) {
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if inGamut(rgb(Lab(lightness: source.lightness, a: source.a * mid, b: source.b * mid))) { low = mid }
                else { high = mid }
            }
            chromaScale = low
        }
        let result = rgb(Lab(lightness: source.lightness, a: source.a * chromaScale, b: source.b * chromaScale))
        return Color(.sRGB, red: encoded(result.0), green: encoded(result.1), blue: encoded(result.2))
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> Double {
        let c = min(1, max(0, value)) // Only numerical residuals remain after chroma reduction.
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func inGamut(_ colour: (Double, Double, Double)) -> Bool {
        [colour.0, colour.1, colour.2].allSatisfy { $0 >= -1e-8 && $0 <= 1 + 1e-8 }
    }

    private static func rgb(_ colour: Lab) -> (Double, Double, Double) {
        let l = colour.lightness + 0.3963377774 * colour.a + 0.2158037573 * colour.b
        let m = colour.lightness - 0.1055613458 * colour.a - 0.0638541728 * colour.b
        let s = colour.lightness - 0.0894841775 * colour.a - 1.2914855480 * colour.b
        return (4.0767416621*l*l*l - 3.3077115913*m*m*m + 0.2309699292*s*s*s,
                -1.2684380046*l*l*l + 2.6097574011*m*m*m - 0.3413193965*s*s*s,
                -0.0041960863*l*l*l - 0.7034186147*m*m*m + 1.7076147010*s*s*s)
    }
}
