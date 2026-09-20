import SwiftUI

struct ThemeSpacingInput<Policy: ThemeSpacingPolicy>: View {
    let binding: Binding<ThemeSpacingValue<Policy>.EdgeValue>
    let title: String
    let theme: Theme
    let focusNamespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        if binding.wrappedValue.isCustom {
            ThemeSpacingCustomInput<Policy>(
                binding: binding,
                title: title,
                focusNamespace: focusNamespace
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
