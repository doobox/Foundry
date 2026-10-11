import SwiftUI

nonisolated enum SiteAppearance: String, Codable, CaseIterable, Sendable {
    case light, dark
    var symbol: String { self == .light ? "sun.max" : "moon" }
}

nonisolated enum SiteAppearanceMode: String, Codable, CaseIterable, Sendable {
    case light, dark, both
    var title: String {
        switch self { case .light: "Light only"; case .dark: "Dark only"; case .both: "Light and Dark" }
    }
    func permits(_ appearance: SiteAppearance) -> Bool { self == .both || rawValue == appearance.rawValue }
    var cssColorScheme: String { self == .both ? "light dark" : rawValue }

    func colour(light: String, dark: String) -> String {
        switch self {
        case .light: light
        case .dark: dark
        case .both: light == dark ? light : "light-dark(\(light), \(dark))"
        }
    }

    /// Runs before styles load so a saved visitor choice does not flash the other appearance.
    func bootstrap(siteID: UUID, defaultMode: String = "system") -> String {
        guard self == .both else { return "" }
        let initialMode = ["system", "light", "dark"].contains(defaultMode) ? defaultMode : "system"
        return """
        <script>
        (() => {
          const key = 'foundry.appearance.\(siteID.uuidString.lowercased())';
          let current = '\(initialMode)';
          const apply = (value, persist = true) => {
            if (!['system', 'light', 'dark'].includes(value)) return;
            if (value === 'system') delete document.documentElement.dataset.bsTheme;
            else document.documentElement.dataset.bsTheme = value;
            current = value;
            if (persist) { try { localStorage.setItem(key, value); } catch (_) {} }
            window.dispatchEvent(new CustomEvent('foundry:appearance-change', { detail: value }));
          };
          window.foundryAppearance = { set: value => apply(value), get: () => current };
          try {
            const saved = localStorage.getItem(key);
            if (['system', 'light', 'dark'].includes(saved)) current = saved;
          } catch (_) {}
          apply(current, false);
        })();
        </script>
        """
    }
}

extension EnvironmentValues {
    @Entry var canvasAppearance: SiteAppearance = .light
}
