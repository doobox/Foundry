import AppKit
import SwiftUI

@MainActor
final class DetachedPanelWindowCoordinator: NSObject, NSWindowDelegate {
    private struct WindowRecord {
        let window: NSPanel
        let hostingController: NSHostingController<DetachedPanelRoot>
    }

    private weak var ownerWindow: NSWindow?
    private var windows: [WorkspacePanel: WindowRecord] = [:]
    private var closingProgrammatically: Set<WorkspacePanel> = []
    private var requestedPanels: [DetachedWorkspacePanel] = []
    private var panelContent: [WorkspacePanel: AnyView] = [:]
    private var updateFrame: ((WorkspacePanel, WorkspaceWindowFrame) -> Void)?
    private var closePanel: ((WorkspacePanel) -> Void)?

    func attach(to window: NSWindow?) {
        guard ownerWindow !== window else { return }

        if let oldOwner = ownerWindow {
            for record in windows.values where record.window.parent === oldOwner {
                oldOwner.removeChildWindow(record.window)
            }
        }

        ownerWindow = window

        if let window {
            for record in windows.values where record.window.parent == nil {
                window.addChildWindow(record.window, ordered: .above)
            }
        }

        reconcileWindows()
    }

    func synchronize(
        panels: [DetachedWorkspacePanel],
        content: (WorkspacePanel) -> AnyView,
        updateFrame: @escaping (WorkspacePanel, WorkspaceWindowFrame) -> Void,
        closePanel: @escaping (WorkspacePanel) -> Void
    ) {
        requestedPanels = panels
        panelContent = Dictionary(uniqueKeysWithValues: panels.map { ($0.panel, content($0.panel)) })
        self.updateFrame = updateFrame
        self.closePanel = closePanel
        reconcileWindows()
    }

    func closeAll() {
        let records = windows
        windows.removeAll()

        for (panel, record) in records {
            closingProgrammatically.insert(panel)
            if let parent = record.window.parent {
                parent.removeChildWindow(record.window)
            }
            record.window.delegate = nil
            record.window.close()
        }

        closingProgrammatically.removeAll()
        requestedPanels.removeAll()
        panelContent.removeAll()
        ownerWindow = nil
    }

    private func reconcileWindows() {
        let requested = Set(requestedPanels.map(\.panel))
        let removedPanels = windows.keys.filter { !requested.contains($0) }

        for panel in removedPanels {
            closeWindow(for: panel)
        }

        guard ownerWindow != nil else { return }

        for (index, detached) in requestedPanels.enumerated() {
            guard let content = panelContent[detached.panel] else { continue }
            let rootView = DetachedPanelRoot(panel: detached.panel, content: content)

            if let record = windows[detached.panel] {
                record.hostingController.rootView = rootView
            } else {
                present(detached, rootView: rootView, cascadeIndex: index)
            }
        }
    }

    private func present(
        _ detached: DetachedWorkspacePanel,
        rootView: DetachedPanelRoot,
        cascadeIndex: Int
    ) {
        let frame = resolvedFrame(for: detached, cascadeIndex: cascadeIndex)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)
        window.title = detached.panel.title
        window.identifier = NSUserInterfaceItemIdentifier("foundry.detached.\(detached.panel.rawValue)")
        window.tabbingMode = .disallowed
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.animationBehavior = .utilityWindow
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.minSize = NSSize(width: 240, height: 260)
        window.contentViewController = hostingController
        window.delegate = self

        windows[detached.panel] = WindowRecord(
            window: window,
            hostingController: hostingController
        )

        if let ownerWindow {
            ownerWindow.addChildWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)

        let resolvedWorkspaceFrame = WorkspaceWindowFrame(frame)
        if resolvedWorkspaceFrame != detached.frame {
            Task { @MainActor [weak self] in
                self?.updateFrame?(detached.panel, resolvedWorkspaceFrame)
            }
        }
    }

    private func closeWindow(for panel: WorkspacePanel) {
        guard let record = windows[panel] else { return }
        closingProgrammatically.insert(panel)
        if let parent = record.window.parent {
            parent.removeChildWindow(record.window)
        }
        record.window.close()
    }

    private func resolvedFrame(
        for detached: DetachedWorkspacePanel,
        cascadeIndex: Int
    ) -> NSRect {
        let requested = NSRect(detached.frame)
        let visibleFrame = bestVisibleFrame(for: requested)

        if detached.frame == .initial, let ownerWindow {
            let offset = CGFloat(cascadeIndex) * 24
            let centered = NSRect(
                x: ownerWindow.frame.midX - requested.width / 2 + offset,
                y: ownerWindow.frame.midY - requested.height / 2 - offset,
                width: requested.width,
                height: requested.height
            )
            return clamped(centered, to: visibleFrame)
        }

        return clamped(requested, to: visibleFrame)
    }

    private func bestVisibleFrame(for requested: NSRect) -> NSRect {
        if let ownerScreen = ownerWindow?.screen {
            return ownerScreen.visibleFrame
        }

        if let intersecting = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(requested).area < $1.visibleFrame.intersection(requested).area
        }), intersecting.visibleFrame.intersects(requested) {
            return intersecting.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? requested
    }

    private func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(max(result.width, 240), visibleFrame.width)
        result.size.height = min(max(result.height, 260), visibleFrame.height)
        result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }

    func windowDidMove(_ notification: Notification) {
        recordFrame(notification)
    }

    func windowDidResize(_ notification: Notification) {
        recordFrame(notification)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = panel(for: window) else {
            return
        }

        if let parent = window.parent {
            parent.removeChildWindow(window)
        }
        windows.removeValue(forKey: panel)
        if closingProgrammatically.remove(panel) == nil {
            closePanel?(panel)
        }
    }

    private func recordFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = panel(for: window),
              !closingProgrammatically.contains(panel) else {
            return
        }
        updateFrame?(panel, WorkspaceWindowFrame(window.frame))
    }

    private func panel(for window: NSWindow) -> WorkspacePanel? {
        windows.first(where: { $0.value.window === window })?.key
    }
}

private extension NSRect {
    init(_ frame: WorkspaceWindowFrame) {
        self.init(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}

private extension WorkspaceWindowFrame {
    init(_ frame: NSRect) {
        self.init(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }
}

private struct DetachedPanelRoot: View {
    let panel: WorkspacePanel
    let content: AnyView

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                Label(panel.title, systemImage: panel.systemImage)
                    .font(.callout.weight(.medium))
                    .imageScale(.large)
                Spacer()
                Text("Drag to dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.bar)
            .contentShape(Rectangle())
            .draggable(WorkspacePanelDragPayload(panel: panel))
            .help("Drag this bar onto a dock or another panel")

            Divider()
            content
                .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 240, minHeight: 260)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

final class DetachedPanelPresentationView: NSView {
    var windowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged?(window)
    }
}

struct DetachedPanelPresenter: NSViewRepresentable {
    final class Coordinator {
        let windowCoordinator: DetachedPanelWindowCoordinator

        init(windowCoordinator: DetachedPanelWindowCoordinator) {
            self.windowCoordinator = windowCoordinator
        }
    }

    @Binding var layout: WorkspaceLayout
    let coordinator: DetachedPanelWindowCoordinator
    let content: (WorkspacePanel) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(windowCoordinator: coordinator)
    }

    func makeNSView(context: Context) -> DetachedPanelPresentationView {
        let view = DetachedPanelPresentationView(frame: .zero)
        view.windowChanged = { [weak windowCoordinator = context.coordinator.windowCoordinator] window in
            windowCoordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: DetachedPanelPresentationView, context: Context) {
        let windowCoordinator = context.coordinator.windowCoordinator
        windowCoordinator.attach(to: nsView.window)
        windowCoordinator.synchronize(
            panels: layout.detachedPanels,
            content: content,
            updateFrame: { panel, frame in
                if layout.detachedPanels.first(where: { $0.panel == panel })?.frame != frame {
                    layout.updateFrame(frame, for: panel)
                }
            },
            closePanel: { panel in
                layout.redockClosedPanel(panel)
            }
        )
    }

    static func dismantleNSView(
        _ nsView: DetachedPanelPresentationView,
        coordinator: Coordinator
    ) {
        nsView.windowChanged = nil
        coordinator.windowCoordinator.closeAll()
    }
}
