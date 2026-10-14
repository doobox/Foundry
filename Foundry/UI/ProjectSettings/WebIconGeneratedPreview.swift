import SwiftUI

struct WebIconGeneratedPreview: View {
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents

    private let columns = [
        GridItem(.adaptive(minimum: 54, maximum: 54), spacing: 14)
    ]

    var body: some View {
        let generatedAssets = WebIconGenerator.generatedFilenames.compactMap { filename in
            assets.first { $0.filename == filename }
        }

        if !generatedAssets.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(generatedAssets) { asset in
                    if let data = assetContents[asset.id]?.data,
                       let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: previewSide(for: asset.filename),
                                height: previewSide(for: asset.filename)
                            )
                            .frame(width: 54, height: 54)
                            .accessibilityLabel("Generated web icon \(asset.filename)")
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: .rect(cornerRadius: 10))
            .allowsHitTesting(false)
        }
    }

    private func previewSide(for filename: String) -> Double {
        guard filename != "favicon.ico",
              let dimensions = filename.split(separator: "-").last?.split(separator: ".").first,
              let pixels = Double(dimensions.split(separator: "x").first ?? "") else {
            return 40
        }
        return min(48, max(18, pixels.squareRoot() * 3.5))
    }
}
