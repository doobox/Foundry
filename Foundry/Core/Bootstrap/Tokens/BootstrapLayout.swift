import Foundation

nonisolated enum BootstrapLayout {
    static let ids: [ThemeScreenID] = [.small, .medium, .large, .extraLarge, .doubleExtraLarge]
    static let classes = ["sm:container", "md:container", "lg:container", "xl:container", "2xl:container"]

    static func normalized(_ saved: ScreenTokens) -> ScreenTokens {
        var result = ScreenTokens.standard
        var previous = result.screen(.mobile).container
        for id in ids {
            let enabled = saved.screen(id).isEnabled
            if enabled { previous = result.screen(id).container }
            result.update(id) { $0.isEnabled = enabled; $0.container = previous }
        }
        return result
    }

    static func mask(for screens: ScreenTokens) -> Int {
        ids.enumerated().reduce(0) { $0 | (screens.screen($1.element).isEnabled ? 1 << $1.offset : 0) }
    }

    static func allowsContainerClass(_ value: String, screens: ScreenTokens) -> Bool {
        guard let index = classes.firstIndex(of: value) else { return true }
        return screens.screen(ids[index]).isEnabled
    }

    static func containerClass(_ value: String, screens: ScreenTokens) -> String {
        guard let index = classes.firstIndex(of: value), !screens.screen(ids[index]).isEnabled else { return value }
        for candidate in (0..<index).reversed() where screens.screen(ids[candidate]).isEnabled {
            return classes[candidate]
        }
        return "container"
    }

}
