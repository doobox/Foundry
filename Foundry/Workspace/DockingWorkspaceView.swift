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
    @SceneStorage("foundry.workspace.selectedPresetID") private var selectedWorkspaceIDValue = ""
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var showsInspector = true
    @State private var inspectorIsTransitioning = false

    var body: some View {
        NavigationSplitView {
            ForEach($layout.columns) { $column in
                if column.role == .sidebarDock {
                    let panelSizing = sizing(for: column)
                    WorkspaceColumnView(
                        column: $column,
                        usesSidebarMaterial: true,
                        canMoveSelectedTab: column.panels.count > 1 || column.role.isPersistentDock,
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
            HStack(spacing: 0) {
                HSplitView {
                    ForEach($layout.columns) { $column in
                        if column.role == .canvas {
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
                            }
                        } else if column.role != .sidebarDock {
                            let panelSizing = sizing(for: column)
                            let isInspectorColumn = column.role == .inspectorDock
                            WorkspaceColumnView(
                                column: $column,
                                usesSidebarMaterial: false,
                                canMoveSelectedTab: column.panels.count > 1 || column.role.isPersistentDock,
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
                            .captureWidth(
                                $column.preferredWidth,
                                constrainedBy: panelSizing,
                                isEnabled: !isInspectorColumn
                                    || (showsInspector && !inspectorIsTransitioning)
                            )
                            .background {
                                if isInspectorColumn {
                                    SplitViewItemCollapseController(
                                        isCollapsed: !showsInspector,
                                        minimumThickness: panelSizing.minimum,
                                        maximumThickness: panelSizing.maximum,
                                        transitionCompleted: {
                                            inspectorIsTransitioning = false
                                        }
                                    )
                                    .frame(width: 0, height: 0)
                                }
                            }
                            .toolbar {
                                if isInspectorColumn {
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
                .id(splitColumnIDs)
            }
        }
        .frame(minWidth: requiredMinimumWidth)
        .alert("Save Workspace As", isPresented: $isNamingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save the current panels, tabs, windows, and column widths.")
        }
        .onChange(of: workspaceLibrary.presets.map(\.id), initial: true) { _, presetIDs in
            if let selectedWorkspaceID, !presetIDs.contains(selectedWorkspaceID) {
                setSelectedWorkspaceID(nil)
            }
        }
        .background {
            WindowMinimumContentSize(
                width: requiredMinimumWidth,
                height: EditorWindowSize.minimumHeight
            )
            .frame(width: 0, height: 0)
        }
    }

    private var workspaceMinimumWidth: CGFloat {
        max(
            EditorWindowSize.minimumWidth,
            minimumWidth(for: layout.columns.filter { $0.role != .inspectorDock })
        )
    }

    private var splitColumnIDs: [UUID] {
        layout.columns
            .filter { $0.role != .sidebarDock }
            .map(\.id)
    }

    private var requiredMinimumWidth: CGFloat {
        guard let inspectorColumn = layout.columns.first(where: { $0.role == .inspectorDock }) else {
            return workspaceMinimumWidth
        }

        let inspectorDividerWidth: CGFloat = 10
        guard showsInspector else {
            return workspaceMinimumWidth + inspectorDividerWidth
        }

        let inspectorSizing = sizing(for: inspectorColumn)
        let inspectorWidth = preferredWidth(for: inspectorColumn, sizing: inspectorSizing)
        return workspaceMinimumWidth + inspectorDividerWidth + inspectorWidth
    }

    private func minimumWidth(for columns: [WorkspaceColumn]) -> CGFloat {
        let splitDividerWidth: CGFloat = 10
        let columnWidths = columns.reduce(CGFloat.zero) { width, column in
            let panelSizing = sizing(for: column)
            let requiredColumnWidth = column.role == .canvas
                ? panelSizing.minimum
                : preferredWidth(for: column, sizing: panelSizing)
            return width + requiredColumnWidth
        }
        let dividerWidths = CGFloat(max(columns.count - 1, 0)) * splitDividerWidth
        return columnWidths + dividerWidths
    }

    private func movePanel(_ panel: WorkspacePanel, _ destinationID: UUID, _ target: WorkspacePanel?) {
        layout.move(panel, to: destinationID, before: target)
    }

    private func dockBeside(_ panel: WorkspacePanel, _ columnID: UUID, _ before: Bool) {
        layout.dockAsColumn(panel, beside: columnID, before: before)
    }

    private func sizing(for column: WorkspaceColumn) -> PanelSizing {
        guard !column.panels.isEmpty else {
            switch column.role {
            case .sidebarDock:
                return PanelSizing(panel: .pages)
            case .inspectorDock:
                return PanelSizing(panel: .inspector)
            case .canvas:
                return PanelSizing(panel: .canvas)
            case .workspace:
                return .zero
            }
        }
        return column.panels.map(PanelSizing.init).reduce(.zero) { $0.combined(with: $1) }
    }

    private func preferredWidth(for column: WorkspaceColumn, sizing: PanelSizing) -> CGFloat {
        guard let preferredWidth = column.preferredWidth else { return sizing.ideal }
        return min(max(CGFloat(preferredWidth), sizing.minimum), sizing.maximum)
    }

    private var inspectorToggleButton: some View {
        Button {
            inspectorIsTransitioning = true
            showsInspector.toggle()
        } label: {
            Label("Toggle Inspector", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
        }
        .help(showsInspector ? "Hide Inspector" : "Show Inspector")
    }

    private var workspacePresetsMenu: some View {
        Menu("Workspaces", systemImage: "rectangle.split.3x1") {
            Toggle(
                "Default Workspace",
                isOn: Binding(
                    get: { selectedWorkspaceID == nil },
                    set: { isSelected in
                        guard isSelected else { return }
                        layout.reset()
                        showsInspector = true
                        setSelectedWorkspaceID(nil)
                    }
                )
            )

            if !workspaceLibrary.presets.isEmpty {
                Divider()
                ForEach(workspaceLibrary.presets) { preset in
                    Toggle(
                        preset.name,
                        isOn: Binding(
                            get: { selectedWorkspaceID == preset.id },
                            set: { isSelected in
                                guard isSelected else { return }
                                layout = preset.layout
                                setSelectedWorkspaceID(preset.id)
                            }
                        )
                    )
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
        setSelectedWorkspaceID(workspaceLibrary.save(name: name, layout: layout))
    }

    private var selectedWorkspaceID: UUID? {
        UUID(uuidString: selectedWorkspaceIDValue)
    }

    private func setSelectedWorkspaceID(_ id: UUID?) {
        selectedWorkspaceIDValue = id?.uuidString ?? ""
    }
}

private struct WindowMinimumContentSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> WindowMinimumSizeReaderView {
        let view = WindowMinimumSizeReaderView()
        view.minimumContentSize = NSSize(width: width, height: height)
        return view
    }

    func updateNSView(_ nsView: WindowMinimumSizeReaderView, context: Context) {
        nsView.minimumContentSize = NSSize(width: width, height: height)
    }
}

private final class WindowMinimumSizeReaderView: NSView {
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []

    var minimumContentSize = NSSize.zero {
        didSet {
            applyMinimumContentSize()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow()
        applyMinimumContentSize()
    }

    deinit {
        stopObservingWindow()
    }

    private func observeWindow() {
        guard observedWindow !== window else { return }
        stopObservingWindow()
        observedWindow = window
        guard let window else { return }

        let center = NotificationCenter.default
        windowObservers = [
            NSWindow.willStartLiveResizeNotification,
            NSWindow.didResizeNotification
        ].map { notification in
            center.addObserver(forName: notification, object: window, queue: .main) { [weak self] _ in
                self?.applyMinimumContentSize()
            }
        }
    }

    private func stopObservingWindow() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        observedWindow = nil
    }

    private func applyMinimumContentSize() {
        guard let window else { return }

        window.contentMinSize = minimumContentSize
        let currentSize = window.contentLayoutRect.size
        guard currentSize.width < minimumContentSize.width || currentSize.height < minimumContentSize.height else {
            return
        }

        let targetContentSize = NSSize(
            width: max(currentSize.width, minimumContentSize.width),
            height: max(currentSize.height, minimumContentSize.height)
        )
        let currentFrame = window.frame
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        targetFrame.origin.x = max(currentFrame.minX, window.screen?.visibleFrame.minX ?? currentFrame.minX)
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height
        window.setFrame(targetFrame, display: true)
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

private struct SplitViewItemCollapseController: NSViewRepresentable {
    let isCollapsed: Bool
    let minimumThickness: CGFloat
    let maximumThickness: CGFloat
    let transitionCompleted: @MainActor () -> Void

    func makeNSView(context: Context) -> SplitViewItemProbeView {
        SplitViewItemProbeView()
    }

    func updateNSView(_ probeView: SplitViewItemProbeView, context: Context) {
        probeView.update(
            isCollapsed: isCollapsed,
            minimumThickness: minimumThickness,
            maximumThickness: maximumThickness,
            transitionCompleted: transitionCompleted
        )
    }
}

@MainActor
private final class SplitViewItemProbeView: NSView {
    private var desiredCollapsed = false
    private var minimumThickness: CGFloat = 0
    private var maximumThickness: CGFloat = .greatestFiniteMagnitude
    private var transitionCompleted: @MainActor () -> Void = {}
    private weak var configuredItem: NSSplitViewItem?
    private var lastAppliedCollapsed: Bool?
    private var updateGeneration = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleUpdate()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleUpdate()
    }

    func update(
        isCollapsed: Bool,
        minimumThickness: CGFloat,
        maximumThickness: CGFloat,
        transitionCompleted: @escaping @MainActor () -> Void
    ) {
        desiredCollapsed = isCollapsed
        self.minimumThickness = minimumThickness
        self.maximumThickness = maximumThickness
        self.transitionCompleted = transitionCompleted
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        updateGeneration += 1
        let generation = updateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.updateGeneration else { return }
            self.applyUpdate()
        }
    }

    private func applyUpdate() {
        guard let (splitViewItem, splitView) = enclosingSplitViewItem() else {
            return
        }

        if configuredItem !== splitViewItem {
            configuredItem = splitViewItem
            lastAppliedCollapsed = nil
        }

        splitViewItem.canCollapse = true
        splitViewItem.canCollapseFromWindowResize = false
        splitViewItem.minimumThickness = minimumThickness
        splitViewItem.maximumThickness = maximumThickness.isFinite
            ? maximumThickness
            : NSSplitViewItem.unspecifiedDimension
        splitViewItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView

        guard lastAppliedCollapsed != desiredCollapsed else { return }

        let shouldAnimate = lastAppliedCollapsed != nil && splitView.window?.isVisible == true
        lastAppliedCollapsed = desiredCollapsed

        guard shouldAnimate else {
            splitViewItem.isCollapsed = desiredCollapsed
            transitionCompleted()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            splitViewItem.animator().isCollapsed = desiredCollapsed
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.transitionCompleted()
            }
        }
    }

    private func enclosingSplitViewItem() -> (NSSplitViewItem, NSSplitView)? {
        var descendant: NSView = self
        var ancestor = superview

        while let current = ancestor {
            if let splitView = current as? NSSplitView,
               let pane = directChild(of: splitView, containing: descendant),
               let paneIndex = splitView.subviews.firstIndex(of: pane),
               let splitViewController = splitView.delegate as? NSSplitViewController,
               splitViewController.splitViewItems.indices.contains(paneIndex) {
                return (splitViewController.splitViewItems[paneIndex], splitView)
            }
            descendant = current
            ancestor = current.superview
        }

        return nil
    }

    private func directChild(of splitView: NSSplitView, containing descendant: NSView) -> NSView? {
        var candidate: NSView? = descendant
        while let current = candidate, current.superview !== splitView {
            candidate = current.superview
        }
        return candidate
    }
}

nonisolated private struct ColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func captureWidth(
        _ preferredWidth: Binding<Double?>,
        constrainedBy sizing: PanelSizing,
        isEnabled: Bool = true
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ColumnWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ColumnWidthPreferenceKey.self) { width in
            guard isEnabled, width > 0 else { return }
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
            if column.panels.isEmpty {
                emptyDockContent
            } else {
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

    private var emptyDockContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28))
            Text("Dock a panel here")
                .font(.headline)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
            accept(values, before: nil)
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
