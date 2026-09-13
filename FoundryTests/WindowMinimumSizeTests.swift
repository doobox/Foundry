import AppKit
import Testing
@testable import Foundry

@Suite("Window minimum size", .serialized)
@MainActor
struct WindowMinimumSizeTests {
    @Test("Growth does not re-enter from an early resize notification")
    func resizeNotificationDuringGrowth() async {
        let window = EarlyResizeNotificationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let reader = WindowMinimumSizeReaderView()
        window.contentView?.addSubview(reader)
        window.injectEarlyNotification = true

        reader.minimumContentSize = NSSize(width: 1100, height: 640)
        for _ in 0..<10 { await Task.yield() }

        #expect(window.maximumDepth == 1)
        #expect(window.contentLayoutRect.width >= 1100)
        let grownWidth = window.frame.width
        reader.minimumContentSize = NSSize(width: 900, height: 640)
        #expect(window.frame.width == grownWidth, "Hiding a panel must not shrink the window")
        window.close()
    }
}

@MainActor
private final class EarlyResizeNotificationWindow: NSWindow {
    var injectEarlyNotification = false
    var maximumDepth = 0
    private var resizeDepth = 0

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        resizeDepth += 1
        maximumDepth = max(maximumDepth, resizeDepth)
        defer { resizeDepth -= 1 }
        // Bound recursion so the regression fails an assertion, not the test host.
        guard resizeDepth < 3 else { return }
        if injectEarlyNotification {
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: self)
        }
        super.setFrame(frameRect, display: flag)
    }
}
