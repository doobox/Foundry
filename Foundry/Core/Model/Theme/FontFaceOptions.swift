import Foundation

/// Metadata only: never registers fonts or creates a preview.
nonisolated struct FontFaceOptions {
    let faces: [FontFileMetadata]
    let verified: Bool
    let missing: Bool
    let selectedWeight: Int?
    let selectedStyle: String?

    init(reference: String?, theme: Theme, assets: ProjectAssetContents, selectedWeight: Int? = nil, selectedStyle: String? = nil) {
        self.selectedWeight = selectedWeight
        self.selectedStyle = selectedStyle
        let font: ThemeFontDefinition?
        switch reference {
        case "body": font = theme.typography.bodyFont
        case "heading": font = theme.typography.headingFont
        case "monospaced": font = theme.typography.monospacedFont
        default: font = theme.typography.customFonts.first { "custom:\($0.id.uuidString.lowercased())" == reference }?.font
        }
        if let font, case .bundled(let files) = font.source {
            faces = files.compactMap { $0.foundryAssetID.flatMap { assets[$0] }.flatMap(FontFileMetadata.read) }
                .filter { $0.family.compare(font.family, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            verified = true
            missing = faces.isEmpty
        } else if let font, case .remote = font.source, let configuration = font.googleConfiguration {
            faces = configuration.validIncluded.map {
                FontFileMetadata(family: font.family, face: $0.title, weight: $0.minimum, maximumWeight: $0.maximum, italic: $0.italic)
            }
            verified = true
            missing = faces.isEmpty
        } else {
            faces = []
            verified = false
            missing = reference != nil && font == nil
        }
    }

    var weights: [Int] {
        guard verified else { return Array(stride(from: 100, through: 900, by: 100)) }
        return Array(Set(weightFaces.flatMap { Array($0.weight...$0.maximumWeight) })).sorted()
    }

    private var weightFaces: [FontFileMetadata] {
        let matching = faces.filter { selectedStyle == nil || $0.cssStyle == selectedStyle }
        // If the old style is absent entirely, allow choosing a new weight first.
        return matching.isEmpty ? faces : matching
    }

    var variableWeight: Bool { weightFaces.contains { $0.maximumWeight > $0.weight } }

    var styles: [String] {
        guard verified else { return ["normal", "italic"] }
        let matching = faces.filter { selectedWeight == nil || ($0.weight...$0.maximumWeight).contains(selectedWeight!) }
        let candidates = matching.isEmpty ? faces : matching
        return ["normal", "italic"].filter { style in candidates.contains { $0.cssStyle == style } }
    }
}
