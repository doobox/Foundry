import SwiftUI

typealias ThemeBorderWidthPartControl = ThemeSpacingPartControl<BorderWidthPolicy>
typealias ThemeRadiusPartControl = ThemeSpacingPartControl<RadiusPolicy>
typealias ThemePaddingPartControl = ThemeSpacingPartControl<PaddingPolicy>
typealias ThemeMarginPartControl = ThemeSpacingPartControl<MarginPolicy>

struct ThemeSpacingPartControl<Policy: ThemeSpacingPolicy>: View {
    var label: String? = nil
    let theme: Theme
    var indicator: InspectorRowIndicator? = nil
    @Binding var value: ThemeSpacingValue<Policy>
    @Namespace private var focusNamespace
    private typealias Edge = ThemeSpacingValue<Policy>.Edge

    var body: some View {
        InspectorGrid(contentInsets: EdgeInsets()) {
            InspectorRow(title: resolvedLabel, indicator: indicator) {
                EdgesControl(
                    verticalLinked: value.verticalLinked,
                    horizontalLinked: value.horizontalLinked,
                    usesThemeTokens: !value.value(for: .top).isCustom,
                    focusNamespace: focusNamespace,
                    toggleVerticalLink: { value.togglePair(using: .top) },
                    toggleHorizontalLink: { value.togglePair(using: .left) },
                    toggleUsesThemeTokens: {
                        value.setUsesThemeTokens(value.value(for: .top).isCustom, theme: theme)
                    },
                    top: { edgeInput(.top) },
                    right: { edgeInput(.right) },
                    bottom: { edgeInput(.bottom) },
                    left: { edgeInput(.left) }
                )
            }
        }
    }

    private func edgeInput(_ edge: Edge) -> some View {
        let binding = Binding(get: { value.value(for: edge) }, set: { value.set($0, for: edge) })
        return ThemeSpacingInput<Policy>(binding: binding, title: edge.title, theme: theme, focusNamespace: focusNamespace)
    }

    var resolvedLabel: String {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Policy.label }
        return label
    }
}
