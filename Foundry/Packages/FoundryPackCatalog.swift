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

    private func packURLs() -> [URL] {
        var roots: [URL] = Bundle.main.resourceURL.map { [$0] } ?? []
        if let builtIns = Bundle.main.url(forResource: "BuiltInComponents", withExtension: "bundle") {
            roots.append(builtIns)
        }
        if let installedURL = try? FoundryPackLoader.installedPacksURL() {
            roots.append(installedURL)
        }
        return roots.flatMap { root -> [URL] in
            FoundryPackLoader.packURLs(in: root)
        }
    }
}
