import Darwin
import Foundation
import Testing
@testable import Foundry

private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

private func assetsByID(from snapshot: FoundryDocumentSnapshot) -> [UUID: ProjectAsset] {
    Dictionary(uniqueKeysWithValues: snapshot.site.assets.map { ($0.id, $0) })
}

struct ProjectAssetStressTests {
    @Test
    func externalLargeProjectLoadTime() throws {
        guard let selectedPath = ProcessInfo.processInfo.environment["FOUNDRY_ASSET_STRESS_PROJECT"] else {
            print("Large-project benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a current .foundry package.")
            return
        }
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
        let expectedAssetCount = snapshot.site.assets.count
        let totalElapsed = wrapperStart.duration(to: clock.now)
        let residentAfterOpen = residentMemoryBytes()

        var resolvedBytes: Int64 = 0
        for asset in snapshot.site.assets {
            if let data = snapshot.byteStore.resolve(asset) {
                resolvedBytes += Int64(data.count)
            }
        }
        let residentAfterResolvingAll = residentMemoryBytes()

        print("""
        Loaded external project asset stress fixture:
          path: \(projectURL.path)
          declared assets: \(expectedAssetCount)
          resolved asset bytes: \(resolvedBytes)
          file-wrapper creation: \(wrapperElapsed)
          document decoding (metadata only, no asset bytes touched): \(documentElapsed)
          measured open total: \(totalElapsed)
          resident memory right after open: \(residentAfterOpen)
          resident memory after resolving every asset once: \(residentAfterResolvingAll)
        """)

        #expect(expectedAssetCount > 0)
        #expect(resolvedBytes > 0)
        #expect(totalElapsed < .seconds(10), "The external asset stress project should open within 10 seconds.")
        // Opening must not have already faulted in every asset's bytes: the
        // library's total size should dwarf what a metadata-only open uses.
        #expect(Int64(residentAfterResolvingAll) - Int64(residentAfterOpen) < resolvedBytes)
    }

    @Test
    func externalLargeProjectStaticPreviewPreparationTime() async throws {
        guard let selectedPath = ProcessInfo.processInfo.environment["FOUNDRY_ASSET_STRESS_PROJECT"] else {
            print("Large-project preview benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a current .foundry package.")
            return
        }
        let projectURL = URL(filePath: selectedPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            print("Large-project preview benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a .foundry package.")
            return
        }

        let wrapper = try FileWrapper(url: projectURL, options: [])
        let snapshot = try FoundryDocument.decodeSnapshot(from: wrapper)
        let assets = ProjectAssetContents(
            store: snapshot.byteStore,
            assetsByID: assetsByID(from: snapshot),
            revision: snapshot.assetRevision
        )
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

    @Test
    func externalLargeProjectRepeatedPHPPreviewTime() async throws {
        guard let selectedPath = ProcessInfo.processInfo.environment["FOUNDRY_ASSET_STRESS_PROJECT"] else {
            print("Large-project PHP preview benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a current .foundry package.")
            return
        }
        let projectURL = URL(filePath: selectedPath, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            print("Large-project PHP preview benchmark skipped. Set FOUNDRY_ASSET_STRESS_PROJECT to a .foundry package.")
            return
        }

        let wrapper = try FileWrapper(url: projectURL, options: [])
        let snapshot = try FoundryDocument.decodeSnapshot(from: wrapper)
        let assets = ProjectAssetContents(
            store: snapshot.byteStore,
            assetsByID: assetsByID(from: snapshot),
            revision: snapshot.assetRevision
        )
        let staticBundle = StaticSiteRenderer(environment: .preview).render(site: snapshot.site, assets: assets)
        var convertedPage = false
        let phpFiles = staticBundle.files.map { file -> SiteExportFile in
            guard !convertedPage, file.path.hasSuffix(".html") else { return file }
            convertedPage = true
            return SiteExportFile(
                path: String(file.path.dropLast(4)) + "php",
                data: file.data,
                contentFingerprint: file.contentFingerprint
            )
        }
        let phpBundle = SiteExportBundle(files: phpFiles, errors: staticBundle.errors)
        #expect(PreviewServer.requiresPHPDocumentRoot(for: phpBundle))

        let clock = ContinuousClock()
        let firstStart = clock.now
        _ = try await PreviewServer.shared.publish(phpBundle, notifyingClients: false)
        let firstElapsed = firstStart.duration(to: clock.now)
        let repeatedStart = clock.now
        _ = try await PreviewServer.shared.publish(phpBundle, notifyingClients: false)
        let repeatedElapsed = repeatedStart.duration(to: clock.now)

        print("""
        Prepared repeated external project PHP preview:
          path: \(projectURL.path)
          files: \(phpBundle.files.count)
          first staging: \(firstElapsed)
          unchanged repeat: \(repeatedElapsed)
        """)

        #expect(repeatedElapsed < .seconds(1), "An unchanged PHP preview should reuse its staged files.")
    }
}
