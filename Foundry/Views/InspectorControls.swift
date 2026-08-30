import AppKit
import SwiftUI

struct InspectorControlRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let content: Content

    init(
        _ title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.small)
        .font(.callout)
    }
}

struct InspectorSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formattedValue: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(formattedValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Slider(value: $value, in: range, step: step)
        }
    }
}

struct InspectorResponsiveIndicator: View {
    let isVisible: Bool
    let isOverridden: Bool
    let breakpointName: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Circle()
                .fill(isOverridden ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .help(helpText)
        .accessibilityLabel("Responsive setting")
        .accessibilityValue(accessibilityValue)
    }

    private var helpText: String {
        isOverridden
            ? "Using a custom value at \(breakpointName). Click to inherit."
            : "Inherited at \(breakpointName). Click to create an override."
    }

    private var accessibilityValue: String {
        isOverridden ? "Overridden at \(breakpointName)" : "Inherited at \(breakpointName)"
    }
}

struct InspectorColorWell: View {
    @Binding var color: Color
    let supportsAlpha: Bool

    init(color: Binding<Color>, supportsAlpha: Bool = false) {
        _color = color
        self.supportsAlpha = supportsAlpha
    }

    var body: some View {
        AppKitColorWell(color: $color, supportsAlpha: supportsAlpha)
            .frame(width: 58, height: 22)
            .accessibilityLabel("Choose colour")
    }
}

private struct AppKitColorWell: NSViewRepresentable {
    @Binding var color: Color
    let supportsAlpha: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell(style: .minimal)
        colorWell.controlSize = .small
        colorWell.supportsAlpha = supportsAlpha
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ colorWell: NSColorWell, context: Context) {
        context.coordinator.color = $color
        context.coordinator.isUpdating = true
        colorWell.color = NSColor(color)
        colorWell.supportsAlpha = supportsAlpha
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject {
        var color: Binding<Color>
        var isUpdating = false

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard !isUpdating else { return }
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}
