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
    case parts
    case reusableParts
    case globalParts
    case structure
    case assets
    case developer
    case canvas
    case inspector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pages: "Pages"
        case .parts: "Parts"
        case .reusableParts: "Templates"
        case .globalParts: "Globals"
        case .structure: "Structure"
        case .assets: "Assets"
        case .developer: "Developer"
        case .canvas: "Canvas"
        case .inspector: "Inspector"
        }
    }

    var systemImage: String {
        switch self {
        case .pages: "doc.on.doc"
        case .parts: "puzzlepiece.extension"
        case .reusableParts: "rectangle.3.group"
        case .globalParts: "globe"
        case .structure: "list.bullet.indent"
        case .assets: "folder"
        case .developer: "ant"
        case .canvas: "macwindow"
        case .inspector: "info.circle"
        }
    }
}

nonisolated enum WorkspaceColumnRole: String, Codable, Sendable {
    case sidebarDock
    case workspace
    case canvas
    case inspectorDock

    var isPersistentDock: Bool {
        self == .sidebarDock || self == .inspectorDock
    }

    var emptySelection: WorkspacePanel {
        switch self {
        case .sidebarDock: .pages
        case .inspectorDock: .inspector
        case .canvas: .canvas
        case .workspace: .pages
        }
    }
}

nonisolated struct WorkspaceColumn: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var role: WorkspaceColumnRole
    var panels: [WorkspacePanel]
    var selectedPanel: WorkspacePanel
    var preferredWidth: Double?

    init(
        id: UUID = UUID(),
        role: WorkspaceColumnRole = .workspace,
        panels: [WorkspacePanel],
        selectedPanel: WorkspacePanel? = nil,
        preferredWidth: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.panels = panels
        self.selectedPanel = selectedPanel ?? panels.first ?? role.emptySelection
        self.preferredWidth = preferredWidth
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case panels
        case selectedPanel
        case preferredWidth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(WorkspaceColumnRole.self, forKey: .role)
        panels = try container.decode([WorkspacePanel].self, forKey: .panels)
        selectedPanel = try container.decodeIfPresent(WorkspacePanel.self, forKey: .selectedPanel)
            ?? panels.first
            ?? role.emptySelection
        preferredWidth = try container.decodeIfPresent(Double.self, forKey: .preferredWidth)
    }
}

nonisolated struct WorkspaceWindowFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let initial = WorkspaceWindowFrame(x: 180, y: 180, width: 330, height: 650)
}

nonisolated struct DetachedWorkspacePanel: Codable, Equatable, Identifiable, Sendable {
    var panel: WorkspacePanel
    var frame: WorkspaceWindowFrame
    var origin: DetachedPanelOrigin? = nil

    var id: WorkspacePanel { panel }
}

nonisolated struct DetachedPanelOrigin: Codable, Equatable, Sendable {
    var columnID: UUID
    var columnIndex: Int
    var panelIndex: Int
    var columnRole: WorkspaceColumnRole
    var columnPreferredWidth: Double?
}

nonisolated struct WorkspaceLayout: Codable, Equatable, Sendable {
    var columns: [WorkspaceColumn]
    var detachedPanels: [DetachedWorkspacePanel]
    var showsSidebar: Bool
    var showsInspector: Bool

    init(
        columns: [WorkspaceColumn],
        detachedPanels: [DetachedWorkspacePanel] = [],
        showsSidebar: Bool = true,
        showsInspector: Bool = true
    ) {
        self.columns = columns
        self.detachedPanels = detachedPanels
        self.showsSidebar = showsSidebar
        self.showsInspector = showsInspector
    }

    static let standard = WorkspaceLayout(columns: [
        WorkspaceColumn(
            role: .sidebarDock,
            panels: [.pages, .parts, .reusableParts, .globalParts, .structure, .assets],
            selectedPanel: .pages
        ),
        WorkspaceColumn(role: .canvas, panels: [.canvas]),
        WorkspaceColumn(role: .inspectorDock, panels: [.inspector])
    ])

    mutating func move(_ panel: WorkspacePanel, to destinationID: UUID, before target: WorkspacePanel? = nil) {
        guard panel != .canvas,
              columns.first(where: { $0.id == destinationID })?.role != .canvas else { return }
        remove(panel)
        guard let destinationIndex = columns.firstIndex(where: { $0.id == destinationID }) else {
            insertWorkspaceColumn(WorkspaceColumn(panels: [panel]), at: columns.endIndex)
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
            insertWorkspaceColumn(WorkspaceColumn(panels: [panel]), at: columns.endIndex)
            return
        }
        insertWorkspaceColumn(
            WorkspaceColumn(panels: [panel]),
            at: index + (before ? 0 : 1)
        )
    }

    mutating func moveToNewColumn(_ panel: WorkspacePanel, after sourceColumnID: UUID) {
        guard panel != .canvas else { return }
        guard let source = columns.first(where: { $0.id == sourceColumnID }),
              source.panels.count > 1 || source.role.isPersistentDock else { return }
        dockAsColumn(panel, beside: sourceColumnID, before: false)
    }

    mutating func detach(_ panel: WorkspacePanel, frame: WorkspaceWindowFrame = .initial) {
        guard panel != .canvas else { return }
        guard let columnIndex = columns.firstIndex(where: { $0.panels.contains(panel) }),
              let panelIndex = columns[columnIndex].panels.firstIndex(of: panel) else { return }
        let sourceColumn = columns[columnIndex]
        let origin = DetachedPanelOrigin(
            columnID: sourceColumn.id,
            columnIndex: columnIndex,
            panelIndex: panelIndex,
            columnRole: sourceColumn.role,
            columnPreferredWidth: sourceColumn.preferredWidth
        )
        remove(panel)
        detachedPanels.append(.init(panel: panel, frame: frame, origin: origin))
    }

    mutating func updateFrame(_ frame: WorkspaceWindowFrame, for panel: WorkspacePanel) {
        guard let index = detachedPanels.firstIndex(where: { $0.panel == panel }) else { return }
        detachedPanels[index].frame = frame
    }

    mutating func redockClosedPanel(_ panel: WorkspacePanel) {
        guard panel != .canvas else { return }
        guard let detached = detachedPanels.first(where: { $0.panel == panel }) else { return }
        detachedPanels.removeAll(where: { $0.panel == panel })

        if let origin = detached.origin {
            if let columnIndex = columns.firstIndex(where: { $0.id == origin.columnID }) {
                let insertionIndex = min(origin.panelIndex, columns[columnIndex].panels.endIndex)
                columns[columnIndex].panels.insert(panel, at: insertionIndex)
                columns[columnIndex].selectedPanel = panel
                return
            }

            insertWorkspaceColumn(
                WorkspaceColumn(
                    id: origin.columnID,
                    role: origin.columnRole,
                    panels: [panel],
                    selectedPanel: panel,
                    preferredWidth: origin.columnPreferredWidth
                ),
                at: origin.columnIndex
            )
            return
        }

        let destinationRole: WorkspaceColumnRole = panel == .inspector ? .inspectorDock : .sidebarDock
        guard let index = columns.firstIndex(where: { $0.role == destinationRole }) else { return }
        columns[index].panels.append(panel)
        columns[index].selectedPanel = panel
    }

    mutating func activate(_ panel: WorkspacePanel) {
        guard let index = columns.firstIndex(where: { $0.panels.contains(panel) }) else { return }
        columns[index].selectedPanel = panel
    }

    mutating func reset(includingDeveloperPanel: Bool = false) {
        self = .standard
        setDeveloperPanelVisible(includingDeveloperPanel)
    }

    static func restored(from defaults: UserDefaults = .standard) -> WorkspaceLayout {
        let includesDeveloperPanel = defaults.bool(forKey: AppPreferenceKey.showsDeveloperPanel)
        guard let data = defaults.data(forKey: storageKey),
              var layout = try? JSONDecoder().decode(WorkspaceLayout.self, from: data) else {
            var layout = WorkspaceLayout.standard
            layout.setDeveloperPanelVisible(includesDeveloperPanel)
            return layout
        }
        layout.setDeveloperPanelVisible(includesDeveloperPanel)
        guard layout.isValid else {
            var fallback = WorkspaceLayout.standard
            fallback.setDeveloperPanelVisible(includesDeveloperPanel)
            return fallback
        }
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
            } else if columns[index].panels.isEmpty {
                columns[index].selectedPanel = columns[index].role.emptySelection
            }
        }
        columns.removeAll(where: { $0.panels.isEmpty && !$0.role.isPersistentDock })
    }

    mutating func addMissingUtilityPanels(includingDeveloperPanel: Bool = false) {
        normalizeColumnRoles()
        if !includingDeveloperPanel {
            remove(.developer)
        }
        let existing = Set(columns.flatMap(\.panels) + detachedPanels.map(\.panel))
        let missing = WorkspacePanel.allCases.filter {
            !existing.contains($0) &&
                $0 != .canvas &&
                ($0 != .developer || includingDeveloperPanel)
        }
        guard !missing.isEmpty else { return }

        for panel in missing {
            let destinationRole: WorkspaceColumnRole = panel == .inspector ? .inspectorDock : .sidebarDock
            guard let index = columns.firstIndex(where: { $0.role == destinationRole }) else { continue }
            columns[index].panels.append(panel)
            if columns[index].panels.count == 1 {
                columns[index].selectedPanel = panel
            }
        }
    }

    mutating func setDeveloperPanelVisible(_ isVisible: Bool) {
        if isVisible {
            guard !columns.flatMap(\.panels).contains(.developer),
                  !detachedPanels.contains(where: { $0.panel == .developer }),
                  let sidebarIndex = columns.firstIndex(where: { $0.role == .sidebarDock }) else {
                return
            }
            columns[sidebarIndex].panels.append(.developer)
        } else {
            remove(.developer)
        }
    }

    private var isValid: Bool {
        let panels = columns.flatMap(\.panels) + detachedPanels.map(\.panel)
        let requiredPanels = Set(WorkspacePanel.allCases.filter { $0 != .developer })
        return !columns.isEmpty &&
            requiredPanels.isSubset(of: Set(panels)) &&
            Set(panels).count == panels.count &&
            panels.allSatisfy { requiredPanels.contains($0) || $0 == .developer } &&
            columns.filter { $0.role == .sidebarDock }.count == 1 &&
            columns.filter { $0.role == .canvas }.count == 1 &&
            columns.filter { $0.role == .inspectorDock }.count == 1 &&
            columns.first?.role == .sidebarDock &&
            columns.last?.role == .inspectorDock &&
            columns.contains(where: { $0.role == .canvas && $0.panels == [.canvas] }) &&
            !detachedPanels.contains(where: { $0.panel == .canvas }) &&
            columns.allSatisfy {
                $0.panels.contains($0.selectedPanel) || ($0.panels.isEmpty && $0.role.isPersistentDock)
            }
    }

    private enum CodingKeys: String, CodingKey {
        case columns
        case detachedPanels
        case showsSidebar
        case showsInspector
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decode([WorkspaceColumn].self, forKey: .columns)
        detachedPanels = try container.decode([DetachedWorkspacePanel].self, forKey: .detachedPanels)
        showsSidebar = try container.decode(Bool.self, forKey: .showsSidebar)
        showsInspector = try container.decode(Bool.self, forKey: .showsInspector)
    }

    private mutating func insertWorkspaceColumn(_ column: WorkspaceColumn, at proposedIndex: Int) {
        let lowerBound = (columns.firstIndex(where: { $0.role == .sidebarDock }) ?? -1) + 1
        let upperBound = columns.firstIndex(where: { $0.role == .inspectorDock }) ?? columns.endIndex
        columns.insert(column, at: min(max(proposedIndex, lowerBound), upperBound))
    }

    private mutating func normalizeColumnRoles() {
        if let canvasIndex = columns.firstIndex(where: { $0.panels == [.canvas] }) {
            columns[canvasIndex].role = .canvas
        } else if let canvasIndex = columns.firstIndex(where: { $0.role == .canvas }) {
            columns[canvasIndex].panels = [.canvas]
            columns[canvasIndex].selectedPanel = .canvas
        }

        if !columns.contains(where: { $0.role == .sidebarDock }) {
            if let canvasIndex = columns.firstIndex(where: { $0.role == .canvas }), canvasIndex > 0 {
                columns[0].role = .sidebarDock
            } else {
                columns.insert(WorkspaceColumn(role: .sidebarDock, panels: []), at: 0)
            }
        }

        if !columns.contains(where: { $0.role == .inspectorDock }) {
            if let canvasIndex = columns.firstIndex(where: { $0.role == .canvas }),
               canvasIndex < columns.index(before: columns.endIndex) {
                columns[columns.index(before: columns.endIndex)].role = .inspectorDock
            } else {
                columns.append(WorkspaceColumn(role: .inspectorDock, panels: []))
            }
        }

        if let sidebarIndex = columns.firstIndex(where: { $0.role == .sidebarDock }), sidebarIndex != 0 {
            columns.insert(columns.remove(at: sidebarIndex), at: 0)
        }
        if let inspectorIndex = columns.firstIndex(where: { $0.role == .inspectorDock }),
           inspectorIndex != columns.index(before: columns.endIndex) {
            columns.append(columns.remove(at: inspectorIndex))
        }
    }

    private static let storageKey = "foundry.workspace.layout.v1"
}
