import AppKit
import Testing
@testable import Foundry

struct AppPreferencesTests {
    @Test @MainActor
    func canvasBackgroundAssetContainsBothAppearanceColours() throws {
        let colour = try #require(NSColor(named: "CanvasWorkspaceBackground", bundle: Bundle.main))
        for (name, red, green, blue) in [
            (NSAppearance.Name.aqua, 0.894, 0.902, 0.898),
            (NSAppearance.Name.darkAqua, 0.188, 0.204, 0.196)
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
