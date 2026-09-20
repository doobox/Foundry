import Foundation
import Testing
@testable import Foundry

struct FontFileMetadataTests {
    @Test func faceOptionsRespectUploadedWeightsAndStyles() throws {
        let contents = try ["Arial", "Arial Bold", "Arial Italic"].map { name in
            let bytes = try data(name)
            return ProjectAssetContent(
                asset: ProjectAsset(
                    filename: "\(name).ttf",
                    mediaType: "font/ttf",
                    byteCount: bytes.count,
                    contentDigest: FoundryDocumentSnapshot.digest(for: bytes)
                ),
                data: bytes
            )
        }
        var framework = Framework.standard
        framework.typography.bodyFont.family = "Arial"
        framework.typography.bodyFont.source = .bundled(files: contents.map { $0.asset.reference })
        let assets = ProjectAssetContents(Dictionary(uniqueKeysWithValues: contents.map { ($0.asset.id, $0) }))
        let normal = FontFaceOptions(reference: "body", framework: framework, assets: assets, selectedStyle: "normal")
        #expect(normal.verified)
        #expect(normal.weights == [400, 700])
        #expect(!normal.variableWeight)
        let italic = FontFaceOptions(reference: "body", framework: framework, assets: assets, selectedStyle: "italic")
        #expect(italic.weights == [400])
        let bold = FontFaceOptions(reference: "body", framework: framework, assets: assets, selectedWeight: 700)
        #expect(bold.styles == ["normal"])
        #expect(FontFaceOptions(reference: "custom:missing", framework: framework, assets: assets).missing)
        #expect(!FontFaceOptions(reference: "heading", framework: framework, assets: assets).verified)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Library/Fonts/SF-Pro.ttf") && FileManager.default.fileExists(atPath: "/Library/Fonts/SF-Pro-Italic.ttf")))
    func sfProVariableInstancesAreOneFamily() throws {
        let regular = try #require(FontFileMetadata.read(Data(contentsOf: URL(fileURLWithPath: "/Library/Fonts/SF-Pro.ttf"))))
        let italic = try #require(FontFileMetadata.read(Data(contentsOf: URL(fileURLWithPath: "/Library/Fonts/SF-Pro-Italic.ttf"))))
        #expect(regular.family == "SF Pro")
        #expect(regular.face == "Variable")
        #expect(regular.maximumWeight > regular.weight)
        #expect(!regular.italic)
        #expect(italic.italic)
        #expect(regular.belongsToSameFamily(as: italic))
    }

    @Test @MainActor func attachmentRejectsMixedFamiliesAndUpdatesFaceSettings() throws {
        let document = FoundryDocument()
        let editor = ProjectEditor(document: document, undoManager: nil)
        let ids = try ["Arial", "Arial Bold", "Georgia"].map { name in
            document.importAsset(data: try data(name), filename: "\(name).ttf", mediaType: "font/ttf", undoManager: nil)
        }
        let references = ids.map { "foundry-asset:\($0.uuidString)" }
        editor.setFrameworkFontResources(Array(references.prefix(2)), reference: .role(.body))
        let accepted = document.site.framework.typography.bodyFont
        #expect(accepted.family == "Arial")
        #expect(accepted.weights == [400, 700])
        editor.setFrameworkFontResources(references, reference: .role(.body))
        #expect(document.site.framework.typography.bodyFont == accepted)
        editor.setFrameworkFontResources([references[1]], reference: .role(.body))
        #expect(document.site.framework.typography.bodyFont.weights == [700])
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/\(name).ttf"))
    }

    @Test func readsFamilyAndFacesFromBytes() throws {
        let regular = try #require(FontFileMetadata.read(data("Arial")))
        let bold = try #require(FontFileMetadata.read(data("Arial Bold")))
        let italic = try #require(FontFileMetadata.read(data("Arial Italic")))
        let other = try #require(FontFileMetadata.read(data("Georgia")))
        #expect(regular.family == "Arial")
        #expect(regular.weight == 400)
        #expect(bold.weight == 700)
        #expect(italic.italic)
        #expect(regular.belongsToSameFamily(as: bold))
        #expect(regular.belongsToSameFamily(as: italic))
        #expect(!regular.belongsToSameFamily(as: other))
        #expect(FontFileMetadata.read(Data([1, 2, 3])) == nil)
    }

    @Test func rendererUsesFacesAndExcludesUnrelatedFamilies() throws {
        let names = ["Arial", "Arial Bold", "Arial Italic", "Georgia"]
        let contents = try names.enumerated().map { index, name in
            let bytes = try data(name)
            return ProjectAssetContent(
                asset: ProjectAsset(
                    filename: "face-\(index).ttf",
                    mediaType: "font/ttf",
                    byteCount: bytes.count,
                    contentDigest: FoundryDocumentSnapshot.digest(for: bytes)
                ),
                data: bytes
            )
        }
        var framework = Framework.standard
        framework.typography.bodyFont.family = "Project Font"
        framework.typography.bodyFont.source = .bundled(files: contents.map { $0.asset.reference })
        let css = framework.fontSourceCSS(assets: ProjectAssetContents(Dictionary(uniqueKeysWithValues: contents.map { ($0.asset.id, $0) })), destination: .export)
        #expect(css.contains("font-style:normal;font-weight:400;"))
        #expect(css.contains("font-style:normal;font-weight:700;"))
        #expect(css.contains("font-style:italic;font-weight:400;"))
        #expect(!css.contains(contents[3].asset.storageFilename))
    }
}
