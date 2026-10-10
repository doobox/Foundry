import SwiftUI

typealias ThemeBorderWidthPartControl = ThemeSpacingPartControl<BorderWidthPolicy>
typealias ThemeRadiusPartControl = ThemeSpacingPartControl<RadiusPolicy>
typealias ThemePaddingPartControl = ThemeSpacingPartControl<PaddingPolicy>
typealias ThemeMarginPartControl = ThemeSpacingPartControl<MarginPolicy>

struct ThemeSpacingPartControl<Policy: ThemeSpacingPolicy>: View {
    var label: String? = nil
    let theme: Theme
    var indicator: InspectorRowIndicator? = nil
    var bootstrapSpacing: Bool = false
    var bootstrapBorders: Bool = false
    /// False for the generic edges/corners controls: raw lengths only, no theme
    /// tokens, no mode toggle.
    var allowsThemeTokens: Bool = true
    /// Restricts the custom unit menu; nil offers the policy's full unit list.
    var unitChoices: [String]? = nil
    /// Label fallback when the manifest label is empty and Policy.label would be
    /// wrong (the generic controls reuse the margin/radius policies).
    var fallbackLabel: String? = nil
    @Binding var value: ThemeSpacingValue<Policy>
    @Namespace private var focusNamespace
    private typealias Edge = ThemeSpacingValue<Policy>.Edge

    var body: some View {
        InspectorGrid(contentInsets: EdgeInsets()) {
            InspectorRow(title: resolvedLabel, indicator: indicator) {
                if Policy.isRadius {
                    // Corners have no meaningful pair state: one link ties all four.
                    // Edge cases map to corners here — top/bottom are the two top
                    // corners, left/right the two bottom corners.
                    CornersControl(
                        linked: value.verticalLinked && value.horizontalLinked,
                        usesThemeTokens: allowsThemeTokens && !value.value(for: .top).isCustom,
                        focusNamespace: focusNamespace,
                        toggleLinked: {
                            if value.verticalLinked && value.horizontalLinked {
                                value.unlinkAll()
                            } else {
                                value.linkAll()
                            }
                        },
                        toggleUsesThemeTokens: modeToggleAction,
                        topLeft: { edgeInput(.top) },
                        topRight: { edgeInput(.bottom) },
                        bottomLeft: { edgeInput(.left) },
                        bottomRight: { edgeInput(.right) }
                    )
                } else {
                    EdgesControl(
                        verticalLinked: value.verticalLinked,
                        horizontalLinked: value.horizontalLinked,
                        usesThemeTokens: allowsThemeTokens && !value.value(for: .top).isCustom,
                        focusNamespace: focusNamespace,
                        toggleVerticalLink: { value.togglePair(using: .top) },
                        toggleHorizontalLink: { value.togglePair(using: .left) },
                        toggleUsesThemeTokens: modeToggleAction,
                        top: { edgeInput(.top) },
                        right: { edgeInput(.right) },
                        bottom: { edgeInput(.bottom) },
                        left: { edgeInput(.left) }
                    )
                }
            }
        }
    }

    private var modeToggleAction: (() -> Void)? {
        guard allowsThemeTokens && !bootstrapSpacing && !bootstrapBorders else { return nil }
        return { value.setUsesThemeTokens(value.value(for: .top).isCustom) }
    }

    @ViewBuilder private func edgeInput(_ edge: Edge) -> some View {
        let binding = Binding(get: { value.value(for: edge) }, set: { value.set($0, for: edge) })
        if bootstrapBorders {
            BootstrapBorderEdgePicker<Policy>(value: binding, title: edge == .left ? "Start" : edge == .right ? "End" : edge.title)
        } else {
            ThemeSpacingInput<Policy>(binding: binding, title: bootstrapSpacing ? (edge == .left ? "Start" : edge == .right ? "End" : edge.title) : edge.title, theme: theme, focusNamespace: focusNamespace, unitChoices: unitChoices, bootstrapSpacing: bootstrapSpacing, bootstrapClassPrefix: BootstrapSpacingClasses.edgePrefix(edge, property: Policy.self == MarginPolicy.self ? "m" : "p"))
        }
    }

    var resolvedLabel: String {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallbackLabel ?? Policy.label }
        return label
    }
}
