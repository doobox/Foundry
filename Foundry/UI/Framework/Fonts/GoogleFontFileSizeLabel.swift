import SwiftUI

struct GoogleFontFileSizeLabel: View {
    let stylesheetURL: URL?
    @State private var result: String = "Measuring…"

    var body: some View {
        Text("Font files: \(result)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Total bytes of unique font files Google returns for the included styles and all character subsets, using a modern browser profile. Visitors may download less. Measuring downloads these files temporarily; Foundry does not retain them.")
            .task(id: stylesheetURL) {
                result = "Measuring…"
                guard let stylesheetURL else { result = "Unavailable"; return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let bytes = try await GoogleFontFileSize.measure(stylesheetURL: stylesheetURL)
                    try Task.checkCancellation()
                    result = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                } catch {
                    guard !Task.isCancelled else { return }
                    result = "Unavailable"
                }
            }
    }
}
