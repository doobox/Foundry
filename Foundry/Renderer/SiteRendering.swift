import Foundation

nonisolated struct SiteExportFile: Equatable, Sendable {
    let path: String
    let data: Data

    init(path: String, contents: String) { self.path = path; data = Data(contents.utf8) }
    init(path: String, data: Data) { self.path = path; self.data = data }
    var contents: String { String(decoding: data, as: UTF8.self) }
}

nonisolated struct SiteExportBundle: Equatable, Sendable {
    let files: [SiteExportFile]
    let errors: [String]

    init(files: [SiteExportFile], errors: [String] = []) {
        self.files = files
        self.errors = errors
    }

    func file(at path: String) -> SiteExportFile? {
        files.first(where: { $0.path == path })
    }

    func validate() throws {
        if !errors.isEmpty { throw SiteExportBundleError.invalid(errors) }
    }
}

nonisolated enum SiteExportBundleError: LocalizedError, Equatable {
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .invalid(let errors):
            errors.joined(separator: "\n")
        }
    }
}

nonisolated protocol SiteRendering: Sendable {
    func render(site: Site, assets: [UUID: ProjectAssetContent]) -> SiteExportBundle
}
