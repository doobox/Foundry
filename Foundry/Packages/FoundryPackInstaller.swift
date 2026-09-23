import AppKit
import Foundation

@MainActor
enum FoundryPackInstaller {
    static func install(from sourceURL: URL, reloadCatalog: Bool = true) throws {
        try installFiles(from: sourceURL)
        if reloadCatalog {
            PartPackageCatalog.shared.reloadInstalledPacks()
        }
    }

    nonisolated static func installFiles(from sourceURL: URL) throws {
        let pack = try FoundryPackLoader.load(from: sourceURL)
        if let invalid = pack.invalidItemPaths.first {
            throw FoundryPackLoadingError.invalidItem(invalid)
        }
        for url in pack.partURLs {
            _ = try PartPackageLoader.load(from: url)
        }
        for url in pack.frameworkURLs {
            _ = try FrameworkBundleStore.load(from: url)
        }
        for url in pack.templateURLs where ReusablePartLibrary.entry(at: url) == nil {
            throw FoundryPackLoadingError.invalidItem("Templates/\(url.lastPathComponent)")
        }

        let destination = try FoundryPackLoader.installedPacksURL()
            .appending(path: sourceURL.lastPathComponent, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        if destination.standardizedFileURL != sourceURL.standardizedFileURL {
            let staging = destination.deletingLastPathComponent().appending(
                path: ".\(destination.lastPathComponent).staging-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            let backup = destination.deletingLastPathComponent().appending(
                path: ".\(destination.lastPathComponent).backup-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fileManager.copyItem(at: sourceURL, to: staging)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.moveItem(at: destination, to: backup)
                }
                try fileManager.moveItem(at: staging, to: destination)
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.removeItem(at: backup)
                }
            } catch {
                if fileManager.fileExists(atPath: staging.path) {
                    try? fileManager.removeItem(at: staging)
                }
                if !fileManager.fileExists(atPath: destination.path),
                   fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }
        }

    }
}

@MainActor
final class FoundryApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard FoundryPackLoader.isPackURL(url) else { continue }
            if url.pathExtension.lowercased() == "foundrydevpack" {
                PartPackageCatalog.shared.openDevelopmentPack(at: url)
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
