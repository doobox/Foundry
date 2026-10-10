import SwiftUI

struct ThemeSpacingInput<Policy: ThemeSpacingPolicy>: View {
    let binding: Binding<ThemeSpacingValue<Policy>.EdgeValue>
    let title: String
    let theme: Theme
    let focusNamespace: Namespace.ID
    var unitChoices: [String]? = nil
    var bootstrapSpacing: Bool = false
    var bootstrapClassPrefix: String = "p"

    @ViewBuilder
    var body: some View {
        if bootstrapSpacing {
            BootstrapSpacingTokenPicker<Policy>(binding: binding, title: title, classPrefix: bootstrapClassPrefix, spacing: theme.spacing)
        } else if binding.wrappedValue.isCustom {
            ThemeSpacingCustomInput<Policy>(
                binding: binding,
                title: title,
                focusNamespace: focusNamespace,
                unitChoices: unitChoices
            )
        } else {
            ThemeSpacingTokenPicker<Policy>(
                binding: binding,
                title: title,
                options: Policy.choices(in: theme)
            )
        }
    }
}
