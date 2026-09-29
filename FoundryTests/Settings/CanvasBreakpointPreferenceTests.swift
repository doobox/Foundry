import Foundation
import Testing
@testable import Foundry

struct CanvasBreakpointPreferenceTests {
    @Test
    func firstLaunchUsesTheSmallestBreakpointWithoutSavingIt() throws {
        try withDefaults { defaults in
            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == 390)
            #expect(defaults.object(forKey: AppPreferenceKey.lastSelectedBreakpointWidth) == nil)
        }
    }

    @Test(arguments: [390.0, 640, 768, 1024, 1280, 1536])
    func restoresEachAvailableBreakpoint(width: Double) throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(width, defaults: defaults)

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == width)
        }
    }

    @Test
    func savedSelectionSurvivesANewPreferencesInstance() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1024, defaults: defaults)
            let saved = defaults.persistentDomain(forName: suiteName)
            #expect(saved?[AppPreferenceKey.lastSelectedBreakpointWidth] as? Double == 1024)

            let reopened = try #require(UserDefaults(suiteName: suiteName))
            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: reopened) == 1024)
        }
    }

    @Test
    func skipsDisabledBreakpointsWithoutReplacingThePreference() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1280, defaults: defaults)
            var screens = ScreenTokens.standard
            screens.update(.extraLarge) { $0.isEnabled = false }
            screens.update(.large) { $0.isEnabled = false }

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: screens, defaults: defaults) == 768)
            #expect(defaults.double(forKey: AppPreferenceKey.lastSelectedBreakpointWidth) == 1280)
            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == 1280)
        }
    }

    @Test
    func fallsBackByWidthWhenAProjectUsesDifferentBreakpointWidths() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1024, defaults: defaults)
            var screens = ScreenTokens.standard
            screens.update(.medium) { $0.minimumWidth = 800 }
            screens.update(.large) { $0.minimumWidth = 1100 }

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: screens, defaults: defaults) == 800)
        }
    }

    @Test
    func usesTheSmallestBreakpointWhenNoneIsSmallEnough() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(320, defaults: defaults)

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == 390)
            #expect(defaults.double(forKey: AppPreferenceKey.lastSelectedBreakpointWidth) == 320)
        }
    }

    @Test
    func supportsProjectsWithOnlyTheMobileBreakpoint() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1536, defaults: defaults)
            var screens = ScreenTokens.standard
            for id in FrameworkScreenID.allCases where id != .mobile {
                screens.update(id) { $0.isEnabled = false }
            }

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: screens, defaults: defaults) == 390)
            #expect(defaults.double(forKey: AppPreferenceKey.lastSelectedBreakpointWidth) == 1536)
        }
    }

    @Test
    func explicitlySelectingAFallbackReplacesThePreference() throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1024, defaults: defaults)
            var screens = ScreenTokens.standard
            screens.update(.large) { $0.isEnabled = false }
            let fallback = CanvasBreakpointPreference.restoredViewportWidth(screens: screens, defaults: defaults)
            try #require(fallback == 768)

            CanvasBreakpointPreference.remember(fallback, defaults: defaults)

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == 768)
        }
    }

    @Test(arguments: [0.0, -1, .infinity, .nan])
    func ignoresInvalidSelections(width: Double) throws {
        try withDefaults { defaults in
            CanvasBreakpointPreference.remember(1024, defaults: defaults)
            CanvasBreakpointPreference.remember(width, defaults: defaults)

            #expect(CanvasBreakpointPreference.restoredViewportWidth(screens: .standard, defaults: defaults) == 1024)
        }
    }

    private let suiteName = "CanvasBreakpointPreferenceTests.\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
