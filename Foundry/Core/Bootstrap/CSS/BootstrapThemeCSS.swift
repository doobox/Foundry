import Foundation

/// Runtime settings shared by canvas, preview and export. No Sass compilation.
///
/// Bootstrap's own stylesheet is never changed. Everything here is an addition:
/// project-named spacers, edited Bootstrap variables, custom token utilities and
/// Foundry's responsive extensions, in that order so later rules win as expected.
nonisolated enum BootstrapThemeCSS {
    static func render(theme: Theme) -> String {
        let spacers = theme.spacing.custom.map { "--bs-spacer-\($0.name): \($0.value)rem;" }
        let root = spacers.isEmpty ? "" : ":root, :host {\n" + spacers.joined(separator: "\n") + "\n}"
        return root
            + BootstrapSpacingCSS.render(theme.spacing)
            + BootstrapEditorCSS.render(theme)
            + BootstrapUtilityExtensionsCSS.render(theme: theme)
    }
}
