import SwiftUI

/// Page overrides use the same complete picker modules as `colourControls`.
struct PageColourOverrideControl: View {
    let purpose: PartColourPurpose
    let theme: Theme
    @Binding var selection: String
    @Binding var adjustment: PageColourAdjustment

    private var title: String {
        switch purpose {
        case .background: "Background"
        case .foreground: "Foreground"
        case .border: "Border"
        case .link: "Links"
        }
    }

    private var variantOptions: [InspectorPopupOption<String>] {
        switch purpose {
        case .foreground: [
            .init(title: "Normal", value: "normal"),
            .init(title: "Emphasis", value: "emphasis"),
            .init(title: "Contrast", value: "contrast")
        ]
        case .background: [
            .init(title: "Solid", value: "solid"),
            .init(title: "Subtle", value: "subtle"),
            .init(title: "Muted", value: "muted")
        ]
        case .border: [
            .init(title: "Normal", value: "normal"),
            .init(title: "Subtle", value: "subtle")
        ]
        case .link: []
        }
    }

    private var tokenSections: [String] {
        // Retain the page's existing black/white choices while using the
        // same complete theme-aware picker modules as parts.
        switch purpose {
        case .background, .border: purpose.defaultSections + ["blackWhite"]
        default: purpose.defaultSections
        }
    }

    private var variantBinding: Binding<String> {
        Binding(
            get: { purpose == .background && adjustment.variant == "normal" ? "solid" : adjustment.variant },
            set: { adjustment.variant = $0 }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { adjustment.opacity }, set: { adjustment.opacity = $0 })
    }

    var body: some View {
        InspectorGrid(contentInsets: EdgeInsets()) {
            ThemeColorsPartControl(
                label: title,
                theme: theme,
                tokenSections: tokenSections,
                themePreviewRole: PartColourPurpose.previewRole(purpose: purpose, group: .colourControls, variant: adjustment.variant),
                linksOnly: purpose == .link,
                allowsInherit: true,
                selection: $selection
            )
            if selection != "inherit" {
                if PartColourToken.parse(selection) == nil, !variantOptions.isEmpty {
                    SelectPartControl(label: purpose == .background ? "Surface" : "Variant",
                        options: variantOptions, indicator: nil, selection: variantBinding)
                }
                SliderPartControl(label: "Opacity",
                    options: SliderOptions(range: 0...100, step: 10, unit: "%", editableValue: true),
                    indicator: nil, value: opacityBinding)
            }
        }
    }
}
