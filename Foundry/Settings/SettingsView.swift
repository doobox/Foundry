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

private struct GeneralSettingsView: View {
    @AppStorage(AppPreferenceKey.appearance)
    private var appearance: AppAppearance = .system
    @AppStorage(AppPreferenceKey.overridesCanvasBackground)
    private var overridesCanvasBackground = false
    @AppStorage(AppPreferenceKey.canvasBackgroundColor)
    private var canvasBackgroundHex = CanvasBackgroundPreference.defaultColor
    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 310)
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
    private var showsDeveloperPanel = false
    @AppStorage(AppPreferenceKey.enablesCanvasWebInspector)
    private var enablesCanvasWebInspector = false

    var body: some View {
        Form {
            Section("Components") {
                Toggle("Show Developer Panel", isOn: $showsDeveloperPanel)
                Text("Adds a workspace panel containing component loading errors and warnings.")
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
        .formStyle(.grouped)
        .frame(width: 560, height: 260)
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
        Form {
            Section("Live Preview") {
                Toggle(
                    "Enable External Preview Auto Reload",
                    isOn: $externalPreviewAutoReload
                )
                Text("When enabled, open browser previews regenerate after project edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser") {
                Picker("Open previews with", selection: $selectedApplicationIdentifier) {
                    DefaultPreviewApplicationLabel(application: defaultApplication)
                        .tag(PreviewApplicationSelection.systemDefault)
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
        .formStyle(.grouped)
        .frame(width: 560, height: 260)
        .task {
            refreshApplications()
        }
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
