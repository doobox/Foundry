import Testing
@testable import Foundry

struct CanvasSizingTests {
    @Test
    func widerViewportsScaleToFitWithoutChangingAdjacentLayoutWidth() {
        #expect(CanvasSizing.scale(availableWidth: 1_000, viewportWidth: 390, horizontalChromeWidth: 48) == 1)
        #expect(CanvasSizing.scale(availableWidth: 1_000, viewportWidth: 1_440, horizontalChromeWidth: 48) < 1)
    }

    @Test
    func resizingClampsViewportToItsPermittedRange() {
        #expect(CanvasSizing.resizedViewportWidth(
            startingWidth: 390, translation: 100, direction: 1, scale: 1,
            minimum: 320, maximum: 1_440
        ) == 590)
        #expect(CanvasSizing.resizedViewportWidth(
            startingWidth: 1_440, translation: 100, direction: 1, scale: 0.5,
            minimum: 320, maximum: 1_440
        ) == 1_440)
        #expect(CanvasSizing.resizedViewportWidth(
            startingWidth: 390, translation: -100, direction: 1, scale: 1,
            minimum: 320, maximum: 1_440
        ) == 320)
    }
}
