import AppKit
import SwiftUI

@MainActor
final class DetachedPanelWindowCoordinator: NSObject, NSWindowDelegate {
    private var windows: [WorkspacePanel: NSPanel] = [:]
    private var closingProgrammatically: Set<WorkspacePanel> = []
    private var updateFrame: ((WorkspacePanel, WorkspaceWindowFrame) -> Void)?
    private var closePanel: ((WorkspacePanel) -> Void)?

    func synchronize(
        panels: [DetachedWorkspacePanel],
        content: (WorkspacePanel) -> AnyView,
        updateFrame: @escaping (WorkspacePanel, WorkspaceWindowFrame) -> Void,
        closePanel: @escaping (WorkspacePanel) -> Void
    ) {
        self.updateFrame = updateFrame
        self.closePanel = closePanel
        let requested = Set(panels.map(\.panel))

        for (panel, window) in windows where !requested.contains(panel) {
            closingProgrammatically.insert(panel)
            window.close()
        }

        for detached in panels {
            let rootView = DetachedPanelRoot(
                panel: detached.panel,
                content: content(detached.panel)
            )
            if let window = windows[detached.panel] {
                window.contentViewController = NSHostingController(rootView: rootView)
            } else {
                present(detached, rootView: rootView)
            }
        }
    }

    private func present(_ detached: DetachedWorkspacePanel, rootView: DetachedPanelRoot) {
        let frame = NSRect(
            x: detached.frame.x,
            y: detached.frame.y,
            width: detached.frame.width,
            height: detached.frame.height
        )
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = detached.panel.title
        window.identifier = NSUserInterfaceItemIdentifier("foundry.detached.\(detached.panel.rawValue)")
        window.tabbingMode = .disallowed
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 240, height: 260)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self
        windows[detached.panel] = window
        window.makeKeyAndOrderFront(nil)
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
        let frame = window.frame
        updateFrame?(
            panel,
            WorkspaceWindowFrame(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width,
                height: frame.height
            )
        )
    }

    private func panel(for window: NSWindow) -> WorkspacePanel? {
        windows.first(where: { $0.value === window })?.key
    }
}

private struct DetachedPanelRoot: View {
    let panel: WorkspacePanel
    let content: AnyView

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(panel.title, systemImage: panel.systemImage)
                    .font(.callout.weight(.medium))
                    .imageScale(.large)
                Spacer()
                Text("Drag to a dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.bar)
            .contentShape(Rectangle())
            .draggable(WorkspacePanelDragPayload(panel: panel))

            Divider()
            content
                .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 240, minHeight: 260)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct DetachedPanelPresenter: NSViewRepresentable {
    @Binding var layout: WorkspaceLayout
    let coordinator: DetachedPanelWindowCoordinator
    let content: (WorkspacePanel) -> AnyView

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        coordinator.synchronize(
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
}
