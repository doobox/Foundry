import SwiftUI

struct VideoWebPopover: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var isImporting = false
    @State private var failed = false
    @State private var importTask: Task<Void, Never>?
    let link: (URL) -> Void
    let importCopy: (URL) async -> Bool
    let allowsYouTube: Bool

    init(url: URL?, link: @escaping (URL) -> Void, importCopy: @escaping (URL) async -> Bool, allowsYouTube: Bool = true) {
        _address = State(initialValue: url?.absoluteString ?? "")
        self.link = link
        self.importCopy = importCopy
        self.allowsYouTube = allowsYouTube
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video on the Web").font(.headline)
            TextField("https://example.com/video.mp4", text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(linkVideo)
                .disabled(isImporting)
            Text(allowsYouTube ? "Use a direct video-file URL or a YouTube video link." : "Background videos require a direct video-file URL.")
                .font(.caption).foregroundStyle(.secondary)
            if failed {
                Text("Couldn’t import this video. Use a downloadable video file up to 100 MB.")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Import Copy", action: download).buttonStyle(.bordered)
                    .disabled(YouTubeVideo.isYouTubeAddress(address))
                if isImporting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Link", action: linkVideo).buttonStyle(.borderedProminent)
            }
            .disabled(!canLink || isImporting)
        }
        .padding()
        .onDisappear { importTask?.cancel() }
    }

    private func linkVideo() {
        guard canLink, !isImporting, let url = RemoteVideoImport.webURL(address) else { return }
        link(url)
        dismiss()
    }

    private func download() {
        guard !YouTubeVideo.isYouTubeAddress(address), !isImporting, let url = RemoteVideoImport.webURL(address) else { return }
        isImporting = true
        failed = false
        importTask = Task {
            let success = await importCopy(url)
            guard !Task.isCancelled else { return }
            isImporting = false
            if success { dismiss() } else { failed = true }
        }
    }
    private var canLink: Bool {
        guard RemoteVideoImport.webURL(address) != nil else { return false }
        return !YouTubeVideo.isYouTubeAddress(address) || (allowsYouTube && YouTubeVideo.id(from: address) != nil)
    }
}
