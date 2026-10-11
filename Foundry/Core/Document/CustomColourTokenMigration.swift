import Foundation

/// Converts persisted token keys and references before project decoding.
/// The parser and renderers support only the current, single-prefix spelling.
nonisolated enum CustomColourTokenMigration {
    static func migrate(_ data: Data) -> Data {
        guard data.range(of: Data("custom-custom-".utf8)) != nil,
              let json = String(data: data, encoding: .utf8) else { return data }
        // Exact token-shaped identifiers only, including keys, rich text and
        // authored CSS references. Unrelated prose and other names are untouched.
        let migrated = json.replacingOccurrences(
            of: #"custom-custom-((?:[0-9a-f]{2})+-(?:bg-(?:body|[1-4])|fg-(?:body|[1-4])|border-(?:body|subtle|muted|emphasized)|link-(?:color|hover-color)))(?![A-Za-z0-9_-])"#,
            with: "custom-$1", options: .regularExpression
        )
        return Data(migrated.utf8)
    }
}
