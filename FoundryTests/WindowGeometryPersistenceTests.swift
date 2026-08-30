import AppKit
import Testing
@testable import Foundry

@Suite("Window geometry persistence")
struct WindowGeometryPersistenceTests {
    @Test("A restored frame is clamped to the visible screen and minimum size")
    func clampsRestoredFrame() {
        let restored = WindowGeometryPersistence.Coordinator.restoredFrame(
            NSRect(x: -500, y: 900, width: 400, height: 300),
            minimumSize: NSSize(width: 800, height: 600),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800)
        )

        #expect(restored == NSRect(x: 0, y: 200, width: 800, height: 600))
    }

    @Test("A valid saved frame is preserved")
    func preservesValidFrame() {
        let saved = NSRect(x: 120, y: 80, width: 900, height: 640)
        let restored = WindowGeometryPersistence.Coordinator.restoredFrame(
            saved,
            minimumSize: NSSize(width: 800, height: 600),
            visibleFrame: NSRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        #expect(restored == saved)
    }
}
