import Foundation

/// A copy-and-go snippet kept beside a Controls showcase part's templates.
/// Developers paste these into their own pack to start from a working
/// declaration rather than the reference pages.
nonisolated struct PartShowcaseSnippet: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let filename: String
    let text: String

    /// The files a showcase part may provide, in display order.
    static let all: [PartShowcaseSnippet] = [
        .init(id: "json", title: "manifest.json", filename: "snippet.json", text: ""),
        .init(id: "html", title: "part.html", filename: "snippet.html", text: ""),
        .init(id: "css", title: "part.css", filename: "snippet.css", text: "")
    ]

    func with(text: String) -> PartShowcaseSnippet {
        .init(id: id, title: title, filename: filename, text: text.trimmingCharacters(in: .newlines))
    }
}
