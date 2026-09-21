import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            PreviewSettingsView()
                .tabItem {
                    Label("Preview", systemImage: "safari")
                }

            DeveloperSettingsView()
                .tabItem {
                    Label("Developer", systemImage: "apple.terminal")
                }
        }
        .task {
            appearance.apply()
        }
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
    }
}

/// Sizes a settings tab to its content, and only allows scrolling once the
/// content outgrows the cap — so tabs fit exactly today and the window never
/// turns comically tall as preferences accumulate.
private struct SettingsPane<Content: View>: View {
    private static var width: CGFloat { 560 }
    private static var maximumHeight: CGFloat { 640 }

    @State private var contentHeight: CGFloat = 200
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollDisabled(contentHeight <= Self.maximumHeight)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { _, height in
                contentHeight = height
            }
            .frame(width: Self.width)
            .frame(height: min(contentHeight, Self.maximumHeight))
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.overridesCanvasBackground)
    private var overridesCanvasBackground = false
    @AppStorage(AppPreferenceKey.canvasBackgroundColor)
    private var canvasBackgroundHex = CanvasBackgroundPreference.defaultColor
    @AppStorage(AppPreferenceKey.automaticallyChecksPartUpdates)
    private var automaticallyChecksPartUpdates = false
    var body: some View {
        SettingsPane {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Canvas") {
                LabeledContent("Canvas Background") {
                    HStack(spacing: 10) {
                        Toggle("Override", isOn: $overridesCanvasBackground)
                            .toggleStyle(.checkbox)
                        ColorPicker(
                            "Canvas background color",
                            selection: canvasBackgroundColor,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .disabled(!overridesCanvasBackground)
                    }
                }
                Text("Changes the workspace behind the page without affecting the exported site.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            }

            Section("Part Updates") {
                Toggle("Automatically Check for Part Updates", isOn: $automaticallyChecksPartUpdates)
                Text("Checks 30 seconds to 2 minutes after Foundry opens and shows the updates window only when updates are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Library Folder") {
                    HStack(spacing: 10) {
                        Text(libraryFolderDisplayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseLibraryFolder() }
                        Button("Use Default") { setLibraryFolder(nil) }
                            .disabled(libraryFolderPath == nil)
                    }
                }
                Text("Installed packs, templates and saved frameworks live here. Point it at a synced folder (iCloud Drive, Dropbox) to share one library across your Macs — existing content is copied to the new location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @State private var libraryFolderPath = FoundryLibraryLocation.customPath

    private var libraryFolderDisplayPath: String {
        if let libraryFolderPath {
            return (libraryFolderPath as NSString).abbreviatingWithTildeInPath
        }
        return "Application Support (Default)"
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder that holds Foundry's packs, templates and frameworks."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setLibraryFolder(FoundryLibraryLocation.resolvedRoot(forChosen: url).path)
    }

    private func setLibraryFolder(_ path: String?) {
        let previousRoot = try? FoundryLibraryLocation.rootURL()
        FoundryLibraryLocation.customPath = path
        libraryFolderPath = path
        if let previousRoot, let newRoot = try? FoundryLibraryLocation.rootURL() {
            FoundryLibraryLocation.migrateContent(from: previousRoot, to: newRoot)
        }
        ReusablePartLibrary.shared.reloadFromPreferredLocation()
        PartPackageCatalog.shared.reloadAllPacks()
    }

    private var canvasBackgroundColor: Binding<Color> {
        Binding(
            get: {
                Color(hex: canvasBackgroundHex)
                    ?? Color(hex: CanvasBackgroundPreference.defaultColor)
                    ?? .gray
            },
            set: { color in
                if let hex = color.hexString {
                    canvasBackgroundHex = hex
                }
            }
        )
    }
}

private struct DeveloperSettingsView: View {
    @AppStorage(AppPreferenceKey.showsDeveloperPanel)
    private var enablesDeveloperTools = false
    @AppStorage(AppPreferenceKey.enablesCanvasWebInspector)
    private var enablesCanvasWebInspector = false
    @AppStorage(AppPreferenceKey.partValidationMode)
    private var partValidationMode = PartValidationPreference.mode
    @AppStorage(AppPreferenceKey.showsHiddenParts)
    private var showsHiddenParts = false

    var body: some View {
        SettingsPane {
            Section("Parts") {
                Toggle("Enable Developer Tools", isOn: $enablesDeveloperTools)
                Text("Adds part development tools, including the developer panel and pack conversion controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Hidden Parts", isOn: $showsHiddenParts)
                Text("Shows parts whose manifest sets showsInPartLibrary to false, so supporting parts can be inspected and tested directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Part Validation", selection: $partValidationMode) {
                    ForEach(PartValidationMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Dev Packs validates parts being actively developed. All Packs also validates built-in and installed release packs, which increases loading time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Canvas") {
                Toggle("Enable Canvas Web Inspector", isOn: $enablesCanvasWebInspector)
                Text("Adds Inspect Element to the canvas context menu and exposes the canvas through Safari’s Develop menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: partValidationMode) {
            PartPackageCatalog.shared.reloadAllPacks()
        }
    }
}

private struct PreviewSettingsView: View {
    @AppStorage(AppPreferenceKey.previewApplication)
    private var selectedApplicationIdentifier = PreviewApplicationSelection.systemDefault
    @AppStorage(AppPreferenceKey.externalPreviewAutoReload)
    private var externalPreviewAutoReload = false
    @State private var applications: [PreviewApplication] = []
    @State private var defaultApplication: PreviewApplication?

    var body: some View {
        SettingsPane {
            Section("Live Preview") {
                Toggle(
                    "Live Browser Preview",
                    isOn: $externalPreviewAutoReload
                )
                Text("When enabled, open browser previews refresh after edits and follow the page selected in Foundry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser") {
                Picker("Open previews with", selection: $selectedApplicationIdentifier) {
                    DefaultPreviewApplicationLabel(application: defaultApplication)
                        .tag(PreviewApplicationSelection.systemDefault)
                    // Keeps the stored choice valid while the application list
                    // is still loading, or after that browser was uninstalled.
                    if hasMissingSelection {
                        Text(selectedApplicationIdentifier)
                            .tag(selectedApplicationIdentifier)
                    }
                    Divider()
                    ForEach(applications) { application in
                        Label {
                            Text(application.name)
                        } icon: {
                            Image(nsImage: application.icon)
                        }
                        .tag(application.bundleIdentifier)
                    }
                }

                Text("The list comes from apps currently registered with macOS to open web pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            refreshApplications()
        }
    }

    private var hasMissingSelection: Bool {
        selectedApplicationIdentifier != PreviewApplicationSelection.systemDefault
            && !applications.contains { $0.bundleIdentifier == selectedApplicationIdentifier }
    }

    private func refreshApplications() {
        applications = PreviewApplicationCatalog.applications()
        defaultApplication = PreviewApplicationCatalog.defaultApplication()
        if selectedApplicationIdentifier != PreviewApplicationSelection.systemDefault,
           !applications.contains(where: { $0.bundleIdentifier == selectedApplicationIdentifier }) {
            selectedApplicationIdentifier = PreviewApplicationSelection.systemDefault
        }
    }
}

private struct DefaultPreviewApplicationLabel: View {
    let application: PreviewApplication?

    var body: some View {
        Label {
            if let application {
                Text("System Default (\(application.name))")
            } else {
                Text("System Default")
            }
        } icon: {
            if let application {
                Image(nsImage: application.icon)
            } else {
                Image(systemName: "safari")
            }
        }
    }
}
