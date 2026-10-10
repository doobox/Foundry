import SwiftUI

struct ThemeBreakpointSettings: View {
    let screens: ScreenTokens
    let editor: ProjectEditor
    var canEdit = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Breakpoints")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Bootstrap's breakpoint widths are fixed. Choose which sizes this site uses; a disabled size keeps the previous container width.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 16) {
                    GridRow {
                        Text("Breakpoint")
                        Text("Enabled")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    ForEach(screens.screens) { screen in
                        ThemeBreakpointSwitchRow(screen: screen, editor: editor)
                    }
                }
                .disabled(!canEdit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .accessibilityIdentifier("theme-section-Breakpoints")
    }
}
