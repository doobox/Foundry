import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let foundryWorkspacePanel = UTType(exportedAs: "uk.co.garysimpson.foundry.workspace-panel")
}

struct WorkspacePanelDragPayload: Codable, Transferable {
    let panel: WorkspacePanel

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .foundryWorkspacePanel)
    }
}

nonisolated enum WorkspacePanel: String, Codable, CaseIterable, Identifiable, Sendable {
    case pages
    case components
    case reusableComponents
    case globalComponents
    case structure
    case assets
    case canvas
    case inspector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pages: "Pages"
        case .components: "Components"
        case .reusableComponents: "Reusable Components"
        case .globalComponents: "Global Components"
        case .structure: "Structure"
        case .assets: "Assets"
        case .canvas: "Canvas"
        case .inspector: "Inspector"
        }
    }

    var systemImage: String {
        switch self {
        case .pages: "doc.on.doc"
        case .components: "square.grid.2x2"
        case .reusableComponents: "square.stack.3d.up"
        case .globalComponents: "globe"
        case .structure: "list.bullet.indent"
        case .assets: "photo.on.rectangle.angled"
        case .canvas: "macwindow"
        case .inspector: "slider.horizontal.3"
        }
    }
}

nonisolated struct WorkspaceColumn: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var panels: [WorkspacePanel]
    var selectedPanel: WorkspacePanel
    var preferredWidth: Double?

    init(
        id: UUID = UUID(),
        panels: [WorkspacePanel],
        selectedPanel: WorkspacePanel? = nil,
        preferredWidth: Double? = nil
    ) {
        self.id = id
        self.panels = panels
        self.selectedPanel = selectedPanel ?? panels.first ?? .canvas
        self.preferredWidth = preferredWidth
    }
}

nonisolated struct WorkspaceWindowFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let initial = WorkspaceWindowFrame(x: 180, y: 180, width: 320, height: 520)
}

nonisolated struct DetachedWorkspacePanel: Codable, Equatable, Identifiable, Sendable {
    var panel: WorkspacePanel
    var frame: WorkspaceWindowFrame

    var id: WorkspacePanel { panel }
}

nonisolated struct WorkspaceLayout: Codable, Equatable, Sendable {
    var columns: [WorkspaceColumn]
    var detachedPanels: [DetachedWorkspacePanel]

    init(columns: [WorkspaceColumn], detachedPanels: [DetachedWorkspacePanel] = []) {
        self.columns = columns
        self.detachedPanels = detachedPanels
    }

    static let standard = WorkspaceLayout(columns: [
        WorkspaceColumn(panels: [.pages, .components, .reusableComponents, .globalComponents, .structure, .assets], selectedPanel: .pages),
        WorkspaceColumn(panels: [.canvas]),
        WorkspaceColumn(panels: [.inspector])
    ])

    mutating func move(_ panel: WorkspacePanel, to destinationID: UUID, before target: WorkspacePanel? = nil) {
        guard panel != .canvas,
              columns.first(where: { $0.id == destinationID })?.panels != [.canvas] else { return }
        remove(panel)
        guard let destinationIndex = columns.firstIndex(where: { $0.id == destinationID }) else {
            columns.append(WorkspaceColumn(panels: [panel]))
            return
        }
        let insertionIndex = target.flatMap {
            columns[destinationIndex].panels.firstIndex(of: $0)
        } ?? columns[destinationIndex].panels.endIndex
        columns[destinationIndex].panels.insert(panel, at: insertionIndex)
        columns[destinationIndex].selectedPanel = panel
    }

    mutating func dockAsColumn(_ panel: WorkspacePanel, beside columnID: UUID, before: Bool) {
        guard panel != .canvas else { return }
        remove(panel)
        guard let index = columns.firstIndex(where: { $0.id == columnID }) else {
            columns.append(WorkspaceColumn(panels: [panel]))
            return
        }
        columns.insert(WorkspaceColumn(panels: [panel]), at: index + (before ? 0 : 1))
    }

    mutating func moveToNewColumn(_ panel: WorkspacePanel, after sourceColumnID: UUID) {
        guard panel != .canvas else { return }
        guard columns.first(where: { $0.id == sourceColumnID })?.panels.count ?? 0 > 1 else { return }
        dockAsColumn(panel, beside: sourceColumnID, before: false)
    }

    mutating func detach(_ panel: WorkspacePanel, frame: WorkspaceWindowFrame = .initial) {
        guard panel != .canvas else { return }
        guard columns.first(where: { $0.panels.contains(panel) })?.panels.count ?? 0 > 1 else { return }
        remove(panel)
        detachedPanels.append(.init(panel: panel, frame: frame))
    }

    mutating func updateFrame(_ frame: WorkspaceWindowFrame, for panel: WorkspacePanel) {
        guard let index = detachedPanels.firstIndex(where: { $0.panel == panel }) else { return }
        detachedPanels[index].frame = frame
    }

    mutating func redockClosedPanel(_ panel: WorkspacePanel) {
        guard panel != .canvas else { return }
        guard detachedPanels.contains(where: { $0.panel == panel }) else { return }
        detachedPanels.removeAll(where: { $0.panel == panel })
        if columns.isEmpty {
            columns = [WorkspaceColumn(panels: [panel])]
        } else {
            columns[0].panels.append(panel)
            columns[0].selectedPanel = panel
        }
    }

    mutating func activate(_ panel: WorkspacePanel) {
        guard let index = columns.firstIndex(where: { $0.panels.contains(panel) }) else { return }
        columns[index].selectedPanel = panel
    }

    mutating func reset() {
        self = .standard
    }

    static func restored(from defaults: UserDefaults = .standard) -> WorkspaceLayout {
        guard let data = defaults.data(forKey: storageKey),
              var layout = try? JSONDecoder().decode(WorkspaceLayout.self, from: data) else {
            return .standard
        }
        layout.addMissingUtilityPanels()
        guard layout.isValid else { return .standard }
        return layout
    }

    func persist(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private mutating func remove(_ panel: WorkspacePanel) {
        detachedPanels.removeAll(where: { $0.panel == panel })
        for index in columns.indices {
            columns[index].panels.removeAll(where: { $0 == panel })
            if columns[index].selectedPanel == panel, let replacement = columns[index].panels.first {
                columns[index].selectedPanel = replacement
            }
        }
        columns.removeAll(where: { $0.panels.isEmpty })
    }

    mutating func addMissingUtilityPanels() {
        let existing = Set(columns.flatMap(\.panels) + detachedPanels.map(\.panel))
        let missing = WorkspacePanel.allCases.filter { !existing.contains($0) && $0 != .canvas }
        guard !missing.isEmpty else { return }
        if let index = columns.firstIndex(where: { $0.panels != [.canvas] }) {
            columns[index].panels.append(contentsOf: missing)
        }
    }

    private var isValid: Bool {
        let panels = columns.flatMap(\.panels) + detachedPanels.map(\.panel)
        return !columns.isEmpty &&
            Set(panels) == Set(WorkspacePanel.allCases) &&
            panels.count == WorkspacePanel.allCases.count &&
            columns.contains(where: { $0.panels == [.canvas] }) &&
            !detachedPanels.contains(where: { $0.panel == .canvas }) &&
            columns.allSatisfy { $0.panels.contains($0.selectedPanel) }
    }

    private enum CodingKeys: String, CodingKey {
        case columns
        case detachedPanels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decode([WorkspaceColumn].self, forKey: .columns)
        detachedPanels = try container.decodeIfPresent([DetachedWorkspacePanel].self, forKey: .detachedPanels) ?? []
    }

    private static let storageKey = "foundry.workspace.layout.v1"
}
