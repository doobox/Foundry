import Foundation

/// Where Foundry keeps its shared, cross-project library content: installed
/// packs containing parts, saved templates and saved frameworks. Defaults to Application
/// Support; users can point it at a synced folder (iCloud Drive, Dropbox) so
/// every Mac shares one library. Caches and development packs never live here.
nonisolated enum FoundryLibraryLocation {
    static let preferenceKey = "library.rootPath"

    static var customPath: String? {
        get {
            let value = UserDefaults.standard.string(forKey: preferenceKey)
            return value?.isEmpty == false ? value : nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferenceKey)
        }
    }

    static func rootURL(fileManager: FileManager = .default) throws -> URL {
        let url: URL
        if let customPath {
            url = URL(filePath: customPath, directoryHint: .isDirectory)
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            url = applicationSupport.appending(path: "Foundry", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directoryURL(named name: String, fileManager: FileManager = .default) throws -> URL {
        let url = try rootURL(fileManager: fileManager)
            .appending(path: name, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let contentDirectoryNames = ["Packs"]

    /// Where the library root should live for a folder the user chose: a
    /// `Foundry` folder inside it, keeping their chosen location tidy — unless
    /// they picked an existing Foundry library (by name or contents), which is
    /// used as-is so selecting the same library from another Mac never nests.
    static func resolvedRoot(forChosen url: URL, fileManager: FileManager = .default) -> URL {
        if url.lastPathComponent.caseInsensitiveCompare("Foundry") == .orderedSame {
            return url
        }
        let containsLibraryContent = contentDirectoryNames.contains { name in
            var isDirectory: ObjCBool = false
            let path = url.appending(path: name, directoryHint: .isDirectory).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        if containsLibraryContent { return url }
        return url.appending(path: "Foundry", directoryHint: .isDirectory)
    }

    /// Copies library content into a new root when the location changes, so
    /// packs and templates travel with the setting. Non-destructive: the old
    /// location keeps its files and nothing existing at the destination is
    /// overwritten, which also makes switching between synced Macs safe.
    static func migrateContent(from oldRoot: URL, to newRoot: URL, fileManager: FileManager = .default) {
        guard oldRoot.standardizedFileURL != newRoot.standardizedFileURL else { return }
        for name in contentDirectoryNames {
            let source = oldRoot.appending(path: name, directoryHint: .isDirectory)
            let destination = newRoot.appending(path: name, directoryHint: .isDirectory)
            guard let items = try? fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ), !items.isEmpty else { continue }
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in items {
                let target = destination.appending(path: item.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                try? fileManager.copyItem(at: item, to: target)
            }
        }
    }
}
