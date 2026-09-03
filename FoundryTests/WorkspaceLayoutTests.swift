import Foundation
import Testing
@testable import Foundry

struct WorkspaceLayoutTests {
    @Test
    func standardLayoutContainsEveryNonDeveloperPanelOnce() {
        let panels = WorkspaceLayout.standard.columns.flatMap(\.panels)
        let expectedPanels = WorkspacePanel.allCases.filter { $0 != .developer }

        #expect(panels.count == expectedPanels.count)
        #expect(Set(panels) == Set(expectedPanels))
        #expect(WorkspaceLayout.standard.columns.map(\.role) == [.sidebarDock, .canvas, .inspectorDock])
    }

    @Test
    func developerPanelIsAddedOnceAndCanBeHiddenAgain() {
        var layout = WorkspaceLayout.standard

        layout.setDeveloperPanelVisible(true)
        layout.setDeveloperPanelVisible(true)

        #expect(layout.columns.flatMap(\.panels).filter { $0 == .developer }.count == 1)
        #expect(layout.columns.first?.panels.last == .developer)

        layout.setDeveloperPanelVisible(false)

        #expect(!layout.columns.flatMap(\.panels).contains(.developer))
        #expect(!layout.detachedPanels.contains(where: { $0.panel == .developer }))
    }

    @Test
    func newDocumentIncludesDeveloperPanelOnlyWhenPreferenceIsEnabled() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!WorkspacePresetStore.initialLayoutForNewDocument(from: defaults)
            .columns.flatMap(\.panels).contains(.developer))

        defaults.set(true, forKey: AppPreferenceKey.showsDeveloperPanel)

        #expect(WorkspacePresetStore.initialLayoutForNewDocument(from: defaults)
            .columns.flatMap(\.panels).contains(.developer))
    }

    @Test
    func canvasCannotMoveIntoAnotherColumn() {
        var layout = WorkspaceLayout.standard
        let inspectorColumnID = layout.columns[2].id

        layout.move(.canvas, to: inspectorColumnID)

        #expect(layout == .standard)
    }

    @Test
    func utilityPanelCannotBecomeACanvasTab() {
        var layout = WorkspaceLayout.standard
        let canvasColumnID = layout.columns[1].id

        layout.move(.components, to: canvasColumnID)

        #expect(layout == .standard)
    }

    @Test
    func canvasCannotDetach() {
        var layout = WorkspaceLayout.standard

        layout.detach(.canvas)

        #expect(layout == .standard)
    }

    @Test
    func movingTabToNewColumnPreservesAllPanels() {
        var layout = WorkspaceLayout.standard
        let sourceID = layout.columns[0].id

        layout.moveToNewColumn(.components, after: sourceID)

        #expect(layout.columns.count == 4)
        #expect(layout.columns[1].panels == [.components])
        #expect(Set(layout.columns.flatMap(\.panels)) == Set(WorkspacePanel.allCases.filter { $0 != .developer }))
    }

    @Test
    func detachingAndRedockingPreservesPanelIdentity() {
        var layout = WorkspaceLayout.standard
        let sourceColumnID = layout.columns[0].id
        let sourcePanelIndex = layout.columns[0].panels.firstIndex(of: .components)

        layout.detach(.components)
        #expect(layout.detachedPanels.map(\.panel) == [.components])
        #expect(!layout.columns.flatMap(\.panels).contains(.components))

        layout.redockClosedPanel(.components)
        #expect(layout.detachedPanels.isEmpty)
        #expect(layout.columns.first(where: { $0.id == sourceColumnID })?.panels[sourcePanelIndex ?? 0] == .components)
    }

    @Test
    func solePanelInWorkspaceColumnCanDetach() {
        var layout = WorkspaceLayout.standard
        let sourceID = layout.columns[0].id
        layout.moveToNewColumn(.components, after: sourceID)
        let workspaceColumnIndex = layout.columns.firstIndex(where: { $0.panels == [.components] })
        let workspaceColumnID = workspaceColumnIndex.map { layout.columns[$0].id }
        if let workspaceColumnIndex {
            layout.columns[workspaceColumnIndex].preferredWidth = 412
        }

        layout.detach(.components)

        #expect(layout.detachedPanels.map(\.panel) == [.components])
        #expect(layout.columns.allSatisfy { $0.id != workspaceColumnID })
        #expect(!layout.columns.flatMap(\.panels).contains(.components))

        layout.redockClosedPanel(.components)

        #expect(layout.columns.firstIndex(where: { $0.id == workspaceColumnID }) == workspaceColumnIndex)
        #expect(layout.columns.first(where: { $0.id == workspaceColumnID })?.panels == [.components])
        #expect(layout.columns.first(where: { $0.id == workspaceColumnID })?.preferredWidth == 412)
    }

    @Test
    func detachedPanelFrameRoundTripsThroughJSON() throws {
        var layout = WorkspaceLayout.standard
        let frame = WorkspaceWindowFrame(x: 420, y: 260, width: 388, height: 640)
        layout.detach(.assets, frame: frame)

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: data)

        #expect(decoded == layout)
    }

    @Test
    func sideDockCreatesAdjacentColumn() {
        var layout = WorkspaceLayout.standard
        let canvasColumnID = layout.columns[1].id

        layout.dockAsColumn(.components, beside: canvasColumnID, before: false)

        let canvasIndex = layout.columns.firstIndex(where: { $0.id == canvasColumnID })
        #expect(canvasIndex != nil)
        #expect(layout.columns[(canvasIndex ?? 0) + 1].panels == [.components])
    }

    @Test
    func layoutRoundTripsThroughJSON() throws {
        var original = WorkspaceLayout.standard
        original.columns[0].preferredWidth = 286
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: data)

        #expect(decoded == original)
        #expect(decoded.columns[0].preferredWidth == 286)
    }

    @Test
    func olderLayoutWithoutWidthsStillDecodes() throws {
        let data = try JSONEncoder().encode(WorkspaceLayout.standard)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var columns = try #require(object["columns"] as? [[String: Any]])
        for index in columns.indices {
            columns[index].removeValue(forKey: "preferredWidth")
        }
        object["columns"] = columns
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: legacyData)

        #expect(decoded.columns.allSatisfy { $0.preferredWidth == nil })
    }

    @Test
    func olderLayoutWithoutRolesMigratesPersistentDocks() throws {
        let data = try JSONEncoder().encode(WorkspaceLayout.standard)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var columns = try #require(object["columns"] as? [[String: Any]])
        for index in columns.indices {
            columns[index].removeValue(forKey: "role")
        }
        object["columns"] = columns
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: legacyData)

        #expect(decoded.columns.map(\.role) == [.sidebarDock, .canvas, .inspectorDock])
    }

    @Test
    func legacyLayoutWithPanelsLeftOfCanvasAddsEmptyInspectorDock() throws {
        let legacyLayout = WorkspaceLayout(columns: [
            WorkspaceColumn(panels: [.pages, .components, .assets]),
            WorkspaceColumn(panels: [.structure]),
            WorkspaceColumn(panels: [.inspector, .globalComponents, .reusableComponents]),
            WorkspaceColumn(panels: [.canvas])
        ])
        let data = try JSONEncoder().encode(legacyLayout)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var columns = try #require(object["columns"] as? [[String: Any]])
        for index in columns.indices {
            columns[index].removeValue(forKey: "role")
        }
        object["columns"] = columns
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceLayout.self, from: legacyData)

        #expect(decoded.columns.first?.role == .sidebarDock)
        #expect(decoded.columns.last?.role == .inspectorDock)
        #expect(decoded.columns.last?.panels.isEmpty == true)
        #expect(decoded.columns.dropLast().flatMap(\.panels).contains(.inspector))
    }

    @Test
    func movingLastInspectorTabKeepsEmptyInspectorDock() {
        var layout = WorkspaceLayout.standard
        let sidebarID = layout.columns[0].id

        layout.move(.inspector, to: sidebarID)

        let inspectorDock = layout.columns.first(where: { $0.role == .inspectorDock })
        #expect(inspectorDock != nil)
        #expect(inspectorDock?.panels.isEmpty == true)
        #expect(layout.columns.last?.role == .inspectorDock)
    }

    @Test
    func movingEverySidebarTabKeepsEmptySidebarDock() {
        var layout = WorkspaceLayout.standard
        let inspectorID = layout.columns[2].id
        let sidebarPanels = layout.columns[0].panels

        for panel in sidebarPanels {
            layout.move(panel, to: inspectorID)
        }

        #expect(layout.columns.first?.role == .sidebarDock)
        #expect(layout.columns.first?.panels.isEmpty == true)
    }

    @Test
    func namedPresetsPersistCapturedWorkspace() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var layout = WorkspaceLayout.standard
        layout.columns[0].preferredWidth = 275
        let preset = WorkspacePreset(name: "Editing", layout: layout)

        WorkspacePresetStore.persist([preset], to: defaults)
        let restored = WorkspacePresetStore.restored(from: defaults)

        #expect(restored == [preset])
        #expect(restored.first?.layout.columns[0].preferredWidth == 275)
    }

    @Test
    func namedPresetsPersistDockVisibility() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var layout = WorkspaceLayout.standard
        layout.showsSidebar = false
        layout.showsInspector = false
        let preset = WorkspacePreset(name: "Focused", layout: layout)

        WorkspacePresetStore.persist([preset], to: defaults)
        let restored = try #require(WorkspacePresetStore.restored(from: defaults).first)

        #expect(restored.layout.showsSidebar == false)
        #expect(restored.layout.showsInspector == false)
    }

    @Test
    func newDocumentUsesLastSelectedNamedWorkspace() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var layout = WorkspaceLayout.standard
        layout.columns[0].preferredWidth = 300
        layout.moveToNewColumn(.structure, after: layout.columns[0].id)
        let preset = WorkspacePreset(name: "Editing", layout: layout)

        WorkspacePresetStore.persist([preset], to: defaults)
        WorkspaceSelectionStore.persist(preset.id, to: defaults)

        #expect(WorkspacePresetStore.initialLayoutForNewDocument(from: defaults) == layout)
    }

    @Test
    func newDocumentUsesFactoryDefaultWhenNoNamedWorkspacesExist() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var layout = WorkspaceLayout.standard
        layout.columns[0].preferredWidth = 300
        layout.persist(to: defaults)

        #expect(WorkspacePresetStore.initialLayoutForNewDocument(from: defaults) == .standard)
    }

    @Test
    func newDocumentUsesLastLiveLayoutWhenDefaultIsSelected() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var layout = WorkspaceLayout.standard
        layout.columns[0].preferredWidth = 300
        layout.persist(to: defaults)
        WorkspacePresetStore.persist(
            [WorkspacePreset(name: "Editing", layout: WorkspaceLayout.standard)],
            to: defaults
        )

        #expect(WorkspacePresetStore.initialLayoutForNewDocument(from: defaults) == layout)
    }

    @Test
    func deletingLastSelectedWorkspaceClearsSelection() throws {
        let suiteName = "WorkspaceLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preset = WorkspacePreset(name: "Editing", layout: .standard)
        WorkspacePresetStore.persist([preset], to: defaults)
        WorkspaceSelectionStore.persist(preset.id, to: defaults)

        WorkspacePresetStore.persist([], to: defaults)

        #expect(WorkspaceSelectionStore.restored(from: defaults) == nil)
    }

}
