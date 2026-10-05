import Foundation

nonisolated enum YouTubeVideo {
    static func id(from source: String) -> String? {
        guard let url = URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        var id: String?
        if ["youtu.be", "www.youtu.be"].contains(host), parts.count == 1 { id = parts[0] }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if url.path == "/watch" { id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value }
            else if parts.count == 2, ["shorts", "live", "embed"].contains(parts[0]) { id = parts[1] }
        } else if ["youtube-nocookie.com", "www.youtube-nocookie.com"].contains(host), parts.count == 2, parts[0] == "embed" { id = parts[1] }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        return id
    }
    static func isYouTubeAddress(_ source: String) -> Bool {
        guard let host = URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else { return false }
        return ["youtube.com", "youtu.be", "youtube-nocookie.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func posters(for id: String) -> [String] {
        ["maxresdefault", "sddefault", "hqdefault", "mqdefault"].map { "https://i.ytimg.com/vi/\(id)/\($0).jpg" }
    }
    static func poster(for id: String) -> String { posters(for: id)[0] }
    static func embed(for id: String, controls: Bool, loops: Bool, start: Double) -> String {
        var source = "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&controls=\(controls ? 1 : 0)"
        if loops { source += "&loop=1&playlist=\(id)" }
        if start.isFinite, start > 0 { source += "&start=\(Int(min(start, 86400)))" }
        return source
    }
}
