import SwiftUI

struct FrameworkBreakpointSwitchRow: View {
    let screen: FrameworkScreen
    let editor: ProjectEditor
    @State private var enabled = true

    var body: some View {
        GridRow {
            Label(screen.id.shortTitle, systemImage: screen.id.systemImage)
            Text("\(Int(screen.minimumWidth)) px").monospacedDigit()
            Text(screen.container.unit == .auto ? "Fluid" : "\(Int(screen.container.value)) px")
                .monospacedDigit()
            if screen.id == .mobile {
                Text("Always on").foregroundStyle(.secondary)
            } else {
                Toggle("Enable \(screen.id.shortTitle)", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Show this size in the canvas and responsive controls. When off, container width inherits the previous enabled size.")
            }
        }
        .onAppear { enabled = screen.isEnabled }
        .onChange(of: screen.isEnabled) { _, value in enabled = value }
        .onChange(of: enabled) { _, value in
            guard value != screen.isEnabled else { return }
            editor.setFrameworkScreenEnabled(screen.id, value: value)
        }
    }
}
