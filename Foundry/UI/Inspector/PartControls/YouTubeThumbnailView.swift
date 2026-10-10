import SwiftUI

struct YouTubeThumbnailView: View {
    let videoID: String
    @State private var thumbnail: NSImage?

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Label("YouTube", systemImage: "play.rectangle")
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .accessibilityLabel("YouTube video thumbnail")
            .task(id: videoID) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        for address in YouTubeVideo.posters(for: videoID) {
            guard !Task.isCancelled, let url = URL(string: address) else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
                guard !Task.isCancelled else { return }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let image = NSImage(data: data), image.size.width > 120 else { continue }
                thumbnail = image
                return
            } catch {
                if Task.isCancelled { return }
            }
        }
    }
}
