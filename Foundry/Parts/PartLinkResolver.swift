import Foundation

nonisolated enum PartLinkResolver {
    struct Result: Equatable, Sendable {
        let href: String
        let target: String
        let attributes: String
    }

    static func resolve(
        _ link: PartLink,
        pages: [Page],
        folders: [PageFolder],
        assets: [ProjectAsset],
        publicURL: String,
        absoluteURL: Bool
    ) -> Result {
        resolve(
            link,
            pages: pages,
            folders: folders,
            assets: assets,
            assetLibrary: nil,
            publicURL: publicURL,
            absoluteURL: absoluteURL
        )
    }

    static func resolve(
        _ link: PartLink,
        pages: [Page],
        folders: [PageFolder],
        assets: [ProjectAsset],
        assetLibrary: [ProjectAssetNode]?,
        publicURL: String,
        absoluteURL: Bool
    ) -> Result {
        let path: String
        switch link.destination {
        case .none: path = ""
        case .url(let value), .plainText(let value): path = value
        case .page(let id):
            path = pages.first(where: { $0.id == id }).map {
                StaticSiteRenderer.urlPath(for: $0, pages: pages, folders: folders)
            } ?? ""
        case .resource(let id):
            path = assets.first(where: { $0.id == id }).map {
                "/" + assetPath($0, folders: folders, assetLibrary: assetLibrary)
            } ?? ""
        }
        var href = path
        if absoluteURL, path.hasPrefix("/"), let base = normalizedPublicURL(publicURL) {
            href = base + path
        }
        let anchor = link.anchor.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if !anchor.isEmpty { href += "#" + anchor }
        var custom = link.attributes.compactMap { attribute -> String? in
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.matches(#"^[A-Za-z_:][A-Za-z0-9_.:-]*$"#) else { return nil }
            return "\(name)=\"\(escapeAttribute(attribute.value))\""
        }
        if link.opensInNewWindow,
           !link.attributes.contains(where: { $0.name.caseInsensitiveCompare("rel") == .orderedSame }) {
            custom.append("rel=\"noopener noreferrer\"")
        }
        return Result(
            href: href,
            target: link.opensInNewWindow ? "_blank" : "",
            attributes: custom.joined(separator: " ")
        )
    }

    private static func assetPath(
        _ asset: ProjectAsset,
        folders: [PageFolder],
        assetLibrary: [ProjectAssetNode]?
    ) -> String {
        let filename = (asset.filename as NSString).lastPathComponent
        let safeFilename = filename.isEmpty ? asset.storageFilename : filename
        switch asset.exportDirectory {
        case .root:
            return safeFilename
        case .folder(let folderID):
            var currentID: UUID? = folderID
            var slugs: [String] = []
            var visited = Set<UUID>()
            while let id = currentID,
                  visited.insert(id).inserted,
                  let folder = folders.first(where: { $0.id == id }) {
                slugs.insert(folder.slug, at: 0)
                currentID = folder.parentID
            }
            return (slugs + [safeFilename]).joined(separator: "/")
        case nil:
            return assetLibrary?.managedExportPath(for: asset) ?? asset.exportPath
        }
    }

    private static func normalizedPublicURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func escapeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private nonisolated extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
