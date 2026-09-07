import Foundation
import Testing
@testable import Foundry

struct ProjectAssetStressTests {
    @Test
    func externalLargeProjectLoadTime() throws {
        let environmentPath = ProcessInfo.processInfo.environment["FOUNDRY_ASSET_STRESS_PROJECT"]
        let defaultStressPath = "/Users/garysimpson/Desktop/Foundry Asset Stress 10x.foundry"
        let fallbackPath = "/Users/garysimpson/Desktop/Untitled 2.foundry"
        let selectedPath = environmentPath
            ?? (FileManager.default.fileExists(atPath: defaultStressPath) ? defaultStressPath : fallbackPath)
        let projectURL = URL(filePath: selectedPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            print("Large-project benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a .foundry package.")
            return
        }

        let clock = ContinuousClock()
        let wrapperStart = clock.now
        let wrapper = try FileWrapper(url: projectURL, options: [])
        let wrapperElapsed = wrapperStart.duration(to: clock.now)

        let documentStart = clock.now
        let snapshot = try FoundryDocument.decodeSnapshot(from: wrapper)
        let documentElapsed = documentStart.duration(to: clock.now)

        let totalAssetBytes = snapshot.assetData.values.reduce(into: Int64(0)) { total, data in
            total += Int64(data.count)
        }
        let expectedAssetCount = snapshot.site.assets.count
        let loadedAssetCount = snapshot.assetData.count
        let totalElapsed = wrapperStart.duration(to: clock.now)

        print("""
        Loaded external project asset stress fixture:
          path: \(projectURL.path)
          declared assets: \(expectedAssetCount)
          loaded assets: \(loadedAssetCount)
          loaded asset bytes: \(totalAssetBytes)
          file-wrapper creation: \(wrapperElapsed)
          document decoding, metadata hydration and hashing: \(documentElapsed)
          measured total: \(totalElapsed)
        """)

        #expect(loadedAssetCount == expectedAssetCount)
        #expect(totalAssetBytes > 0)
        #expect(totalElapsed < .seconds(10), "The external asset stress project should open within 10 seconds.")
    }

    @Test
    func externalLargeProjectStaticPreviewPreparationTime() async throws {
        let environmentPath = ProcessInfo.processInfo.environment["FOUNDRY_ASSET_STRESS_PROJECT"]
        let defaultStressPath = "/Users/garysimpson/Desktop/Foundry Asset Stress 10x.foundry"
        let fallbackPath = "/Users/garysimpson/Desktop/Untitled 2.foundry"
        let selectedPath = environmentPath
            ?? (FileManager.default.fileExists(atPath: defaultStressPath) ? defaultStressPath : fallbackPath)
        let projectURL = URL(filePath: selectedPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            print("Large-project preview benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a .foundry package.")
            return
        }

        let wrapper = try FileWrapper(url: projectURL, options: [])
        let snapshot = try FoundryDocument.decodeSnapshot(from: wrapper)
        let assets = Dictionary(uniqueKeysWithValues: snapshot.site.assets.compactMap { asset in
            snapshot.assetData[asset.id].map { (asset.id, ProjectAssetContent(asset: asset, data: $0)) }
        })
        let clock = ContinuousClock()
        let start = clock.now
        let bundle = await Task.detached(priority: .userInitiated) {
            StaticSiteRenderer(environment: .preview).render(site: snapshot.site, assets: assets)
        }.value
        let renderElapsed = start.duration(to: clock.now)

        #expect(!PreviewServer.requiresPHPDocumentRoot(for: bundle))
        _ = try await PreviewServer.shared.publish(bundle, notifyingClients: false)
        let totalElapsed = start.duration(to: clock.now)

        print("""
        Prepared external project static preview:
          path: \(projectURL.path)
          files: \(bundle.files.count)
          render: \(renderElapsed)
          render and publish: \(totalElapsed)
        """)

        #expect(totalElapsed < .seconds(10), "The static stress-project preview should prepare within 10 seconds.")
    }
}
