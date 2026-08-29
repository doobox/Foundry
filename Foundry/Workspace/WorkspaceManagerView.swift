import SwiftUI

struct WorkspaceManagerView: View {
    @Environment(WorkspacePresetLibrary.self) private var library

    var body: some View {
        Group {
            if library.presets.isEmpty {
                ContentUnavailableView(
                    "No Saved Workspaces",
                    systemImage: "square.grid.2x2",
                    description: Text("Use Save Workspace As… from the workspace menu to add one.")
                )
            } else {
                List {
                    ForEach(library.presets) { preset in
                        WorkspaceManagerRow(preset: preset) {
                            library.delete(preset.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Workspaces")
        .frame(minWidth: 420, minHeight: 260)
    }
}

private struct WorkspaceManagerRow: View {
    let preset: WorkspacePreset
    let delete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
            Text(preset.name)
            Spacer()
            Button("Delete \(preset.name)", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete \(preset.name)")
        }
        .padding(.vertical, 4)
    }
}
