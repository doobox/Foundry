import AppKit
import SwiftUI

struct ThemeColourSettings: View {
    let theme: Theme
    let editor: ProjectEditor

    var body: some View {
        ThemeEditorColumns {
            ThemeEditorCard(title: "Palette", subtitle: "Shared colours for your website.") {
                VStack(spacing: 0) {
                    ForEach(DesignToken.colorTokens) { token in
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(token.displayName).font(.body.weight(.medium))
                                Text(description(for: token)).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(theme.color(for: token) ?? "")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            ColorPicker(token.displayName, selection: colorBinding(for: token), supportsOpacity: false)
                                .labelsHidden()
                                .accessibilityLabel("\(token.displayName) colour")
                        }
                        .padding(.vertical, 12)
                        if token != DesignToken.colorTokens.last { Divider() }
                    }
                }
            }
        } preview: {
            VStack(spacing: 20) {
                ThemeEditorCard(title: "Preview", subtitle: "Your palette in context.") {
                    ThemePalettePreview(colors: theme.colors)
                }
                ThemeEditorCard(title: "Contrast", subtitle: "Against the Surface colour.") {
                    contrastRow("Text", foreground: theme.colors.text)
                    contrastRow("Links", foreground: theme.colors.links)
                }
            }
        }
    }

    private func description(for token: DesignToken) -> String {
        switch token {
        case .backgroundColor: "The background of the page."
        case .surfaceColor: "Cards and raised content areas."
        case .textColor: "Body text and headings."
        case .accentColor: "Emphasis and primary actions."
        default: "Linked text within your content."
        }
    }

    private func colorBinding(for token: DesignToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme.color(for: token) ?? "#FFFFFF") ?? .white },
            set: { editor.setThemePaletteColor(token, value: $0.hexString ?? "#FFFFFF") }
        )
    }

    private func contrastRow(_ title: String, foreground: String) -> some View {
        let ratio: Double? = luminance(foreground).flatMap { first in
            luminance(theme.colors.surface).map { second in
                (max(first, second) + 0.05) / (min(first, second) + 0.05)
            }
        }
        return HStack {
            Text(title)
            Spacer()
            if let ratio {
                Image(systemName: ratio >= 4.5 ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(ratio >= 4.5 ? Color.secondary : Color.orange)
                Text("\(ratio, format: .number.precision(.fractionLength(1))):1")
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .help(ratio.map { $0 >= 4.5 ? "Meets WCAG AA contrast for normal text." : "Below WCAG AA contrast for normal text (4.5:1)." }
              ?? "Contrast is shown for opaque colours only.")
        .accessibilityElement(children: .combine)
    }

    private func luminance(_ value: String) -> Double? {
        guard let color = Color(hex: value),
              let rgb = NSColor(color).usingColorSpace(.sRGB),
              rgb.alphaComponent >= 0.999 else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value in
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}

struct ThemePalettePreview: View {
    let colors: ColorTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(color(colors.accent)).frame(width: 8, height: 8)
                Text("YOUR WEBSITE").font(.system(size: 10, weight: .semibold)).tracking(1.2)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("A little more you.").font(.system(size: 28, weight: .bold))
                Text("A shared palette brings your pages together, from the first heading to the smallest detail.")
                    .font(.system(size: 14)).lineSpacing(4)
                Text("Explore the details").underline().font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color(colors.links))
                RoundedRectangle(cornerRadius: 5).fill(color(colors.accent)).frame(width: 76, height: 7)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(color(colors.surface), in: .rect(cornerRadius: 10))
            HStack(spacing: 6) {
                ForEach([colors.background, colors.surface, colors.text, colors.accent, colors.links].indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color([colors.background, colors.surface, colors.text, colors.accent, colors.links][index]))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color(colors.text).opacity(0.12), lineWidth: 1))
                        .frame(height: 20)
                }
            }
        }
        .foregroundStyle(color(colors.text))
        .padding(16)
        .background(color(colors.background), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Website colour preview")
    }

    private func color(_ hex: String) -> Color { Color(hex: hex) ?? .clear }
}
