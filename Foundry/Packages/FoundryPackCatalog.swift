import Foundation
import Observation

@MainActor
@Observable
final class FoundryPackCatalog {
    static let shared = FoundryPackCatalog()

    private(set) var packs: [String: FoundryPack] = [:]
    private(set) var themes: [String: LoadedThemePackage] = [:]
    private(set) var diagnostics: [URL: String] = [:]

    private init() {
        reload()
    }

    func reload() {
        packs = [:]
        themes = [:]
        diagnostics = [:]

        for url in packURLs() {
            do {
                let pack = try FoundryPackLoader.load(from: url)
                packs[pack.manifest.identifier] = pack
                for themeURL in pack.themeURLs {
                    let theme = try ThemePackageLoader.load(from: themeURL)
                    themes[theme.manifest.identifier] = theme
                }
            } catch {
                diagnostics[url] = error.localizedDescription
            }
        }
    }

    private func packURLs() -> [URL] {
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
        }
        if let installedURL = try? FoundryPackLoader.installedPacksURL() {
            roots.append(installedURL)
        }
        return roots.flatMap { root -> [URL] in
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            return enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "foundrypack" }
        }
    }
}
