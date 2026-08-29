import AppKit
import Foundation

@MainActor
enum FoundryPackInstaller {
    static func install(from sourceURL: URL) throws {
        let pack = try FoundryPackLoader.load(from: sourceURL)
        switch pack.type {
        case .component:
            _ = try ComponentPackageLoader.load(from: sourceURL)
        case .theme:
            _ = try ThemePackageLoader.load(from: sourceURL)
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
        FoundryPackCatalog.shared.reload()
    }
}

@MainActor
final class FoundryApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "foundrypack" {
            do {
                try FoundryPackInstaller.install(from: url)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Foundry Pack Could Not Be Installed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
