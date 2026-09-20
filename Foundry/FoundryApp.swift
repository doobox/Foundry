import SwiftUI

nonisolated enum EditorWindowSize {
    static let minimumWidth: CGFloat = 1_100
    static let minimumHeight: CGFloat = 700
    static let idealWidth: CGFloat = 1_500
    static let idealHeight: CGFloat = 900
}

@main
struct FoundryApp: App {
    @NSApplicationDelegateAdaptor(FoundryApplicationDelegate.self) private var applicationDelegate
    @State private var workspaceLibrary = WorkspacePresetLibrary()

    init() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            _ = PartPackageCatalog.shared
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: { FoundryDocument() }) { file in
            ContentView(document: file.document)
                .environment(workspaceLibrary)
                //.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbarBackground(.quinary, for: .windowToolbar)
                .onAppear { file.document.adoptPackageURL(file.fileURL) }
                .onChange(of: file.fileURL) { _, newURL in
                    file.document.adoptPackageURL(newURL)
                }
        }
        .commands {
            AboutMenuCommands()
            PublishingMenuCommands()
        }
        .defaultSize(width: EditorWindowSize.idealWidth, height: EditorWindowSize.idealHeight)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        Window("Welcome to Foundry", id: "welcome") {
            WelcomeView()
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)

        WindowGroup("Framework", id: "framework-editor", for: UUID.self) { $presentationID in
            FrameworkWindowSceneContent(presentationID: presentationID)
                .frame(
                    minWidth: 962,
                    idealWidth: 1_204,
                    minHeight: 504,
                    idealHeight: 661,
                    maxHeight: .infinity
                )
        }
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
        .defaultSize(width: 1_204, height: 661)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)

        WindowGroup("Site Settings", id: "site-settings", for: UUID.self) { $presentationID in
            ProjectSettingsWindowSceneContent(presentationID: presentationID)
        }
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
        .defaultSize(width: 1_000, height: 680)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)

        Window("Part Updates", id: "part-updates") {
            PartUpdatesWindow()
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)

        Window("Available Part Updates", id: "available-part-updates") {
            AvailablePartUpdatesWindow()
        }
        .defaultSize(width: 720, height: 560)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}

private struct AboutMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Foundry") {
                FoundryAboutPanel.show()
            }
        }
    }
}

@MainActor
private enum FoundryAboutPanel {
    private static let apiDescription = "Part API v\(FoundryPartAPI.currentVersion)"

    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [.credits: NSAttributedString(string: apiDescription)]
        )

        DispatchQueue.main.async {
            matchAPIDescriptionToVersionLabel()
        }
    }

    private static func matchAPIDescriptionToVersionLabel() {
        for window in NSApplication.shared.windows {
            guard let contentView = window.contentView else { continue }
            let textFields = descendants(of: NSTextField.self, in: contentView)
            guard let versionField = textFields.first(where: { $0.stringValue.hasPrefix("Version ") }),
                  !versionField.attributedStringValue.string.isEmpty else {
                continue
            }

            var attributes = versionField.attributedStringValue.attributes(at: 0, effectiveRange: nil)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            attributes[.paragraphStyle] = paragraphStyle
            let description = NSAttributedString(string: apiDescription, attributes: attributes)

            if let field = textFields.first(where: { $0.stringValue == apiDescription }) {
                field.attributedStringValue = description
            }
            if let textView = descendants(of: NSTextView.self, in: contentView).first(where: {
                $0.string.trimmingCharacters(in: .whitespacesAndNewlines) == apiDescription
            }) {
                textView.textStorage?.setAttributedString(description)
            }
            return
        }
    }

    private static func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
        root.subviews.flatMap { view in
            (view as? View).map { [$0] } ?? []
                + descendants(of: type, in: view)
        }
    }
}
