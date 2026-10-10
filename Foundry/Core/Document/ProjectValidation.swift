import Foundation

nonisolated enum ProjectValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchema(found: Int, supported: Int)
    case missingPages
    case duplicatePageIdentifier
    case duplicateSlug(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let found, let supported):
            "This project uses schema \(found), but this version supports schema \(supported)."
        case .missingPages:
            "A Foundry project must contain at least one page."
        case .duplicatePageIdentifier:
            "The project contains duplicate page identifiers."
        case .duplicateSlug(let slug):
            "More than one page uses the slug “\(slug)”."
        }
    }
}

nonisolated extension Site {
    func validate() throws {
        guard schemaVersion <= Site.currentSchemaVersion else {
            throw ProjectValidationError.unsupportedSchema(
                found: schemaVersion,
                supported: Site.currentSchemaVersion
            )
        }
        guard !pages.isEmpty else {
            throw ProjectValidationError.missingPages
        }

        var pageIDs = Set<UUID>()
        var slugs = Set<String>()
        for page in pages {
            guard pageIDs.insert(page.id).inserted else {
                throw ProjectValidationError.duplicatePageIdentifier
            }
            guard slugs.insert(page.slug).inserted else {
                throw ProjectValidationError.duplicateSlug(page.slug)
            }
        }
    }
}
