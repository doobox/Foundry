import Foundation

/// A view over a project's asset bytes. Metadata lookups never touch the
/// byte store; only the subscript resolves bytes, through `AssetByteStore`'s
/// bounded cache.
nonisolated struct ProjectAssetContents: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    private enum Source: Sendable {
        case inline([UUID: ProjectAssetContent])
        case store(AssetByteStore, assetsByID: [UUID: ProjectAsset], revision: UInt64)
    }
    private let source: Source

    init(dictionaryLiteral elements: (UUID, ProjectAssetContent)...) {
        source = .inline(Dictionary(uniqueKeysWithValues: elements))
    }

    init(_ contents: [UUID: ProjectAssetContent]) {
        source = .inline(contents)
    }

    init(store: AssetByteStore, assetsByID: [UUID: ProjectAsset], revision: UInt64) {
        source = .store(store, assetsByID: assetsByID, revision: revision)
    }

    /// Byte-free — safe to call on every render/keystroke.
    func asset(_ id: UUID) -> ProjectAsset? {
        switch source {
        case .inline(let contents): contents[id]?.asset
        case .store(_, let assetsByID, _): assetsByID[id]
        }
    }

    /// Byte-free — safe to call on every render/keystroke.
    func hasContent(_ id: UUID) -> Bool {
        switch source {
        case .inline(let contents): contents[id] != nil
        case .store(let store, let assetsByID, _):
            assetsByID[id].map { store.hasContent(for: $0) } ?? false
        }
    }

    /// Byte-free — safe to call on every render/keystroke.
    func digest(_ id: UUID) -> String? {
        switch source {
        case .inline(let contents): contents[id]?.digest
        case .store(_, let assetsByID, _): assetsByID[id]?.contentDigest
        }
    }

    /// Byte-resolving — may read from disk through the shared cache.
    subscript(id: UUID) -> ProjectAssetContent? {
        switch source {
        case .inline(let contents):
            return contents[id]
        case .store(let store, let assetsByID, _):
            guard let asset = assetsByID[id], let data = store.resolve(asset) else { return nil }
            return ProjectAssetContent(asset: asset, data: data)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.source, rhs.source) {
        case (.inline(let lhsContents), .inline(let rhsContents)):
            lhsContents == rhsContents
        case (.store(let lhsStore, _, let lhsRevision), .store(let rhsStore, _, let rhsRevision)):
            lhsStore === rhsStore && lhsRevision == rhsRevision
        default:
            false
        }
    }
}
