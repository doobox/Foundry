import AppKit
import Testing
@testable import Foundry

@MainActor
struct EditorSheetSizingTests {
    @Test func limitsToFoundryWindowRatherThanWholeDisplay() {
        let available = EditorSheetSizePersistence.Coordinator.availableFrame(
            parent: CGRect(x: 200, y: 150, width: 900, height: 650),
            screen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(available == CGRect(x: 200, y: 150, width: 900, height: 650))
    }

    @Test func clipsParentWindowToSmallerScreen() {
        let available = EditorSheetSizePersistence.Coordinator.availableFrame(
            parent: CGRect(x: -200, y: -100, width: 1600, height: 1100),
            screen: CGRect(x: 0, y: 40, width: 1024, height: 700))
        #expect(available == CGRect(x: 0, y: 40, width: 1024, height: 700))
    }

    @Test func preservesSavedSizeWhenItFits() {
        let size = CGSize(width: 1100, height: 760)
        #expect(EditorSheetSizePersistence.Coordinator.clamped(size,
            minimum: CGSize(width: 820, height: 560), available: CGSize(width: 1300, height: 900),
            fallback: CGSize(width: 980, height: 700)) == size)
    }

    @Test func availableAreaWinsOverMinimumOnSmallWindows() {
        #expect(EditorSheetSizePersistence.Coordinator.clamped(CGSize(width: 1600, height: 1200),
            minimum: CGSize(width: 820, height: 560), available: CGSize(width: 700, height: 420),
            fallback: CGSize(width: 980, height: 700)) == CGSize(width: 700, height: 420))
    }

    @Test func invalidPreferencesUseDefaults() {
        #expect(EditorSheetSizePersistence.Coordinator.clamped(CGSize(width: CGFloat.nan, height: -1),
            minimum: CGSize(width: 820, height: 560), available: CGSize(width: 1200, height: 900),
            fallback: CGSize(width: 980, height: 700)) == CGSize(width: 980, height: 700))
    }
}
