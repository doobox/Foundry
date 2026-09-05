import SwiftUI
import WebKit

struct AvailableComponentUpdatesWindow: View {
    @State private var manager = ComponentUpdateManager.shared
    @State private var operationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .top
            )
        }
        .frame(minWidth: 620, minHeight: 430)
        .task {
            if manager.items.isEmpty { await manager.checkAll() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Component Updates").font(.title2.bold())
                Text("Keep installed components current and secure.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Again", systemImage: "arrow.clockwise") {
                start { await manager.checkAll() }
            }
            .disabled(manager.isChecking || manager.isUpdating)
            Button("Update All", systemImage: "arrow.down.circle") {
                start { await manager.installAll() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.items.isEmpty || manager.isChecking || manager.isUpdating)
            if manager.isChecking || manager.isUpdating {
                Button("Cancel", role: .cancel) { operationTask?.cancel() }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if manager.isChecking {
            ContentUnavailableView {
                ProgressView().controlSize(.large)
                Text("Checking for Updates")
            } description: {
                Text("Contacting component update servers…")
            }
        } else if manager.items.isEmpty {
            ContentUnavailableView(
                manager.checkMessage == "All components are up to date." ? "Components Are Up to Date" : "Update Check Incomplete",
                systemImage: manager.checkMessage == "All components are up to date." ? "checkmark.circle" : "exclamationmark.triangle",
                description: Text(manager.checkMessage ?? "No updates are currently available.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let message = manager.checkMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let message = manager.completedMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(manager.items) { item in
                        ComponentUpdateRow(item: item, install: {
                            start { await manager.install(id: item.id) }
                        })
                    }
                }
                .padding(20)
            }
        }
    }

    private func start(_ operation: @escaping @MainActor () async -> Void) {
        operationTask?.cancel()
        operationTask = Task { await operation() }
    }
}

private struct ComponentUpdateRow: View {
    let item: ComponentUpdateManager.Item
    let install: () -> Void
    @State private var showsReleaseNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.update.title).font(.headline)
                    Text("\(item.update.currentVersion) → \(item.update.release.version)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let notesURL = item.update.release.releaseNotesURL {
                    Button("View Release Notes") { showsReleaseNotes = true }
                        .popover(isPresented: $showsReleaseNotes) {
                            ReleaseNotesView(url: notesURL).frame(width: 520, height: 420)
                        }
                }
                action
            }
            if case .updating(let progress) = item.state {
                ProgressView(value: progress) { Text("Updating…") }
            }
            if case .failed(let message) = item.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var action: some View {
        switch item.state {
        case .available: Button("Update", action: install).buttonStyle(.borderedProminent)
        case .updating: ProgressView().controlSize(.small)
        case .installed: Label("Updated", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Button("Retry", action: install)
        }
    }
}

private struct ReleaseNotesView: View {
    let url: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Release Notes").font(.headline)
                Spacer()
                Link("Open in Browser", destination: url)
            }
            ReleaseNotesWebView(url: url)
        }
        .padding(16)
    }
}

private struct ReleaseNotesWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        webView.load(request)
    }
}
