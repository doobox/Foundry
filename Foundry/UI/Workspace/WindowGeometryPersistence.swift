import AppKit
import SwiftUI

/// Persists a window frame without opting the scene into automatic state restoration.
struct WindowGeometryPersistence: NSViewRepresentable {
    let key: String

    func makeCoordinator() -> Coordinator {
        Coordinator(key: key)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowReaderView()
        view.onWindowChange = context.coordinator.attach(to:)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        private let key: String
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var didRestore = false

        init(key: String) {
            self.key = key
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            guard let window else { return }

            // Attaching the hosting view can happen during AppKit layout.
            // Restore on the next main-queue turn to avoid re-entering layout.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.restoreFrame(of: window)
            }

            let center = NotificationCenter.default
            observers = [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification].map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.saveFrame()
                }
            }
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            window = nil
        }

        private func restoreFrame(of window: NSWindow) {
            guard !didRestore else { return }
            didRestore = true
            guard let value = UserDefaults.standard.string(forKey: key) else { return }

            let savedFrame = NSRectFromString(value)
            guard savedFrame.width > 0, savedFrame.height > 0 else { return }

            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            guard let screenFrame = visibleFrames.first(where: { $0.intersects(savedFrame) })
                    ?? window.screen?.visibleFrame
                    ?? NSScreen.main?.visibleFrame else { return }

            let restored = Self.restoredFrame(
                savedFrame,
                minimumSize: window.contentMinSize,
                visibleFrame: screenFrame
            )
            window.setFrame(restored, display: false)
        }

        static func restoredFrame(
            _ savedFrame: NSRect,
            minimumSize: NSSize,
            visibleFrame: NSRect
        ) -> NSRect {
            var restored = savedFrame
            restored.size.width = min(max(restored.width, minimumSize.width), visibleFrame.width)
            restored.size.height = min(max(restored.height, minimumSize.height), visibleFrame.height)
            restored.origin.x = min(max(restored.minX, visibleFrame.minX), visibleFrame.maxX - restored.width)
            restored.origin.y = min(max(restored.minY, visibleFrame.minY), visibleFrame.maxY - restored.height)
            return restored
        }

        private func saveFrame() {
            guard let window, window.isVisible else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
        }
    }
}

private final class WindowReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
