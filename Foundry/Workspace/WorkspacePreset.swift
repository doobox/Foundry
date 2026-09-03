import Foundation
import Observation

nonisolated struct WorkspacePreset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var layout: WorkspaceLayout

    init(id: UUID = UUID(), name: String, layout: WorkspaceLayout) {
        self.id = id
        self.name = name
        self.layout = layout
    }
}

@MainActor
@Observable
final class WorkspacePresetLibrary {
    private(set) var presets: [WorkspacePreset]

    init(presets: [WorkspacePreset] = WorkspacePresetStore.restored()) {
        self.presets = presets
    }

    func save(name: String, layout: WorkspaceLayout, replacing id: UUID? = nil) -> UUID {
        if let id, let index = presets.firstIndex(where: { $0.id == id }) {
            presets[index].name = name
            presets[index].layout = layout
            persist()
            return id
        }

        if let index = presets.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            presets[index].name = name
            presets[index].layout = layout
            let id = presets[index].id
            persist()
            return id
        }

        let preset = WorkspacePreset(name: name, layout: layout)
        presets.append(preset)
        persist()
        return preset.id
    }

    func delete(_ id: UUID) {
        presets.removeAll(where: { $0.id == id })
        persist()
    }

    private func persist() {
        WorkspacePresetStore.persist(presets)
    }
}

nonisolated enum WorkspacePresetStore {
    static func initialLayoutForNewDocument(from defaults: UserDefaults = .standard) -> WorkspaceLayout {
        let presets = restored(from: defaults)
        guard !presets.isEmpty else {
            var layout = WorkspaceLayout.standard
            layout.setDeveloperPanelVisible(
                defaults.bool(forKey: AppPreferenceKey.showsDeveloperPanel)
            )
            return layout
        }
        if let selectedID = WorkspaceSelectionStore.restored(from: defaults),
           let preset = presets.first(where: { $0.id == selectedID }) {
            return preset.layout
        }
        return WorkspaceLayout.restored(from: defaults)
    }

    static func restored(from defaults: UserDefaults = .standard) -> [WorkspacePreset] {
        guard let data = defaults.data(forKey: storageKey),
              let presets = try? JSONDecoder().decode([WorkspacePreset].self, from: data) else {
            return []
        }
        return presets.map { preset in
            var migrated = preset
            migrated.layout.addMissingUtilityPanels(
                includingDeveloperPanel: defaults.bool(forKey: AppPreferenceKey.showsDeveloperPanel)
            )
            return migrated
        }
    }

    static func persist(_ presets: [WorkspacePreset], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
        if let selectedID = WorkspaceSelectionStore.restored(from: defaults),
           !presets.contains(where: { $0.id == selectedID }) {
            WorkspaceSelectionStore.persist(nil, to: defaults)
        }
    }

    private static let storageKey = "foundry.workspace.presets.v1"
}

nonisolated enum WorkspaceSelectionStore {
    static func restored(from defaults: UserDefaults = .standard) -> UUID? {
        guard let value = defaults.string(forKey: storageKey) else { return nil }
        return UUID(uuidString: value)
    }

    static func persist(_ id: UUID?, to defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    private static let storageKey = "foundry.workspace.lastSelectedPresetID"
}
