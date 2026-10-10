import AppKit

/// The panel displays an sRGB preview; only user changes replace the exact saved base.
@MainActor
final class BootstrapColourPicker: NSObject {
    private static weak var owner: BootstrapColourPicker?
    private var initializing = false
    private var onChange: ((NSColor) -> Void)?

    func open(colour: NSColor, onChange: @escaping (NSColor) -> Void) {
        Self.owner?.stop()
        Self.owner = self
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.isContinuous = true
        panel.showsAlpha = false
        initializing = true
        panel.color = colour
        initializing = false
        panel.orderFront(nil)
    }

    @objc func changed(_ sender: NSColorPanel) {
        guard Self.owner === self, !initializing else { return }
        onChange?(sender.color)
    }

    func stop() {
        onChange = nil
        guard Self.owner === self else { return }
        Self.owner = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }
}

extension BootstrapColourScale {
    /// Ottosson's linear-sRGB → Oklab matrices, followed by polar conversion.
    /// https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
    static func picked(_ colour: NSColor) -> Self? {
        guard let rgb = colour.usingColorSpace(.extendedSRGB) else { return nil }
        func linear(_ v: Double) -> Double {
            let a = abs(v)
            return (v < 0 ? -1 : 1) * (a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4))
        }
        let r = linear(rgb.redComponent), g = linear(rgb.greenComponent), b = linear(rgb.blueComponent)
        let l = cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
        let m = cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
        let s = cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
        let lightness = min(1, max(0, 0.2104542553*l + 0.7936177850*m - 0.0040720468*s))
        let a = 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
        let bb = 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
        let chroma = hypot(a, bb)
        let hue = chroma < 0.000001 ? 0 : (atan2(bb, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return Self(base: String(format: "oklch(%.10f%% %.10f %.10f)", locale: Locale(identifier: "en_US_POSIX"),
                                 lightness * 100, chroma < 0.000001 ? 0 : chroma, hue))
    }
}
