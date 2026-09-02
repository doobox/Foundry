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
    @SceneStorage("foundry.workspace.selectedPresetID") private var selectedWorkspaceIDValue = ""
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var presetPendingDeletion: WorkspacePreset?
    @State private var inspectorIsTransitioning = false
    @State private var workspacePresentationID = UUID()

    var body: some View {
        AppKitWorkspaceSplitView(
            layout: $layout,
            showsSidebar: layout.showsSidebar,
            showsInspector: layout.showsInspector,
            toolbarContent: WorkspaceToolbarContent(
                sidebarToggle: AnyView(sidebarToggleButton),
                workspaces: AnyView(workspacePresetsMenu),
                preview: AnyView(previewSiteButton),
                settings: AnyView(projectSettingsButton),
                publish: AnyView(publishButton),
                inspectorToggle: AnyView(inspectorToggleButton)
            ),
            inspectorTransitionCompleted: {
                inspectorIsTransitioning = false
            },
            columnContent: { columnBinding in
                innerColumnView(columnBinding)
            }
        )
        .id(workspacePresentationID)
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: requiredMinimumWidth)
        .alert("Save Workspace As", isPresented: $isNamingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save the current panels, tabs, windows, and column widths.")
        }
        .alert(
            "Delete “\(presetPendingDeletion?.name ?? "Workspace")”?",
            isPresented: Binding(
                get: { presetPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        presetPendingDeletion = nil
                    }
                }
            ),
            presenting: presetPendingDeletion
        ) { preset in
            Button("Delete", role: .destructive) {
                deleteWorkspace(preset.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This workspace arrangement will be permanently deleted.")
        }
        .onChange(of: workspaceLibrary.presets.map(\.id), initial: true) { _, presetIDs in
            if let selectedWorkspaceID, !presetIDs.contains(selectedWorkspaceID) {
                setSelectedWorkspaceID(nil)
            }
        }
        .onAppear {
            restoreInitialWorkspaceSelection()
        }
        .background {
            WindowMinimumContentSize(
                width: requiredMinimumWidth,
                height: EditorWindowSize.minimumHeight
            )
            .frame(width: 0, height: 0)
        }
    }

    private func innerColumnView(_ columnBinding: Binding<WorkspaceColumn>) -> AnyView {
        let column = columnBinding.wrappedValue

        if column.role == .canvas {
            return AnyView(
                FixedCanvasColumn(
                    columnID: column.id,
                    editorOptions: $canvasEditorOptions,
                    viewportWidth: $canvasViewportWidth,
                    screens: canvasScreens,
                    openThemeEditor: openThemeEditor,
                    dockBeside: dockBeside,
                    content: { panelContent(.canvas) }
                )
            )
        }

        return AnyView(
            WorkspaceColumnView(
                column: columnBinding,
                usesSidebarMaterial: column.role == .sidebarDock,
                canMoveSelectedTabToNewColumn: column.panels.count > 1 || column.role.isPersistentDock,
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
        )
    }

    private var requiredMinimumWidth: CGFloat {
        let visibleColumns = layout.columns.filter { column in
            switch column.role {
            case .sidebarDock:
                layout.showsSidebar
            case .inspectorDock:
                layout.showsInspector
            case .workspace, .canvas:
                true
            }
        }
        return max(EditorWindowSize.minimumWidth, minimumWidth(for: visibleColumns))
    }

    private func minimumWidth(for columns: [WorkspaceColumn]) -> CGFloat {
        let splitDividerWidth: CGFloat = 10
        let columnWidths = columns.reduce(CGFloat.zero) { width, column in
            width + sizing(for: column).minimum
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
            layout.showsInspector.toggle()
        } label: {
            Label("Toggle Inspector", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
        }
        .help(layout.showsInspector ? "Hide Inspector" : "Show Inspector")
    }

    private var sidebarToggleButton: some View {
        Button {
            layout.showsSidebar.toggle()
        } label: {
            Label("Toggle Sidebar", systemImage: "sidebar.leading")
                .labelStyle(.iconOnly)
        }
        .help(layout.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
    }

    private var previewSiteButton: some View {
        Button("Preview Site", systemImage: "safari", action: previewSite)
            .labelStyle(.iconOnly)
            .help("Generate and open a production preview")
    }

    private var projectSettingsButton: some View {
        Button {
            openProjectSettings()
        } label: {
            Label("Project Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .help("Open project settings")
    }

    private var publishButton: some View {
        Button {
            publishSite()
        } label: {
            Label("Publish", systemImage: "cloud")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 5)
        }
        .buttonStyle(.bordered)
        .help("Publish site")
    }

    private var workspacePresetsMenu: some View {
        Menu("Workspaces", systemImage: "rectangle.split.3x1") {
            Toggle(
                "Default Workspace",
                isOn: Binding(
                    get: { selectedWorkspaceID == nil },
                    set: { _ in
                        layout.reset()
                        setSelectedWorkspaceID(nil)
                        workspacePresentationID = UUID()
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
                            set: { _ in
                                applyWorkspacePreset(preset.id)
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

            if let selectedWorkspacePreset {
                Divider()
                Button("Delete “\(selectedWorkspacePreset.name)”…", role: .destructive) {
                    presetPendingDeletion = selectedWorkspacePreset
                }
            }
        }
        .menuIndicator(.hidden)
        .help("Save or restore a workspace arrangement")
    }

    private var suggestedWorkspaceName: String {
        if let preset = selectedWorkspacePreset {
            return preset.name
        }
        return "Workspace \(workspaceLibrary.presets.count + 1)"
    }

    private var selectedWorkspacePreset: WorkspacePreset? {
        guard let selectedWorkspaceID else { return nil }
        return workspaceLibrary.presets.first(where: { $0.id == selectedWorkspaceID })
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

    private func deleteWorkspace(_ id: UUID) {
        workspaceLibrary.delete(id)
        if selectedWorkspaceID == id {
            setSelectedWorkspaceID(nil)
        }
    }

    private func applyWorkspacePreset(_ id: UUID) {
        guard let preset = workspaceLibrary.presets.first(where: { $0.id == id }) else { return }
        layout = preset.layout
        setSelectedWorkspaceID(id)
        workspacePresentationID = UUID()
    }

    private func restoreInitialWorkspaceSelection() {
        guard selectedWorkspaceID == nil,
              let lastSelectedID = WorkspaceSelectionStore.restored(),
              workspaceLibrary.presets.contains(where: { $0.id == lastSelectedID }) else {
            return
        }
        selectedWorkspaceIDValue = lastSelectedID.uuidString
    }

    private var selectedWorkspaceID: UUID? {
        UUID(uuidString: selectedWorkspaceIDValue)
    }

    private func setSelectedWorkspaceID(_ id: UUID?) {
        selectedWorkspaceIDValue = id?.uuidString ?? ""
        WorkspaceSelectionStore.persist(id)
    }
}

private struct WorkspaceToolbarContent {
    let sidebarToggle: AnyView
    let workspaces: AnyView
    let preview: AnyView
    let settings: AnyView
    let publish: AnyView
    let inspectorToggle: AnyView
}

private struct AppKitWorkspaceSplitView: NSViewControllerRepresentable {
    @Binding var layout: WorkspaceLayout
    let showsSidebar: Bool
    let showsInspector: Bool
    let toolbarContent: WorkspaceToolbarContent
    let inspectorTransitionCompleted: @MainActor () -> Void
    let columnContent: @MainActor (Binding<WorkspaceColumn>) -> AnyView

    func makeNSViewController(context: Context) -> AppKitWorkspaceSplitViewController {
        AppKitWorkspaceSplitViewController()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: AppKitWorkspaceSplitViewController,
        context: Context
    ) -> CGSize? {
        let currentSize = nsViewController.view.bounds.size
        let width = proposal.width ?? currentSize.width
        let height = proposal.height ?? currentSize.height

        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateNSViewController(
        _ splitViewController: AppKitWorkspaceSplitViewController,
        context: Context
    ) {
        let layoutBinding = $layout
        let contentBuilder = columnContent
        let transitionCompleted = inspectorTransitionCompleted
        let columns = layout.columns

        splitViewController.update(
            columns: columns,
            showsSidebar: showsSidebar,
            showsInspector: showsInspector,
            toolbarContent: toolbarContent,
            content: { columnID in
                let fallback = columns.first(where: { $0.id == columnID })
                    ?? WorkspaceColumn(role: .workspace, panels: [])
                let columnBinding = Binding<WorkspaceColumn>(
                    get: {
                        layoutBinding.wrappedValue.columns.first(where: { $0.id == columnID })
                            ?? fallback
                    },
                    set: { updatedColumn in
                        guard let index = layoutBinding.wrappedValue.columns.firstIndex(
                            where: { $0.id == columnID }
                        ) else { return }
                        layoutBinding.wrappedValue.columns[index] = updatedColumn
                    }
                )
                return contentBuilder(columnBinding)
            },
            preferredWidthChanged: { columnID, width in
                guard let index = layoutBinding.wrappedValue.columns.firstIndex(
                    where: { $0.id == columnID }
                ) else { return }
                layoutBinding.wrappedValue.columns[index].preferredWidth = Double(width)
            },
            inspectorTransitionCompleted: transitionCompleted
        )
    }
}

@MainActor
private final class AppKitWorkspaceSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private struct OuterEntry {
        let id: UUID
        let role: WorkspaceColumnRole
        let hostingController: NSHostingController<AnyView>
        let splitViewItem: NSSplitViewItem
        var sizing: PanelSizing
        var preferredWidth: CGFloat
    }

    private enum ToolbarIdentifier {
        static let toolbar = NSToolbar.Identifier("foundry.editor.toolbar")
        static let sidebarToggle = NSToolbarItem.Identifier("foundry.toolbar.sidebar-toggle")
        static let leadingSeparator = NSToolbarItem.Identifier("foundry.toolbar.sidebar-separator")
        static let workspaces = NSToolbarItem.Identifier("foundry.toolbar.workspaces")
        static let preview = NSToolbarItem.Identifier("foundry.toolbar.preview")
        static let trailingSeparator = NSToolbarItem.Identifier("foundry.toolbar.inspector-separator")
        static let settings = NSToolbarItem.Identifier("foundry.toolbar.settings")
        static let publish = NSToolbarItem.Identifier("foundry.toolbar.publish")
        static let inspectorToggle = NSToolbarItem.Identifier("foundry.toolbar.inspector-toggle")
    }

    private let detailSplitViewController = AppKitDetailSplitViewController()
    private lazy var detailContainerController = AppKitDetailContainerViewController(
        detailSplitViewController: detailSplitViewController
    )
    private var sidebarEntry: OuterEntry?
    private var inspectorEntry: OuterEntry?
    private var detailSplitViewItem: NSSplitViewItem?
    private var preferredWidthChanged: (UUID, CGFloat) -> Void = { _, _ in }
    private var inspectorTransitionCompleted: () -> Void = {}
    private var toolbarContent: WorkspaceToolbarContent?
    private var toolbarHostingViews: [NSToolbarItem.Identifier: NSHostingView<AnyView>] = [:]
    private var activeDividerIndex: Int?
    private var dividerCommitTask: Task<Void, Never>?
    private var widthApplicationGeneration = 0
    private var visibilityUpdateGeneration = 0
    private var needsInitialWidthApplication = false
    private var isApplyingInitialWidths = false
    private var lastShowsSidebar: Bool?
    private var lastShowsInspector: Bool?

    private lazy var editorToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: ToolbarIdentifier.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .default
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installWindowToolbarIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        installWindowToolbarIfNeeded()
        guard needsInitialWidthApplication else { return }
        needsInitialWidthApplication = false
        scheduleInitialWidths()
    }

    deinit {
        dividerCommitTask?.cancel()
    }

    func update(
        columns: [WorkspaceColumn],
        showsSidebar: Bool,
        showsInspector: Bool,
        toolbarContent: WorkspaceToolbarContent,
        content: (UUID) -> AnyView,
        preferredWidthChanged: @escaping (UUID, CGFloat) -> Void,
        inspectorTransitionCompleted: @escaping () -> Void
    ) {
        loadViewIfNeeded()
        self.preferredWidthChanged = preferredWidthChanged
        self.inspectorTransitionCompleted = inspectorTransitionCompleted
        self.toolbarContent = toolbarContent
        updateToolbarHostingViews()

        guard let sidebar = columns.first(where: { $0.role == .sidebarDock }),
              let inspector = columns.first(where: { $0.role == .inspectorDock }) else {
            return
        }
        let detailColumns = columns.filter { $0.role == .workspace || $0.role == .canvas }

        if sidebarEntry?.id != sidebar.id || inspectorEntry?.id != inspector.id {
            rebuildOuterSplit(
                sidebar: sidebar,
                inspector: inspector,
                detailColumns: detailColumns,
                showsSidebar: showsSidebar,
                showsInspector: showsInspector,
                content: content
            )
        } else {
            updateOuterEntries(
                sidebar: sidebar,
                inspector: inspector,
                detailColumns: detailColumns,
                content: content
            )
            scheduleVisibilityUpdate(
                showsSidebar: showsSidebar,
                showsInspector: showsInspector
            )
        }

        detailSplitViewController.update(
            columns: detailColumns,
            showsSidebar: true,
            showsInspector: true,
            content: content,
            preferredWidthChanged: preferredWidthChanged,
            inspectorTransitionCompleted: {}
        )
    }

    private func rebuildOuterSplit(
        sidebar: WorkspaceColumn,
        inspector: WorkspaceColumn,
        detailColumns: [WorkspaceColumn],
        showsSidebar: Bool,
        showsInspector: Bool,
        content: (UUID) -> AnyView
    ) {
        widthApplicationGeneration += 1
        activeDividerIndex = nil
        dividerCommitTask?.cancel()
        dividerCommitTask = nil

        for item in splitViewItems.reversed() {
            removeSplitViewItem(item)
        }

        let sidebarSizing = sizing(for: sidebar)
        let sidebarPreferredWidth = preferredWidth(for: sidebar, sizing: sidebarSizing)
        let sidebarHostingController = NSHostingController(rootView: hostedRootView(content(sidebar.id)))
        sidebarHostingController.sizingOptions = []
        sidebarHostingController.view.frame.size.width = sidebarPreferredWidth
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHostingController)
        sidebarEntry = OuterEntry(
            id: sidebar.id,
            role: .sidebarDock,
            hostingController: sidebarHostingController,
            splitViewItem: sidebarItem,
            sizing: sidebarSizing,
            preferredWidth: sidebarPreferredWidth
        )

        let detailItem = NSSplitViewItem(viewController: detailContainerController)
        detailSplitViewItem = detailItem

        let inspectorSizing = sizing(for: inspector)
        let inspectorPreferredWidth = preferredWidth(for: inspector, sizing: inspectorSizing)
        let inspectorHostingController = NSHostingController(rootView: hostedRootView(content(inspector.id)))
        inspectorHostingController.sizingOptions = []
        inspectorHostingController.view.frame.size.width = inspectorPreferredWidth
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHostingController)
        inspectorEntry = OuterEntry(
            id: inspector.id,
            role: .inspectorDock,
            hostingController: inspectorHostingController,
            splitViewItem: inspectorItem,
            sizing: inspectorSizing,
            preferredWidth: inspectorPreferredWidth
        )

        configureOuterItems(detailColumns: detailColumns)
        sidebarItem.isCollapsed = !showsSidebar
        inspectorItem.isCollapsed = !showsInspector
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        addSplitViewItem(inspectorItem)
        sidebarItem.isCollapsed = !showsSidebar
        inspectorItem.isCollapsed = !showsInspector

        lastShowsSidebar = showsSidebar
        lastShowsInspector = showsInspector
        needsInitialWidthApplication = true
        view.needsLayout = true
        installWindowToolbarIfNeeded()
    }

    private func updateOuterEntries(
        sidebar: WorkspaceColumn,
        inspector: WorkspaceColumn,
        detailColumns: [WorkspaceColumn],
        content: (UUID) -> AnyView
    ) {
        if var entry = sidebarEntry {
            entry.sizing = sizing(for: sidebar)
            entry.preferredWidth = preferredWidth(for: sidebar, sizing: entry.sizing)
            entry.hostingController.rootView = hostedRootView(content(sidebar.id))
            sidebarEntry = entry
        }
        if var entry = inspectorEntry {
            entry.sizing = sizing(for: inspector)
            entry.preferredWidth = preferredWidth(for: inspector, sizing: entry.sizing)
            entry.hostingController.rootView = hostedRootView(content(inspector.id))
            inspectorEntry = entry
        }
        configureOuterItems(detailColumns: detailColumns)
    }

    private func configureOuterItems(detailColumns: [WorkspaceColumn]) {
        if let sidebarEntry {
            configurePersistentDock(sidebarEntry)
        }
        if let inspectorEntry {
            configurePersistentDock(inspectorEntry)
        }
        if let detailSplitViewItem {
            detailSplitViewItem.minimumThickness = minimumWidth(for: detailColumns)
            detailSplitViewItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
            detailSplitViewItem.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
            detailSplitViewItem.holdingPriority = .defaultLow
        }
    }

    private func configurePersistentDock(_ entry: OuterEntry) {
        let item = entry.splitViewItem
        item.minimumThickness = entry.sizing.minimum
        item.maximumThickness = entry.sizing.maximum.isFinite
            ? entry.sizing.maximum
            : NSSplitViewItem.unspecifiedDimension
        item.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
        item.holdingPriority = NSLayoutConstraint.Priority(rawValue: 489)
        item.canCollapse = true
        item.canCollapseFromWindowResize = false
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
    }

    private func minimumWidth(for columns: [WorkspaceColumn]) -> CGFloat {
        let paneWidths = columns.reduce(CGFloat.zero) { $0 + sizing(for: $1).minimum }
        let dividers = CGFloat(max(columns.count - 1, 0)) * splitView.dividerThickness
        return paneWidths + dividers
    }

    private func scheduleInitialWidths() {
        widthApplicationGeneration += 1
        let generation = widthApplicationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, generation == self.widthApplicationGeneration else { return }
            self.applyInitialWidths()
        }
    }

    private func applyInitialWidths() {
        guard splitView.arrangedSubviews.count == 3,
              let sidebarEntry,
              let inspectorEntry,
              let detailSplitViewItem else {
            return
        }

        let dividerSpace = splitView.dividerThickness * 2
        let availableWidth = max(splitView.bounds.width - dividerSpace, 0)
        let detailMinimum = detailSplitViewItem.minimumThickness
        var sidebarWidth = sidebarEntry.splitViewItem.isCollapsed ? 0 : sidebarEntry.preferredWidth
        var inspectorWidth = inspectorEntry.splitViewItem.isCollapsed ? 0 : inspectorEntry.preferredWidth
        let panelIdealTotal = sidebarWidth + inspectorWidth
        let panelMinimumTotal = (sidebarEntry.splitViewItem.isCollapsed ? 0 : sidebarEntry.sizing.minimum)
            + (inspectorEntry.splitViewItem.isCollapsed ? 0 : inspectorEntry.sizing.minimum)
        let availablePanelWidth = max(availableWidth - detailMinimum, 0)

        if panelIdealTotal > availablePanelWidth {
            let capacity = panelIdealTotal - panelMinimumTotal
            let shortage = panelIdealTotal - availablePanelWidth
            let fraction = capacity > 0 ? min(shortage / capacity, 1) : 1
            if !sidebarEntry.splitViewItem.isCollapsed {
                sidebarWidth -= (sidebarEntry.preferredWidth - sidebarEntry.sizing.minimum) * fraction
            }
            if !inspectorEntry.splitViewItem.isCollapsed {
                inspectorWidth -= (inspectorEntry.preferredWidth - inspectorEntry.sizing.minimum) * fraction
            }
        }

        isApplyingInitialWidths = true
        defer { isApplyingInitialWidths = false }
        splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        splitView.setPosition(splitView.bounds.width - inspectorWidth, ofDividerAt: 1)
    }

    private func scheduleVisibilityUpdate(showsSidebar: Bool, showsInspector: Bool) {
        visibilityUpdateGeneration += 1
        let generation = visibilityUpdateGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, generation == self.visibilityUpdateGeneration else { return }
            self.updateSidebarVisibility(showsSidebar, animated: true)
            self.updateInspectorVisibility(showsInspector, animated: true)
        }
    }

    private func updateSidebarVisibility(_ showsSidebar: Bool, animated: Bool) {
        guard let sidebarEntry else {
            lastShowsSidebar = showsSidebar
            return
        }
        let visibilityChanged = lastShowsSidebar != showsSidebar
        guard visibilityChanged || sidebarEntry.splitViewItem.isCollapsed == showsSidebar else { return }
        let shouldAnimate = animated && visibilityChanged && lastShowsSidebar != nil
            && view.window?.isVisible == true
        lastShowsSidebar = showsSidebar
        guard shouldAnimate else {
            sidebarEntry.splitViewItem.isCollapsed = !showsSidebar
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            sidebarEntry.splitViewItem.animator().isCollapsed = !showsSidebar
        }
    }

    private func updateInspectorVisibility(_ showsInspector: Bool, animated: Bool) {
        guard let inspectorEntry else {
            lastShowsInspector = showsInspector
            return
        }
        let visibilityChanged = lastShowsInspector != showsInspector
        guard visibilityChanged || inspectorEntry.splitViewItem.isCollapsed == showsInspector else { return }
        let shouldAnimate = animated && visibilityChanged && lastShowsInspector != nil
            && view.window?.isVisible == true
        lastShowsInspector = showsInspector
        guard shouldAnimate else {
            inspectorEntry.splitViewItem.isCollapsed = !showsInspector
            inspectorTransitionCompleted()
            return
        }
        let transitionCompleted = inspectorTransitionCompleted
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            inspectorEntry.splitViewItem.animator().isCollapsed = !showsInspector
        } completionHandler: {
            Task { @MainActor in
                transitionCompleted()
            }
        }
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard !isApplyingInitialWidths,
              NSEvent.pressedMouseButtons & 1 == 1 else {
            return proposedPosition
        }
        activeDividerIndex = dividerIndex
        scheduleDividerWidthCommit()
        return proposedPosition
    }

    private func scheduleDividerWidthCommit() {
        dividerCommitTask?.cancel()
        dividerCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 1 {
                self.scheduleDividerWidthCommit()
            } else {
                self.finishDividerDrag()
            }
        }
    }

    private func finishDividerDrag() {
        defer {
            activeDividerIndex = nil
            dividerCommitTask = nil
        }
        guard let dividerIndex = activeDividerIndex else { return }

        if dividerIndex == 0,
           var sidebarEntry,
           !sidebarEntry.splitViewItem.isCollapsed {
            let width = constrained(splitView.arrangedSubviews[0].frame.width, for: sidebarEntry.sizing)
            sidebarEntry.preferredWidth = width
            self.sidebarEntry = sidebarEntry
            preferredWidthChanged(sidebarEntry.id, width)
        } else if dividerIndex == 1,
                  var inspectorEntry,
                  !inspectorEntry.splitViewItem.isCollapsed {
            let width = constrained(splitView.arrangedSubviews[2].frame.width, for: inspectorEntry.sizing)
            inspectorEntry.preferredWidth = width
            self.inspectorEntry = inspectorEntry
            preferredWidthChanged(inspectorEntry.id, width)
        }
    }

    private func constrained(_ width: CGFloat, for sizing: PanelSizing) -> CGFloat {
        min(max(width, sizing.minimum), sizing.maximum)
    }

    private func installWindowToolbarIfNeeded() {
        guard splitViewItems.count == 3,
              toolbarContent != nil,
              let window = view.window else {
            return
        }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        if window.toolbar !== editorToolbar {
            window.toolbar = editorToolbar
        }
    }

    private func updateToolbarHostingViews() {
        for (identifier, hostingView) in toolbarHostingViews {
            guard let content = toolbarView(for: identifier) else { continue }
            hostingView.rootView = content
        }
    }

    private func toolbarView(for identifier: NSToolbarItem.Identifier) -> AnyView? {
        guard let toolbarContent else { return nil }
        switch identifier {
        case ToolbarIdentifier.sidebarToggle: return toolbarContent.sidebarToggle
        case ToolbarIdentifier.workspaces: return toolbarContent.workspaces
        case ToolbarIdentifier.preview: return toolbarContent.preview
        case ToolbarIdentifier.settings: return toolbarContent.settings
        case ToolbarIdentifier.publish: return toolbarContent.publish
        case ToolbarIdentifier.inspectorToggle: return toolbarContent.inspectorToggle
        default: return nil
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarIdentifier.sidebarToggle,
            ToolbarIdentifier.leadingSeparator,
            ToolbarIdentifier.workspaces,
            ToolbarIdentifier.preview,
            .flexibleSpace,
            ToolbarIdentifier.trailingSeparator,
            .flexibleSpace,
            ToolbarIdentifier.settings,
            ToolbarIdentifier.publish,
            ToolbarIdentifier.inspectorToggle
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarIdentifier.leadingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )
        case ToolbarIdentifier.trailingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )
        default:
            guard let content = toolbarView(for: itemIdentifier) else { return nil }
            let hostingView = NSHostingView(rootView: content)
            toolbarHostingViews[itemIdentifier] = hostingView
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = hostingView
            item.visibilityPriority = itemIdentifier == ToolbarIdentifier.inspectorToggle
                || itemIdentifier == ToolbarIdentifier.sidebarToggle
                ? .user
                : .standard
            return item
        }
    }

    private func sizing(for column: WorkspaceColumn) -> PanelSizing {
        guard !column.panels.isEmpty else {
            switch column.role {
            case .sidebarDock: return PanelSizing(panel: .pages)
            case .inspectorDock: return PanelSizing(panel: .inspector)
            case .canvas: return PanelSizing(panel: .canvas)
            case .workspace: return .zero
            }
        }
        return column.panels.map(PanelSizing.init).reduce(.zero) { $0.combined(with: $1) }
    }

    private func preferredWidth(for column: WorkspaceColumn, sizing: PanelSizing) -> CGFloat {
        guard let preferredWidth = column.preferredWidth else { return sizing.ideal }
        return constrained(CGFloat(preferredWidth), for: sizing)
    }

    private func hostedRootView(_ content: AnyView) -> AnyView {
        AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity))
    }
}

@MainActor
private final class AppKitDetailContainerViewController: NSViewController {
    private let detailSplitViewController: AppKitDetailSplitViewController

    init(detailSplitViewController: AppKitDetailSplitViewController) {
        self.detailSplitViewController = detailSplitViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let containerView = NSView()
        containerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        containerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view = containerView

        addChild(detailSplitViewController)
        let detailView = detailSplitViewController.view
        detailView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailView)
        NSLayoutConstraint.activate([
            detailView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            detailView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            detailView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            detailView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
}

@MainActor
private final class AppKitDetailSplitViewController: NSSplitViewController {
    private struct Entry {
        let id: UUID
        var role: WorkspaceColumnRole
        let hostingController: NSHostingController<AnyView>
        let splitViewItem: NSSplitViewItem
        var sizing: PanelSizing
        var preferredWidth: CGFloat
    }

    private var entries: [Entry] = []
    private var preferredWidthChanged: (UUID, CGFloat) -> Void = { _, _ in }
    private var inspectorTransitionCompleted: () -> Void = {}
    private var lastShowsSidebar: Bool?
    private var lastShowsInspector: Bool?
    private var activeDividerIndex: Int?
    private var dividerCommitTask: Task<Void, Never>?
    private var widthApplicationGeneration = 0
    private var visibilityUpdateGeneration = 0
    private var needsInitialWidthApplication = false
    private var isApplyingInitialWidths = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard needsInitialWidthApplication else { return }
        needsInitialWidthApplication = false
        scheduleInitialWidths()
    }

    deinit {
        dividerCommitTask?.cancel()
    }

    func update(
        columns: [WorkspaceColumn],
        showsSidebar: Bool,
        showsInspector: Bool,
        content: (UUID) -> AnyView,
        preferredWidthChanged: @escaping (UUID, CGFloat) -> Void,
        inspectorTransitionCompleted: @escaping () -> Void
    ) {
        loadViewIfNeeded()
        self.preferredWidthChanged = preferredWidthChanged
        self.inspectorTransitionCompleted = inspectorTransitionCompleted

        let needsRebuild = entries.map(\.id) != columns.map(\.id)
        if needsRebuild {
            rebuild(
                columns: columns,
                showsSidebar: showsSidebar,
                showsInspector: showsInspector,
                content: content
            )
            return
        }

        for index in entries.indices {
            let column = columns[index]
            entries[index].role = column.role
            entries[index].sizing = sizing(for: column)
            entries[index].preferredWidth = preferredWidth(for: column, sizing: entries[index].sizing)
            entries[index].hostingController.rootView = hostedRootView(content(column.id))
            configureSplitViewItem(at: index)
        }

        scheduleVisibilityUpdate(
            showsSidebar: showsSidebar,
            showsInspector: showsInspector
        )
    }

    private func rebuild(
        columns: [WorkspaceColumn],
        showsSidebar: Bool,
        showsInspector: Bool,
        content: (UUID) -> AnyView
    ) {
        widthApplicationGeneration += 1
        activeDividerIndex = nil
        dividerCommitTask?.cancel()
        dividerCommitTask = nil

        for item in splitViewItems.reversed() {
            removeSplitViewItem(item)
        }
        entries.removeAll(keepingCapacity: true)

        for column in columns {
            let hostingController = NSHostingController(rootView: hostedRootView(content(column.id)))
            hostingController.sizingOptions = []
            let item: NSSplitViewItem
            switch column.role {
            case .sidebarDock:
                item = NSSplitViewItem(sidebarWithViewController: hostingController)
            case .inspectorDock:
                item = NSSplitViewItem(inspectorWithViewController: hostingController)
            case .workspace, .canvas:
                item = NSSplitViewItem(viewController: hostingController)
            }
            let panelSizing = sizing(for: column)
            let panelPreferredWidth = preferredWidth(for: column, sizing: panelSizing)
            hostingController.view.frame.size.width = panelPreferredWidth
            entries.append(
                Entry(
                    id: column.id,
                    role: column.role,
                    hostingController: hostingController,
                    splitViewItem: item,
                    sizing: panelSizing,
                    preferredWidth: panelPreferredWidth
                )
            )
            configureSplitViewItem(at: entries.index(before: entries.endIndex))
            if column.role == .sidebarDock {
                item.isCollapsed = !showsSidebar
            } else if column.role == .inspectorDock {
                item.isCollapsed = !showsInspector
            }
            addSplitViewItem(item)
        }

        lastShowsSidebar = showsSidebar
        lastShowsInspector = showsInspector
        needsInitialWidthApplication = true
        view.needsLayout = true
    }

    private func configureSplitViewItem(at index: Int) {
        let entry = entries[index]
        let item = entry.splitViewItem
        item.minimumThickness = entry.sizing.minimum
        item.maximumThickness = entry.sizing.maximum.isFinite
            ? entry.sizing.maximum
            : NSSplitViewItem.unspecifiedDimension
        item.holdingPriority = entry.role == .canvas
            ? .defaultLow
            : NSLayoutConstraint.Priority(rawValue: 489)
        item.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension

        if entry.role == .sidebarDock || entry.role == .inspectorDock {
            item.canCollapse = true
            item.canCollapseFromWindowResize = false
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        }
    }

    private func updateSidebarVisibility(_ showsSidebar: Bool, animated: Bool) {
        guard let sidebar = entries.first(where: { $0.role == .sidebarDock }) else {
            lastShowsSidebar = showsSidebar
            return
        }
        let visibilityChanged = lastShowsSidebar != showsSidebar
        guard visibilityChanged || sidebar.splitViewItem.isCollapsed == showsSidebar else { return }
        let shouldAnimate = animated && visibilityChanged && lastShowsSidebar != nil
            && view.window?.isVisible == true
        lastShowsSidebar = showsSidebar

        guard shouldAnimate else {
            sidebar.splitViewItem.isCollapsed = !showsSidebar
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            sidebar.splitViewItem.animator().isCollapsed = !showsSidebar
        }
    }

    private func scheduleVisibilityUpdate(showsSidebar: Bool, showsInspector: Bool) {
        visibilityUpdateGeneration += 1
        let generation = visibilityUpdateGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, generation == self.visibilityUpdateGeneration else { return }
            self.updateSidebarVisibility(showsSidebar, animated: true)
            self.updateInspectorVisibility(showsInspector, animated: true)
        }
    }

    private func updateInspectorVisibility(_ showsInspector: Bool, animated: Bool) {
        guard let inspector = entries.first(where: { $0.role == .inspectorDock }) else {
            lastShowsInspector = showsInspector
            return
        }
        let visibilityChanged = lastShowsInspector != showsInspector
        guard visibilityChanged || inspector.splitViewItem.isCollapsed == showsInspector else { return }
        let shouldAnimate = animated && visibilityChanged && lastShowsInspector != nil
            && view.window?.isVisible == true
        lastShowsInspector = showsInspector

        guard shouldAnimate else {
            inspector.splitViewItem.isCollapsed = !showsInspector
            inspectorTransitionCompleted()
            return
        }

        let transitionCompleted = inspectorTransitionCompleted
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            inspector.splitViewItem.animator().isCollapsed = !showsInspector
        } completionHandler: {
            Task { @MainActor in
                transitionCompleted()
            }
        }
    }

    private func scheduleInitialWidths() {
        widthApplicationGeneration += 1
        let generation = widthApplicationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self, generation == self.widthApplicationGeneration else { return }
            self.applyInitialWidths()
        }
    }

    private func applyInitialWidths() {
        guard entries.count == splitView.arrangedSubviews.count,
              let canvasIndex = entries.firstIndex(where: { $0.role == .canvas }) else {
            return
        }
        let totalPaneWidth = splitView.arrangedSubviews.reduce(CGFloat.zero) { $0 + $1.frame.width }
        let dividerSpace = max(splitView.bounds.width - totalPaneWidth, 0)
        let availableWidth = max(splitView.bounds.width - dividerSpace, 0)
        guard availableWidth > 0 else { return }

        var targets = Array(repeating: CGFloat.zero, count: entries.count)
        var resizablePanelIndices: [Int] = []
        var panelIdealTotal: CGFloat = 0
        var panelMinimumTotal: CGFloat = 0

        for index in entries.indices where index != canvasIndex {
            let entry = entries[index]
            guard !entry.splitViewItem.isCollapsed else { continue }
            targets[index] = entry.preferredWidth
            resizablePanelIndices.append(index)
            panelIdealTotal += entry.preferredWidth
            panelMinimumTotal += entry.sizing.minimum
        }

        let canvasMinimum = entries[canvasIndex].sizing.minimum
        let panelSpace = max(availableWidth - canvasMinimum, 0)
        if panelIdealTotal > panelSpace {
            let capacity = panelIdealTotal - panelMinimumTotal
            let shortage = panelIdealTotal - panelSpace
            let fraction = capacity > 0 ? min(shortage / capacity, 1) : 1
            for index in resizablePanelIndices {
                let entry = entries[index]
                targets[index] -= (entry.preferredWidth - entry.sizing.minimum) * fraction
            }
        }

        let allocatedPanels = resizablePanelIndices.reduce(CGFloat.zero) { $0 + targets[$1] }
        targets[canvasIndex] = max(availableWidth - allocatedPanels, canvasMinimum)

        isApplyingInitialWidths = true
        defer { isApplyingInitialWidths = false }

        let dividerThickness = entries.count > 1
            ? dividerSpace / CGFloat(entries.count - 1)
            : 0
        var position = splitView.bounds.minX
        for dividerIndex in 0..<max(entries.count - 1, 0) {
            position += targets[dividerIndex]
            splitView.setPosition(position, ofDividerAt: dividerIndex)
            position += dividerThickness
        }
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard !isApplyingInitialWidths,
              NSEvent.pressedMouseButtons & 1 == 1 else {
            return proposedPosition
        }
        activeDividerIndex = dividerIndex
        scheduleDividerWidthCommit()
        return proposedPosition
    }

    private func scheduleDividerWidthCommit() {
        dividerCommitTask?.cancel()
        dividerCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 1 {
                self.scheduleDividerWidthCommit()
            } else {
                self.finishDividerDrag()
            }
        }
    }

    private func finishDividerDrag() {
        defer {
            activeDividerIndex = nil
            dividerCommitTask = nil
        }
        guard let dividerIndex = activeDividerIndex else { return }

        for index in [dividerIndex, dividerIndex + 1] where entries.indices.contains(index) {
            guard entries[index].role != .canvas,
                  !entries[index].splitViewItem.isCollapsed else {
                continue
            }
            let width = min(
                max(splitView.arrangedSubviews[index].frame.width, entries[index].sizing.minimum),
                entries[index].sizing.maximum
            )
            entries[index].preferredWidth = width
            preferredWidthChanged(entries[index].id, width)
        }
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

    private func hostedRootView(_ content: AnyView) -> AnyView {
        AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity))
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

        let contentBounds = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let layoutSize = window.contentLayoutRect.size
        let windowChrome = NSSize(
            width: max(contentBounds.width - layoutSize.width, 0),
            height: max(contentBounds.height - layoutSize.height, 0)
        )
        let effectiveContentMinimum = NSSize(
            width: minimumContentSize.width + windowChrome.width,
            height: minimumContentSize.height + windowChrome.height
        )

        if abs(window.contentMinSize.width - effectiveContentMinimum.width) > 0.5
            || abs(window.contentMinSize.height - effectiveContentMinimum.height) > 0.5 {
            window.contentMinSize = effectiveContentMinimum
        }

        let missingWidth = max(minimumContentSize.width - layoutSize.width, 0)
        let missingHeight = max(minimumContentSize.height - layoutSize.height, 0)
        guard missingWidth > 0.5 || missingHeight > 0.5 else {
            return
        }

        let currentFrame = window.frame
        var targetFrame = currentFrame
        targetFrame.size.width += missingWidth
        targetFrame.size.height += missingHeight
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if let visibleFrame = window.screen?.visibleFrame {
            targetFrame.origin.x = min(
                max(targetFrame.minX, visibleFrame.minX),
                max(visibleFrame.maxX - targetFrame.width, visibleFrame.minX)
            )
            targetFrame.origin.y = max(targetFrame.minY, visibleFrame.minY)
        }

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
    let transitionCompleted: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> SplitViewItemProbeView {
        SplitViewItemProbeView()
    }

    func updateNSView(_ probeView: SplitViewItemProbeView, context: Context) {
        probeView.update(
            isCollapsed: isCollapsed,
            minimumThickness: minimumThickness,
            maximumThickness: maximumThickness,
            transitionCompleted: { transitionCompleted() }
        )
    }
}

@MainActor
private final class SplitViewItemProbeView: NSView {
    private var desiredCollapsed = false
    private var minimumThickness: CGFloat = 0
    private var maximumThickness: CGFloat = .greatestFiniteMagnitude
    private var transitionCompleted: @MainActor @Sendable () -> Void = {}
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
        transitionCompleted: @escaping @MainActor @Sendable () -> Void
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

        let transitionCompleted = transitionCompleted
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            splitViewItem.animator().isCollapsed = desiredCollapsed
        } completionHandler: {
            Task { @MainActor in
                transitionCompleted()
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

private extension View {
    func captureWidth(
        _ preferredWidth: Binding<Double?>,
        constrainedBy sizing: PanelSizing,
        isEnabled: Bool = true
    ) -> some View {
        background {
            SplitPaneBehaviorController(
                holdingPriority: NSLayoutConstraint.Priority(rawValue: 489),
                capturesDirectDividerResizes: isEnabled,
                widthChanged: { width in
                    let constrainedWidth = min(max(width, sizing.minimum), sizing.maximum)
                    if abs((preferredWidth.wrappedValue ?? 0) - Double(constrainedWidth)) > 1 {
                        preferredWidth.wrappedValue = Double(constrainedWidth)
                    }
                }
            )
            .frame(width: 0, height: 0)
        }
    }

    func splitPaneHoldingPriority(_ priority: NSLayoutConstraint.Priority) -> some View {
        background {
            SplitPaneBehaviorController(
                holdingPriority: priority,
                capturesDirectDividerResizes: false,
                widthChanged: { _ in }
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct SplitPaneBehaviorController: NSViewRepresentable {
    let holdingPriority: NSLayoutConstraint.Priority
    let capturesDirectDividerResizes: Bool
    let widthChanged: @MainActor @Sendable (CGFloat) -> Void

    func makeNSView(context: Context) -> SplitPaneBehaviorProbeView {
        SplitPaneBehaviorProbeView()
    }

    func updateNSView(_ probeView: SplitPaneBehaviorProbeView, context: Context) {
        probeView.update(
            holdingPriority: holdingPriority,
            capturesDirectDividerResizes: capturesDirectDividerResizes,
            widthChanged: { width in
                widthChanged(width)
            }
        )
    }
}

private final class SplitPaneBehaviorProbeView: NSView {
    private var holdingPriority: NSLayoutConstraint.Priority = .defaultLow
    private var capturesDirectDividerResizes = false
    private var widthChanged: @MainActor @Sendable (CGFloat) -> Void = { _ in }
    private weak var configuredItem: NSSplitViewItem?
    private weak var observedSplitView: NSSplitView?
    private weak var observedPane: NSView?
    private var observedPaneIndex = 0
    private var resizeObserver: NSObjectProtocol?
    private var mouseUpMonitor: Any?
    private var updateGeneration = 0
    private var pendingWidth: CGFloat?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopObserving()
        } else {
            scheduleUpdate()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleUpdate()
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
    }

    func update(
        holdingPriority: NSLayoutConstraint.Priority,
        capturesDirectDividerResizes: Bool,
        widthChanged: @escaping @MainActor @Sendable (CGFloat) -> Void
    ) {
        self.holdingPriority = holdingPriority
        self.capturesDirectDividerResizes = capturesDirectDividerResizes
        self.widthChanged = widthChanged
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        updateGeneration += 1
        let generation = updateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.updateGeneration else { return }
            self.configureEnclosingItem()
        }
    }

    private func configureEnclosingItem() {
        guard let (item, splitView, pane, paneIndex) = enclosingSplitViewItem() else { return }

        if configuredItem !== item {
            configuredItem = item
        }
        if item.holdingPriority != holdingPriority {
            item.holdingPriority = holdingPriority
        }

        guard observedSplitView !== splitView
                || observedPane !== pane
                || observedPaneIndex != paneIndex else {
            return
        }
        stopObserving()
        observedSplitView = splitView
        observedPane = pane
        observedPaneIndex = paneIndex
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.captureDirectDividerResize()
            }
        }
    }

    private func captureDirectDividerResize() {
        guard capturesDirectDividerResizes,
              let splitView = observedSplitView,
              let pane = observedPane,
              splitView.window?.inLiveResize != true,
              NSEvent.pressedMouseButtons & 1 == 1,
              isMouseDraggingAdjacentDivider(in: splitView),
              pane.frame.width > 0 else {
            return
        }

        pendingWidth = pane.frame.width
        if mouseUpMonitor == nil {
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.commitPendingWidth()
                }
                return event
            }
        }
    }

    private func commitPendingWidth() {
        guard let pendingWidth else {
            removeMouseUpMonitor()
            return
        }
        self.pendingWidth = nil
        removeMouseUpMonitor()
        widthChanged(pendingWidth)
    }

    private func removeMouseUpMonitor() {
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
    }

    private func isMouseDraggingAdjacentDivider(in splitView: NSSplitView) -> Bool {
        guard let window = splitView.window else { return false }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = splitView.convert(windowPoint, from: nil)
        let dividerIndices = [observedPaneIndex - 1, observedPaneIndex]
            .filter { splitView.subviews.indices.contains($0) && $0 < splitView.subviews.count - 1 }

        return dividerIndices.contains { dividerIndex in
            let precedingFrame = splitView.subviews[dividerIndex].frame
            let hitSlop: CGFloat = 6
            let dividerRect: NSRect
            if splitView.isVertical {
                dividerRect = NSRect(
                    x: precedingFrame.maxX - hitSlop,
                    y: splitView.bounds.minY,
                    width: splitView.dividerThickness + hitSlop * 2,
                    height: splitView.bounds.height
                )
            } else {
                dividerRect = NSRect(
                    x: splitView.bounds.minX,
                    y: precedingFrame.maxY - hitSlop,
                    width: splitView.bounds.width,
                    height: splitView.dividerThickness + hitSlop * 2
                )
            }
            return dividerRect.contains(point)
        }
    }

    private func stopObserving() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        resizeObserver = nil
        observedSplitView = nil
        observedPane = nil
        pendingWidth = nil
        removeMouseUpMonitor()
    }

    private func enclosingSplitViewItem() -> (NSSplitViewItem, NSSplitView, NSView, Int)? {
        var descendant: NSView = self
        var ancestor = superview

        while let current = ancestor {
            if let splitView = current as? NSSplitView,
               let pane = directChild(of: splitView, containing: descendant),
               let paneIndex = splitView.subviews.firstIndex(of: pane),
               let splitViewController = splitView.delegate as? NSSplitViewController,
               splitViewController.splitViewItems.indices.contains(paneIndex) {
                return (splitViewController.splitViewItems[paneIndex], splitView, pane, paneIndex)
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
    let canMoveSelectedTabToNewColumn: Bool
    let movePanel: (WorkspacePanel, UUID, WorkspacePanel?) -> Void
    let dockBeside: (WorkspacePanel, UUID, Bool) -> Void
    let moveToNewColumn: (WorkspacePanel) -> Void
    let detachPanel: (WorkspacePanel) -> Void
    @ViewBuilder let panelContent: (WorkspacePanel) -> PanelContent
    @State private var leadingTargeted = false
    @State private var trailingTargeted = false
    @State private var consolidationTargeted = false
    @State private var targetedTab: WorkspacePanel?
    @State private var appendTabTargeted = false
    @State private var emptyDockTargeted = false

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
        .contentShape(Rectangle())
        .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
            accept(values, before: nil)
        } isTargeted: {
            consolidationTargeted = $0
        }
        .background {
            Group {
                if usesSidebarMaterial {
                    SidebarMaterialBackground()
                } else {
                    Color(nsColor: .controlBackgroundColor)
                }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if consolidationTargeted,
               !leadingTargeted,
               !trailingTargeted,
               targetedTab == nil,
               !appendTabTargeted,
               !column.panels.isEmpty {
                ConsolidationDockTarget()
                    .allowsHitTesting(false)
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
        } isTargeted: {
            emptyDockTargeted = $0
        }
        .overlay {
            if emptyDockTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
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
                            isDropTargeted: targetedTab == panel,
                            canMoveToNewColumn: canMoveSelectedTabToNewColumn,
                            select: {
                                column.selectedPanel = panel
                            },
                            moveToNewColumn: { moveToNewColumn(panel) },
                            detach: { detachPanel(panel) }
                        )
                        .dropDestination(for: WorkspacePanelDragPayload.self) { values, _ in
                            accept(values, before: panel)
                        } isTargeted: { isTargeted in
                            if isTargeted {
                                targetedTab = panel
                            } else if targetedTab == panel {
                                targetedTab = nil
                            }
                        }
                    }
                    if appendTabTargeted, targetedTab == nil {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 24)
                            .accessibilityHidden(true)
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
            accept(values, before: nil)
        } isTargeted: {
            appendTabTargeted = $0
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

private struct ConsolidationDockTarget: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.10)
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(8)
            Label("Add as Tab", systemImage: "rectangle.stack")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
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
    let isDropTargeted: Bool
    let canMoveToNewColumn: Bool
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
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isDropTargeted ? 0.16 : 0))
        }
        .overlay(alignment: .leading) {
            if isDropTargeted {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 24)
                    .offset(x: -2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(panel.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(panel.title)
        .draggable(WorkspacePanelDragPayload(panel: panel))
        .contextMenu {
            Button("Move Tab to New Column", systemImage: "rectangle.split.2x1", action: moveToNewColumn)
                .disabled(!canMoveToNewColumn)
            Button("Detach Tab", systemImage: "macwindow.on.rectangle", action: detach)
        }
    }
}
