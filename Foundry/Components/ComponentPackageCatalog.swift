import Foundation
import Observation

@MainActor
@Observable
final class ComponentPackageCatalog {
    static let shared = ComponentPackageCatalog()

    private(set) var revision = 0
    private(set) var diagnostics: [URL: [ComponentPackageDiagnostic]] = [:]
    private(set) var packages: [String: LoadedComponentPackage] = [:]

    private init() {
        loadBundledComponents()
        loadInstalledComponents()
    }

    private func loadBundledComponents() {
        guard let containerURL = Bundle.main.url(
            forResource: "BuiltInComponents",
            withExtension: "foundrypack"
        ) else { return }
        for url in FoundryPackLoader.packURLs(in: containerURL, includingRoot: true) {
            guard let pack = try? FoundryPackLoader.load(from: url), pack.type == .component else { continue }
            reload(url)
        }
    }

    private func loadInstalledComponents() {
        guard let root = try? FoundryPackLoader.installedPacksURL() else { return }
        for url in FoundryPackLoader.packURLs(in: root) {
            guard let pack = try? FoundryPackLoader.load(from: url), pack.type == .component else { continue }
            reload(url)
        }
    }

    private func reload(_ url: URL) {
        do {
            let package = try ComponentPackageLoader.load(from: url)
            if let previous = packages[package.manifest.identifier], previous.rootURL != url {
                diagnostics[url] = [
                    .init(
                        severity: .error,
                        location: "Info.plist:CFBundleIdentifier",
                        message: "Another installed package already uses '\(package.manifest.identifier)'."
                    )
                ]
                return
            }
            packages[package.manifest.identifier] = package
            diagnostics[url] = ComponentPackageValidator.validate(
                package.manifest,
                rootURL: package.resourceRootURL
            )
            ComponentRegistry.register(package)
            revision += 1
        } catch ComponentPackageLoadingError.invalid(let packageDiagnostics) {
            diagnostics[url] = packageDiagnostics
            revision += 1
        } catch {
            diagnostics[url] = [
                .init(severity: .error, location: url.lastPathComponent, message: error.localizedDescription)
            ]
            revision += 1
        }
    }

    func reloadInstalledPacks() {
        loadInstalledComponents()
    }
}
