import SwiftUI

struct FrameworkSpacingInput<Policy: FrameworkSpacingPolicy>: View {
    let binding: Binding<FrameworkSpacingValue<Policy>.EdgeValue>
    let title: String
    let framework: Framework
    let focusNamespace: Namespace.ID
    var unitChoices: [String]? = nil
    var bootstrapSpacing: Bool = false
    var bootstrapClassPrefix: String = "p"

    @ViewBuilder
    var body: some View {
        if bootstrapSpacing {
            BootstrapSpacingTokenPicker<Policy>(binding: binding, title: title, classPrefix: bootstrapClassPrefix, spacing: framework.spacing)
        } else if binding.wrappedValue.isCustom {
            FrameworkSpacingCustomInput<Policy>(
                binding: binding,
                title: title,
                focusNamespace: focusNamespace,
                unitChoices: unitChoices
            )
        } else {
            FrameworkSpacingTokenPicker<Policy>(
                binding: binding,
                title: title,
                options: Policy.choices(in: framework)
            )
        }
    }
}
