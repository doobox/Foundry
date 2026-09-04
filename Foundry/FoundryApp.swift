import SwiftUI

nonisolated enum EditorWindowSize {
    static let minimumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 640
    static let idealWidth: CGFloat = 1_440
    static let idealHeight: CGFloat = 900
}

@main
struct FoundryApp: App {
    @NSApplicationDelegateAdaptor(FoundryApplicationDelegate.self) private var applicationDelegate
    @State private var workspaceLibrary = WorkspacePresetLibrary()

    init() {
        _ = ComponentPackageCatalog.shared
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoundryDocument() }) { file in
            ContentView(document: file.document)
                .environment(workspaceLibrary)
        }
        .commands {
            PublishingMenuCommands()
        }
        .defaultSize(width: EditorWindowSize.idealWidth, height: EditorWindowSize.idealHeight)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        WindowGroup("Theme", id: "theme-editor", for: UUID.self) { $presentationID in
            ThemeWindowSceneContent(presentationID: presentationID)
                .frame(
                    minWidth: 1_104,
                    idealWidth: 1_104,
                    maxWidth: .infinity,
                    minHeight: 661,
                    idealHeight: 661,
                    maxHeight: .infinity
                )
        }
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
        .defaultSize(width: 1_104, height: 661)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}
