import AppKit
import SwiftUI

/// Observe only clicks in this sheet's parent; never intercept another window.
struct SheetBackdropClose: NSViewRepresentable {
    var close: () -> Void
    func makeNSView(context: Context) -> BackdropReader {
        let view = BackdropReader()
        view.close = close
        return view
    }
    func updateNSView(_ nsView: BackdropReader, context: Context) { nsView.close = close }
    static func dismantleNSView(_ nsView: BackdropReader, coordinator: ()) { nsView.stop() }

    final class BackdropReader: NSView {
        var close: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let sheet = self.window, let parent = sheet.sheetParent,
                      event.window === parent, parent.attachedSheet === sheet,
                      sheet.attachedSheet == nil else { return event }
                let point = parent.convertPoint(toScreen: event.locationInWindow)
                guard parent.frame.contains(point), !sheet.frame.contains(point) else { return event }
                DispatchQueue.main.async { [weak self, weak sheet] in
                    guard let self, self.window === sheet, sheet?.sheetParent != nil else { return }
                    self.close?()
                }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
