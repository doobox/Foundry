import AppKit
import Foundation

@MainActor
enum FoundryPackInstaller {
    static func install(from sourceURL: URL) throws {
        let packURLs = FoundryPackLoader.packURLs(in: sourceURL, includingRoot: true)
        guard !packURLs.isEmpty else { throw FoundryPackLoadingError.wrongExtension }
        for url in packURLs {
            let pack = try FoundryPackLoader.load(from: url)
            switch pack.type {
            case .component:
                _ = try ComponentPackageLoader.load(from: url)
            case .collection:
                break
            }
        }

        let destination = try FoundryPackLoader.installedPacksURL()
            .appending(path: sourceURL.lastPathComponent, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if destination.standardizedFileURL != sourceURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
        }

        ComponentPackageCatalog.shared.reloadInstalledPacks()
    }
}

@MainActor
final class FoundryApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if ThemeBundleStore.isThemeURL(url) {
                do {
                    try ThemeLibrary.shared.install(from: url)
                } catch {
                    presentInstallError(error, title: "Foundry Theme Could Not Be Installed")
                }
                continue
            }
            guard FoundryPackLoader.isPackURL(url) else { continue }
            if url.pathExtension.lowercased() == "foundrydevpack" {
                ComponentPackageCatalog.shared.openDevelopmentPack(at: url)
                continue
            }
            do {
                try FoundryPackInstaller.install(from: url)
            } catch {
                presentInstallError(error, title: "Foundry Pack Could Not Be Installed")
            }
        }
    }

    private func presentInstallError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
