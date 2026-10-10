import SwiftUI
import AppKit

struct WelcomeView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var recentProjects: [URL] = []
    @State private var selectedProject: URL?
    @State private var isChoosingFile = false
    @State private var isOpening = false
    @State private var openingError: String?
    @FocusState private var recentsFocused: Bool

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 116, height: 116)
                    .accessibilityHidden(true)
                Text("Foundry")
                    .font(.system(size: 18, weight: .semibold))
                Text(version)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Open…") { isChoosingFile = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("New Project") {
                    openWindow(id: "new-project")
                    dismissWindow(id: "welcome")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .buttonStyle(.bordered)
            .buttonSizing(.flexible)
            .controlSize(.extraLarge)
            .disabled(isOpening)

            recentProjectsList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("Recent Projects")
                .overlay {
                    if isOpening {
                        ProgressView("Opening project…")
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
        }
        .padding(.horizontal, 48)
        .padding(.top, 70)
        .padding(.bottom, 28)
        .frame(width: 480, height: 600)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .background(WelcomeWindowAppearance())
        .overlay(alignment: .topLeading) {
            Button { dismissWindow(id: "welcome") } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Close")
            .accessibilityLabel("Close welcome window")
            .padding(20)
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .onAppear(perform: refreshRecents)
        .task { recentsFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRecents()
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.foundryProject]) { result in
            switch result {
            case .success(let url): openProject(url)
            case .failure(let error): openingError = error.localizedDescription
            }
        }
        .alert("Couldn’t Open Project", isPresented: Binding(
            get: { openingError != nil }, set: { if !$0 { openingError = nil } }
        )) {
            Button("OK") { openingError = nil }
        } message: {
            Text(openingError ?? "")
        }
    }

    @ViewBuilder private var recentProjectsList: some View {
        if recentProjects.isEmpty {
            ContentUnavailableView("No Recent Projects", systemImage: "doc.on.doc",
                description: Text("Open a project or create a new one."))
        } else {
            List(selection: $selectedProject) {
                ForEach(recentProjects, id: \.self) { url in
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                    Text(directoryLabel(for: url))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        .tag(url)
                        .help(url.path)
                }
            }
            .listStyle(.inset)
            .focused($recentsFocused)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: URL.self) { urls in
                if let url = urls.first {
                    Button("Open") { openProject(url) }
                }
            } primaryAction: { urls in
                if let url = urls.first { openProject(url) }
            }
            .disabled(isOpening)
        }
    }

    private func refreshRecents() {
        recentProjects = NSDocumentController.shared.recentDocumentURLs
            .filter { $0.pathExtension.lowercased() == "foundry" }
        if selectedProject == nil || !recentProjects.contains(selectedProject!) {
            selectedProject = recentProjects.first
        }
    }

    private func directoryLabel(for url: URL) -> String {
        let directory = url.deletingLastPathComponent().path as NSString
        return directory.abbreviatingWithTildeInPath
    }

    private func openProject(_ url: URL) {
        guard !isOpening else { return }
        isOpening = true
        Task { @MainActor in
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isOpening = false
            }
            do {
                try await openDocument(at: url)
                refreshRecents()
                dismissWindow(id: "welcome")
            } catch {
                openingError = error.localizedDescription
            }
        }
    }
}

private struct WelcomeWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowProbe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.hasShadow = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.invalidateShadow()
        }
    }
}
