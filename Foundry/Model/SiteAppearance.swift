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
    func bootstrap(siteID: UUID) -> String {
        guard self == .both else { return "" }
        return """
        <script>
        (() => {
          const key = 'foundry.appearance.\(siteID.uuidString.lowercased())';
          const apply = value => {
            if (!['system', 'light', 'dark'].includes(value)) return;
            document.documentElement.style.colorScheme = value === 'system' ? 'light dark' : value;
            try { localStorage.setItem(key, value); } catch (_) {}
          };
          window.foundryAppearance = { set: apply };
          let saved = 'system';
          try { saved = localStorage.getItem(key) || 'system'; } catch (_) {}
          apply(saved);
        })();
        </script>
        """
    }
}

extension EnvironmentValues {
    @Entry var canvasAppearance: SiteAppearance = .light
}
