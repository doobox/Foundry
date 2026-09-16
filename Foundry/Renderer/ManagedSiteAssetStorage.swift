import Foundation

nonisolated enum SiteLogoStorage {
    static let exportDirectory = "assets/site-logo"

    static func exportPath(for asset: ProjectAsset) -> String {
        let rawExtension = (asset.filename as NSString).pathExtension.lowercased()
        let safeExtension = rawExtension
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return exportDirectory + "/site-logo." + (safeExtension.isEmpty ? "bin" : safeExtension)
    }
}

nonisolated enum ManagedSiteAssetStorage {
    static func isManagedExportPath(_ path: String) -> Bool {
        WebIconGenerator.isManagedExportPath(path)
            || path == SiteLogoStorage.exportDirectory
            || path.hasPrefix(SiteLogoStorage.exportDirectory + "/")
    }
}
