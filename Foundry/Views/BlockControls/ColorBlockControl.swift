import SwiftUI

struct BasicColorBlockControl<TokenPicker: View>: View {
    let label: String
    let selectedToken: DesignToken?
    let indicator: InspectorRowIndicator?
    @Binding var color: Color
    @ViewBuilder let tokenPicker: () -> TokenPicker

    var body: some View {
        Group {
            InspectorRow(title: "Source", control: tokenPicker)
            if selectedToken == nil {
                InspectorRow(title: label, alignment: .center, indicator: indicator) {
                    InspectorColorWell(color: $color)
                }
            }
        }
    }
}

#Preview("Colour") {
    @Previewable @State var color = Color.blue
    BlockControlPreview {
        ColorBlockControl(label: "Colour", allowsOpacity: true, indicator: .preview, color: $color)
    }
}

struct ColorBlockControl: View {
    let label: String
    let allowsOpacity: Bool
    let indicator: InspectorRowIndicator?
    @Binding var color: Color

    var body: some View {
        InspectorRow(title: label, alignment: .center, indicator: indicator) {
            InspectorColorWell(color: $color, supportsAlpha: allowsOpacity)
        }
    }
}
