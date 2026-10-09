import SwiftUI

struct FrameworkBreakpointSettings: View {
    let screens: ScreenTokens
    let editor: ProjectEditor
    var canEdit = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Breakpoints")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 16) {
                    GridRow {
                        Text("Breakpoint")
                        Text("Starts at")
                        Text("Container max")
                        Text("Enabled")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    ForEach(screens.screens) { screen in
                        FrameworkBreakpointSwitchRow(screen: screen, editor: editor)
                    }
                }
                .disabled(!canEdit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .accessibilityIdentifier("framework-section-Breakpoints")
    }
}
