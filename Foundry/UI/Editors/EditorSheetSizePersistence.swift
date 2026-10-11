import AppKit
import SwiftUI

/// Saves content size only: AppKit remains responsible for sheet attachment.
struct EditorSheetSizePersistence: NSViewRepresentable {
    let key: String
    let minimum: CGSize
    let defaultSize: CGSize
    var availableSizeChanged: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(key: key, minimum: minimum, defaultSize: defaultSize, availableSizeChanged: availableSizeChanged)
    }

    func makeNSView(context: Context) -> NSView {
        let view = SheetWindowReader()
        view.onWindowChange = context.coordinator.attach
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject {
        let key: String
        let minimum: CGSize
        let defaultSize: CGSize
        let availableSizeChanged: (CGSize) -> Void
        private weak var window: NSWindow?
        private var restored = false
        private var updateQueued = false

        init(key: String, minimum: CGSize, defaultSize: CGSize, availableSizeChanged: @escaping (CGSize) -> Void) {
            self.key = key
            self.minimum = minimum
            self.defaultSize = defaultSize
            self.availableSizeChanged = availableSizeChanged
        }

        func attach(_ window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            guard window != nil else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification] {
                center.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: nil)
            }
            center.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            center.addObserver(self, selector: #selector(save), name: NSWindow.didEndLiveResizeNotification, object: window)
            center.addObserver(self, selector: #selector(save), name: NSWindow.willCloseNotification, object: window)
            queueUpdate()
        }

        func detach() {
            save()
            NotificationCenter.default.removeObserver(self)
            window = nil
            restored = false
        }

        @objc private func windowChanged(_ notification: Notification) {
            guard let changed = notification.object as? NSWindow, let window,
                  changed === window || changed === window.sheetParent else { return }
            // Resizing the sheet already obeys its maximum; do not fight the drag.
            if changed === window, notification.name == NSWindow.didResizeNotification { return }
            queueUpdate()
        }

        @objc private func screenChanged() { queueUpdate() }

        private func queueUpdate() {
            guard !updateQueued else { return }
            updateQueued = true
            // AppKit window attachment/notifications may occur during SwiftUI
            // layout. Defer geometry changes and view state publication.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateQueued = false
                self.updateSize()
            }
        }

        private func updateSize() {
            guard let window,
                  let screen = window.sheetParent?.screen ?? window.screen ?? NSScreen.main else { return }
            let visible = Self.availableFrame(parent: window.sheetParent?.frame, screen: screen.visibleFrame)
            guard !visible.isNull else { return }
            let parentTop = window.sheetParent.map { $0.convertToScreen($0.contentLayoutRect).maxY } ?? visible.maxY
            let top = min(visible.maxY, max(visible.minY + 1, parentTop))
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let available = CGSize(width: max(1, visible.width), height: max(1, top - visible.minY - chrome))
            // SwiftUI uses the remembered size for its first layout. Never
            // restore it here after presentation; only constrain current size.
            let preferred = window.contentRect(forFrameRect: window.frame).size
            let size = Self.clamped(preferred, minimum: minimum, available: available, fallback: defaultSize)
            availableSizeChanged(available)
            // Allow the view to adopt a smaller minimum before resizing AppKit.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.contentMinSize = CGSize(width: min(self.minimum.width, available.width), height: min(self.minimum.height, available.height))
                window.contentMaxSize = available
                var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
                let centerX = window.sheetParent?.frame.midX ?? window.frame.midX
                frame.origin = CGPoint(x: min(max(centerX - frame.width / 2, visible.minX), visible.maxX - frame.width), y: top - frame.height)
                if window.frame != frame { window.setFrame(frame, display: true) }
                self.restored = true
            }
        }

        static func clamped(_ size: CGSize, minimum: CGSize, available: CGSize, fallback: CGSize) -> CGSize {
            func dimension(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat, _ fallback: CGFloat) -> CGFloat {
                min(max(value.isFinite && value > 0 ? value : fallback, minimum), maximum)
            }
            return CGSize(width: dimension(size.width, minimum.width, available.width, fallback.width),
                          height: dimension(size.height, minimum.height, available.height, fallback.height))
        }

        static func availableFrame(parent: CGRect?, screen: CGRect) -> CGRect {
            let bounds = parent?.intersection(screen) ?? screen
            guard !bounds.isNull, bounds.width > 40, bounds.height > 40 else { return .null }
            return bounds.insetBy(dx: 20, dy: 20)
        }

        @objc private func save() {
            guard restored, let window else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
            UserDefaults.standard.set(NSStringFromSize(size), forKey: key)
        }
    }
}

private final class SheetWindowReader: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
