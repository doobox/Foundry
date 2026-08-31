import AppKit
import SwiftUI

struct DockingWorkspaceView<PanelContent: View>: View {
    @Binding var layout: WorkspaceLayout
    @Binding var canvasEditorOptions: CanvasEditorOptions
    @Binding var canvasViewportWidth: Double
    let canvasScreens: ScreenTokens
    let openProjectSettings: () -> Void
    let openThemeEditor: () -> Void
    let previewSite: () -> Void
    let publishSite: () -> Void
    @ViewBuilder let panelContent: (WorkspacePanel) -> PanelContent
    @Environment(WorkspacePresetLibrary.self) private var workspaceLibrary
    @Environment(\.openWindow) private var openWindow
    @State private var selectedWorkspaceID: UUID?
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var showsInspector = true

    var body: some View {
        NavigationSplitView {
            ForEach($layout.columns) { $column in
                if column.id == sidebarColumnID {
                    let panelSizing = sizing(for: column.panels)
                    WorkspaceColumnView(
                        column: $column,
                        usesSidebarMaterial: true,
                        canMoveSelectedTab: column.panels.count > 1,
                        movePanel: movePanel,
                        dockBeside: dockBeside,
                        moveToNewColumn: { panel in
                            layout.moveToNewColumn(panel, after: column.id)
                        },
                        detachPanel: { panel in
                            layout.detach(panel)
                        },
                        panelContent: panelContent
                    )
                    .navigationSplitViewColumnWidth(
                        min: panelSizing.minimum,
                        ideal: preferredWidth(for: column, sizing: panelSizing),
                        max: panelSizing.maximum
                    )
                    .captureWidth($column.preferredWidth, constrainedBy: panelSizing)
                }
            }
        } detail: {
            HSplitView {
                ForEach($layout.columns) { $column in
                    if column.panels == [.canvas] {
                        FixedCanvasColumn(
                            columnID: column.id,
                            editorOptions: $canvasEditorOptions,
                            viewportWidth: $canvasViewportWidth,
                            screens: canvasScreens,
                            openThemeEditor: openThemeEditor,
                            dockBeside: dockBeside,
                            content: { panelContent(.canvas) }
                        )
                        .frame(minWidth: 0, idealWidth: 760, maxWidth: .infinity)
                        .layoutPriority(-1)
                        .toolbar {
                            ToolbarItem {
                                workspacePresetsMenu
                            }
                            ToolbarSpacer(.fixed)
                            ToolbarItem {
                                Button("Preview Site", systemImage: "safari", action: previewSite)
                                    .help("Generate and open a production preview")
                            }
//                        
//                            if !showsInspector {
//                                ToolbarSpacer(.fixed)
//                                ToolbarItem {
//                                    inspectorToggleButton
//                                }
//                            }
                        }
                    } else if column.id != sidebarColumnID
                                && (column.id != inspectorColumnID || showsInspector) {
                        let panelSizing = sizing(for: column.panels)
                        WorkspaceColumnView(
                            column: $column,
                            usesSidebarMaterial: false,
                            canMoveSelectedTab: column.panels.count > 1,
                            movePanel: movePanel,
                            dockBeside: dockBeside,
                            moveToNewColumn: { panel in
                                layout.moveToNewColumn(panel, after: column.id)
                            },
                            detachPanel: { panel in
                                layout.detach(panel)
                            },
                            panelContent: panelContent
                        )
                        .frame(
                            minWidth: panelSizing.minimum,
                            idealWidth: preferredWidth(for: column, sizing: panelSizing),
                            maxWidth: panelSizing.maximum
                        )
                        .captureWidth($column.preferredWidth, constrainedBy: panelSizing)
                        .toolbar {
                            if column.id == inspectorColumnID {
                                ToolbarSpacer(.flexible)
                                ToolbarItem {
                                    Button {
                                        openProjectSettings()
                                    } label: {
                                        Label("Project Settings", systemImage: "gearshape")
                                            .labelStyle(.iconOnly)
                                    }
                                    .help("Open project settings")
                                }
                                ToolbarSpacer(.fixed)
                                ToolbarItem {
                                    Button {
                                        publishSite()
                                    } label: {
                                        Label("Publish", systemImage: "cloud")
                                            .labelStyle(.titleAndIcon)
                                            .padding(.horizontal, 5)
                                    }
                                    .help("Publish site")
                                }
                                ToolbarSpacer(.fixed)
                                ToolbarItem {
                                    inspectorToggleButton
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Save Workspace As", isPresented: $isNamingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save the current panels, tabs, windows, and column widths.")
        }
    }

    private var sidebarColumnID: UUID? {
        guard let canvasIndex = layout.columns.firstIndex(where: { $0.panels == [.canvas] }),
              canvasIndex > layout.columns.startIndex else { return nil }
        return layout.columns.first?.id
    }

    private var inspectorColumnID: UUID? {
        guard let canvasIndex = layout.columns.firstIndex(where: { $0.panels == [.canvas] }),
              canvasIndex < layout.columns.index(before: layout.columns.endIndex) else { return nil }
        return layout.columns.last?.id
    }

    private func movePanel(_ panel: WorkspacePanel, _ destinationID: UUID, _ target: WorkspacePanel?) {
        layout.move(panel, to: destinationID, before: target)
    }

    private func dockBeside(_ panel: WorkspacePanel, _ columnID: UUID, _ before: Bool) {
        layout.dockAsColumn(panel, beside: columnID, before: before)
    }

    private func sizing(for panels: [WorkspacePanel]) -> PanelSizing {
        panels.map(PanelSizing.init).reduce(.zero) { $0.combined(with: $1) }
    }

    private func preferredWidth(for column: WorkspaceColumn, sizing: PanelSizing) -> CGFloat {
        guard let preferredWidth = column.preferredWidth else { return sizing.ideal }
        return min(max(CGFloat(preferredWidth), sizing.minimum), sizing.maximum)
    }

    private var inspectorToggleButton: some View {
        Button {
            showsInspector.toggle()
        } label: {
            Label("Toggle Inspector", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
        }
        .help(showsInspector ? "Hide Inspector" : "Show Inspector")
    }

    private var workspacePresetsMenu: some View {
        Menu("Workspaces", systemImage: "rectangle.split.3x1") {
            Button {
                layout.reset()
                showsInspector = true
                selectedWorkspaceID = nil
            } label: {
                if selectedWorkspaceID == nil {
                    Label("Default Workspace", systemImage: "checkmark")
                } else {
                    Text("Default Workspace")
                }
            }

            if !workspaceLibrary.presets.isEmpty {
                Divider()
                ForEach(workspaceLibrary.presets) { preset in
                    Button {
                        layout = preset.layout
                        selectedWorkspaceID = preset.id
                    } label: {
                        if selectedWorkspaceID == preset.id {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }
            }

            Divider()
            Button("Save Workspace") {
                saveWorkspace()
            }
            Button("Save Workspace As…") {
                presetName = suggestedWorkspaceName
                isNamingPreset = true
            }
            Button("Manage Workspaces…") {
                openWindow(id: "workspace-manager")
            }
        }
        .menuIndicator(.hidden)
        .help("Save or restore a workspace arrangement")
    }

    private var suggestedWorkspaceName: String {
        if let selectedWorkspaceID,
           let preset = workspaceLibrary.presets.first(where: { $0.id == selectedWorkspaceID }) {
            return preset.name
        }
        return "Workspace \(workspaceLibrary.presets.count + 1)"
    }

    private func saveWorkspace() {
        guard let selectedWorkspaceID,
              let preset = workspaceLibrary.presets.first(where: { $0.id == selectedWorkspaceID }) else {
            presetName = suggestedWorkspaceName
            isNamingPreset = true
            return
        }

        _ = workspaceLibrary.save(name: preset.name, layout: layout, replacing: selectedWorkspaceID)
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        selectedWorkspaceID = workspaceLibrary.save(name: name, layout: layout)
    }
}

nonisolated private struct PanelSizing {
    let minimum: CGFloat
    let ideal: CGFloat
    let maximum: CGFloat

    static let zero = PanelSizing(minimum: 0, ideal: 0, maximum: 0)

    init(panel: WorkspacePanel) {
        switch panel {
        case .pages:
            self.init(minimum: 180, ideal: 230, maximum: 300)
        case .components, .reusableComponents, .globalComponents:
            self.init(minimum: 210, ideal: 260, maximum: 330)
        case .structure:
            self.init(minimum: 230, ideal: 290, maximum: 380)
        case .assets:
            self.init(minimum: 220, ideal: 280, maximum: 360)
        case .inspector:
            self.init(minimum: 380, ideal: 380, maximum: 494)
        case .canvas:
            self.init(minimum: 240, ideal: 760, maximum: .infinity)
        }
    }

    init(minimum: CGFloat, ideal: CGFloat, maximum: CGFloat) {
        self.minimum = minimum
        self.ideal = ideal
        self.maximum = maximum
    }

    func combined(with other: PanelSizing) -> PanelSizing {
        PanelSizing(
            minimum: max(minimum, other.minimum),
            ideal: max(ideal, other.ideal),
            maximum: max(maximum, other.maximum)
        )
    }
}

nonisolated private struct ColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func captureWidth(_ preferredWidth: Binding<Double?>, constrainedBy sizing: PanelSizing) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ColumnWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ColumnWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            let constrainedWidth = min(max(width, sizing.minimum), sizing.maximum)
            if abs((preferredWidth.wrappedValue ?? 0) - Double(constrainedWidth)) > 1 {
                preferredWidth.wrappedValue = Double(constrainedWidth)
            }
        }
    }
}

private struct CanvasOptionsButton: View {
    @Binding var options: CanvasEditorOptions
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Canvas Options")
        .help("Canvas Options")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Canvas Options")
                    .font(.headline)

                Divider()

                Toggle("Show Titles", isOn: $options.showsTitles)
                Toggle("Show Outlines", isOn: $options.showsOutlines)
                Toggle("Show Selection", isOn: $options.showsSelection)
                Toggle("Scroll to Selection", isOn: $options.scrollsToSelection)
            }
            .padding(16)
            .frame(width: 240, alignment: .leading)
        }
    }
}

private struct FixedCanvasColumn<Content: View>: View {
    let columnID: UUID
    @Binding var editorOptions: CanvasEditorOptions
    @Binding var viewportWidth: Double
    let screens: ScreenTokens
    let openThemeEditor: () -> Void
    let dockBeside: (WorkspacePanel, UUID, Bool) -> Void
    @ViewBuilder let content: () -> Content
    @State private var leadingTargeted = false
    @State private var trailingTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CanvasOptionsButton(options: $editorOptions)
                Button(action: openThemeEditor) {
                    Image(systemName: "theatermask.and.paintbrush")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Theme Editor")
                .help("Open Theme Editor")
                Spacer()
                HStack(spacing: 12) {
                    ForEach(screens.enabledScreens) { screen in
                        Button {
                            viewportWidth = screens.canvasWidth(for: screen)
                        } label: {
                            Image(systemName: screen.id.systemImage)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isSelected(screen) ? Color.accentColor : .secondary)
                        .accessibilityLabel(screen.id.shortTitle)
                        .help("\(screen.id.shortTitle) · \(Int(screens.canvasWidth(for: screen))) px")
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(.bar)
            Divider()
            GeometryReader { proxy in
                content()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            SideDockTarget(title: "Dock Left", isTargeted: leadingTargeted)
                .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                    dock(values, before: true)
                } isTargeted: {
                    leadingTargeted = $0
                }
        }
        .overlay(alignment: .trailing) {
            SideDockTarget(title: "Dock Right", isTargeted: trailingTargeted)
                .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                    dock(values, before: false)
                } isTargeted: {
                    trailingTargeted = $0
                }
        }
    }

    private func isSelected(_ screen: ThemeScreen) -> Bool {
        screens.activeScreen(for: viewportWidth).id == screen.id
    }

    private func dock(_ values: [WorkspacePanelDragPayload], before: Bool) -> Bool {
        guard let panel = values.first?.panel,
              panel != .canvas else { return false }
        dockBeside(panel, columnID, before)
        return true
    }
}

private struct WorkspaceColumnView<PanelContent: View>: View {
    @Binding var column: WorkspaceColumn
    let usesSidebarMaterial: Bool
    let canMoveSelectedTab: Bool
    let movePanel: (WorkspacePanel, UUID, WorkspacePanel?) -> Void
    let dockBeside: (WorkspacePanel, UUID, Bool) -> Void
    let moveToNewColumn: (WorkspacePanel) -> Void
    let detachPanel: (WorkspacePanel) -> Void
    @ViewBuilder let panelContent: (WorkspacePanel) -> PanelContent
    @State private var leadingTargeted = false
    @State private var trailingTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            HStack {
                Text(column.selectedPanel.title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()
            panelContent(column.selectedPanel)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            if usesSidebarMaterial {
                SidebarMaterialBackground()
                    .ignoresSafeArea()
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        }
        .overlay(alignment: .leading) {
            SideDockTarget(title: "Dock Left", isTargeted: leadingTargeted)
                .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                    dock(values, before: true)
                } isTargeted: {
                    leadingTargeted = $0
                }
        }
        .overlay(alignment: .trailing) {
            SideDockTarget(title: "Dock Right", isTargeted: trailingTargeted)
                .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                    dock(values, before: false)
                } isTargeted: {
                    trailingTargeted = $0
                }
        }
    }

    private var tabBar: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(column.panels) { panel in
                        WorkspaceTab(
                            panel: panel,
                            isSelected: panel == column.selectedPanel,
                            canMove: canMoveSelectedTab,
                            select: {
                                column.selectedPanel = panel
                            },
                            moveToNewColumn: { moveToNewColumn(panel) },
                            detach: { detachPanel(panel) }
                        )
                        .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                            _ = accept(values, before: panel)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(minWidth: geometry.size.width, maxHeight: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 36)
        .background(.bar)
        .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
            _ = accept(values, before: nil)
        }
    }

    private func accept(_ values: [WorkspacePanelDragPayload], before target: WorkspacePanel?) -> Bool {
        guard let panel = values.first?.panel else { return false }
        movePanel(panel, column.id, target)
        return true
    }

    private func dock(_ values: [WorkspacePanelDragPayload], before: Bool) -> Bool {
        guard let panel = values.first?.panel else { return false }
        dockBeside(panel, column.id, before)
        return true
    }
}

private struct SideDockTarget: View {
    let title: String
    let isTargeted: Bool

    var body: some View {
        ZStack {
            Color.accentColor.opacity(isTargeted ? 0.24 : 0.001)
            if isTargeted {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(width: isTargeted ? 72 : 18)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

private struct WorkspaceTab: View {
    let panel: WorkspacePanel
    let isSelected: Bool
    let canMove: Bool
    let select: () -> Void
    let moveToNewColumn: () -> Void
    let detach: () -> Void

    var body: some View {
        Button(action: select) {
            Image(systemName: panel.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .accessibilityLabel(panel.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(panel.title)
        .draggable(WorkspacePanelDragPayload(panel: panel))
        .contextMenu {
            Button("Move Tab to New Column", systemImage: "rectangle.split.2x1", action: moveToNewColumn)
                .disabled(!canMove)
            Button("Detach Tab", systemImage: "macwindow.on.rectangle", action: detach)
                .disabled(!canMove)
        }
    }
}
