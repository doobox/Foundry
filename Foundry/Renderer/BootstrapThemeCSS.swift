import Foundation

/// Runtime settings shared by canvas, preview and export. No Sass compilation.
nonisolated enum BootstrapThemeCSS {
    static func render(framework: Framework) -> String {
        var declarations = ["--bs-spacer: 1rem;"]
        declarations += framework.spacing.values.enumerated().map { "--bs-spacer-\($0.offset): \($0.element)rem;" }
        declarations += framework.spacing.custom.map { "--bs-spacer-\($0.name): \($0.value)rem;" }
        let names = ["sm", "md", "lg", "xl", "2xl"]
        for (id, name) in zip(BootstrapLayout.ids, names) {
            let cap = framework.screens.screen(id).container
            let value = cap.unit == .auto ? "none" : "\(Int(cap.value))px"
            declarations.append("--bs-container-\(name): \(value);")
        }
        return ":root, :host {\n" + declarations.joined(separator: "\n") + "\n}" + BootstrapSpacingCSS.render(framework.spacing) + BootstrapEditorCSS.render(framework)
    }
}
