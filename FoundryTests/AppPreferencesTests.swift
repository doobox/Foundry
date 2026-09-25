import AppKit
import Testing
@testable import Foundry

struct AppPreferencesTests {
    @Test @MainActor
    func canvasBackgroundAssetContainsBothAppearanceColours() throws {
        let colour = try #require(NSColor(named: "CanvasWorkspaceBackground", bundle: Bundle.main))
        for (name, red, green, blue) in [
            (NSAppearance.Name.aqua, 0.476, 0.476, 0.476),
            (NSAppearance.Name.darkAqua, 0.157, 0.165, 0.212)
        ] {
            let appearance = try #require(NSAppearance(named: name))
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolved = colour.usingColorSpace(.sRGB)
            }
            let value = try #require(resolved)
            #expect(abs(value.redComponent - red) < 0.005)
            #expect(abs(value.greenComponent - green) < 0.005)
            #expect(abs(value.blueComponent - blue) < 0.005)
            #expect(value.alphaComponent == 1)
        }
    }

    @Test
    func previewDefaultsToTheUsersDefaultBrowser() {
        #expect(PreviewApplicationSelection.systemDefault == "systemDefault")
    }
}
