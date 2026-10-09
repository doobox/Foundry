import Foundation

nonisolated enum CanvasBreakpointPreference {
    static func viewportWidth(afterChanging old: ScreenTokens, to screens: ScreenTokens, currentWidth: Double) -> Double {
        let selected = old.activeScreen(for: currentWidth)
        guard !screens.screen(selected.id).isEnabled else { return currentWidth }
        let fallback = screens.activeScreen(for: selected.minimumWidth)
        return screens.canvasWidth(for: fallback)
    }

    static func restoredViewportWidth(
        screens: ScreenTokens,
        defaults: UserDefaults = .standard
    ) -> Double {
        let rememberedWidth = defaults.double(forKey: AppPreferenceKey.lastSelectedBreakpointWidth)
        let enabledScreens = screens.enabledScreens
        let matchingScreen = enabledScreens.last {
            rememberedWidth.isFinite && screens.canvasWidth(for: $0) <= rememberedWidth
        }
        let screen = matchingScreen ?? enabledScreens.first ?? screens.screen(.mobile)

        // Restoring a fallback must not replace the user's saved preference.
        return screens.canvasWidth(for: screen)
    }

    /// Call only for an explicit breakpoint selection, not a restore or canvas drag.
    static func remember(_ width: Double, defaults: UserDefaults = .standard) {
        guard width.isFinite, width > 0 else { return }
        defaults.set(width, forKey: AppPreferenceKey.lastSelectedBreakpointWidth)
    }
}
