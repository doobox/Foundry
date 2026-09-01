import Foundation
import Testing
@testable import Foundry

struct WorkspaceLayoutTests {
    @Test
    func standardLayoutContainsEveryPanelOnce() {
        let panels = WorkspaceLayout.standard.columns.flatMap(\.panels)

        #expect(panels.count == WorkspacePanel.allCases.count)
        #expect(Set(panels) == Set(WorkspacePanel.allCases))
        #expect(WorkspaceLayout.standard.columns.map(\.role) == [.sidebarDock, .canvas, .inspectorDock])
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
        #expect(Set(layout.columns.flatMap(\.panels)) == Set(WorkspacePanel.allCases))
    }

    @Test
    func detachingAndRedockingPreservesPanelIdentity() {
        var layout = WorkspaceLayout.standard

        layout.detach(.components)
        #expect(layout.detachedPanels.map(\.panel) == [.components])
        #expect(!layout.columns.flatMap(\.panels).contains(.components))

        layout.redockClosedPanel(.components)
        #expect(layout.detachedPanels.isEmpty)
        #expect(layout.columns.flatMap(\.panels).contains(.components))
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

}
