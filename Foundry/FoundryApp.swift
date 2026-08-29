import SwiftUI

nonisolated enum EditorWindowSize {
    static let minimumWidth: CGFloat = 720
    static let minimumHeight: CGFloat = 520
    static let idealWidth: CGFloat = 1_440
    static let idealHeight: CGFloat = 900
}

@main
struct FoundryApp: App {
    @State private var workspaceLibrary = WorkspacePresetLibrary()

    init() {
        _ = ComponentPackageCatalog.shared
        _ = FoundryPackCatalog.shared
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoundryDocument() }) { file in
            ContentView(document: file.document)
                .environment(workspaceLibrary)
        }
        .defaultSize(width: EditorWindowSize.idealWidth, height: EditorWindowSize.idealHeight)
        .windowToolbarStyle(.unified)

        Window("Manage Workspaces", id: "workspace-manager") {
            WorkspaceManagerView()
                .environment(workspaceLibrary)
        }
        .defaultSize(width: 480, height: 320)

        Settings {
            SettingsView()
        }
    }
}
