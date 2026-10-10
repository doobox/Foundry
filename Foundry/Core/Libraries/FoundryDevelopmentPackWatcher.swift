import Foundation
import Darwin

nonisolated final class FoundryDevelopmentPackWatcher: @unchecked Sendable {
    private let rootURL: URL
    private let queue = DispatchQueue(label: "uk.co.garysimpson.foundry.devpack-watcher")
    private let onChange: @Sendable () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingChange: DispatchWorkItem?

    init(rootURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.rootURL = rootURL.standardizedFileURL
        self.onChange = onChange
        queue.async { [weak self] in self?.rebuildSources() }
    }

    deinit {
        pendingChange?.cancel()
        sources.forEach { $0.cancel() }
    }

    private func rebuildSources() {
        sources.forEach { $0.cancel() }
        sources = Self.watchedURLs(in: rootURL).compactMap(makeSource)
    }

    static func watchedURLs(in rootURL: URL) -> [URL] {
        var urls = [rootURL]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return urls }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "foundrypack" {
                enumerator.skipDescendants()
                continue
            }
            urls.append(url)
        }
        return urls
    }

    private func makeSource(for url: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            onChange()
            rebuildSources()
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }
}
