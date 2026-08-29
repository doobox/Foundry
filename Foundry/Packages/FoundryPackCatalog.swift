import Foundation
import Observation

@MainActor
@Observable
final class FoundryPackCatalog {
    static let shared = FoundryPackCatalog()

    private(set) var packs: [String: FoundryPack] = [:]
    private(set) var themes: [String: LoadedThemePackage] = [:]
    private(set) var diagnostics: [URL: String] = [:]
    private var developmentRoots: Set<URL> = []

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
                packs[pack.identifier] = pack
                if pack.type == .theme {
                    let theme = try ThemePackageLoader.load(from: url)
                    themes[theme.manifest.identifier] = theme
                }
            } catch {
                diagnostics[url] = error.localizedDescription
            }
        }
    }

    func openDevelopmentPack(at rootURL: URL) {
        developmentRoots.insert(rootURL.standardizedFileURL)
        reload()
    }

    private func packURLs() -> [URL] {
        var roots: [URL] = Bundle.main.resourceURL.map { [$0] } ?? []
        if let installedURL = try? FoundryPackLoader.installedPacksURL() {
            roots.append(installedURL)
        }
        roots.append(contentsOf: developmentRoots)
        return roots.flatMap { root -> [URL] in
            FoundryPackLoader.packURLs(in: root)
        }
    }
}
