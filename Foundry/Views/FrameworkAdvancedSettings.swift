import SwiftUI

/// Bootstrap's component variables, collapsed by default for people who want them.
///
/// Every value here is a variable Bootstrap's own components read, so an edit reaches
/// the whole site. Bootstrap's utility scales are not here: they ship fixed, and
/// project-named additions to them live under Extensions.
struct FrameworkAdvancedSettings: View {
    let framework: Framework
    let editor: ProjectEditor
    @State private var expanded: Set<BootstrapEditorSection> = []

    static let sections: [BootstrapEditorSection] = [
        .body, .links, .focusRing, .controls, .shadows, .borderWidth, .borderRadius, .zIndex
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fine-tune the variables Bootstrap's components read. Changes apply across the site. Bootstrap's utility classes keep their fixed values; add your own under Extensions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Self.sections, id: \.self) { section in
                    DisclosureGroup(isExpanded: binding(for: section)) {
                        BootstrapBuiltInTokenCard(section: section, framework: framework, editor: editor)
                            .padding(.top, 8)
                    } label: {
                        HStack {
                            Text(section.title).font(.headline)
                            if framework.bootstrapTokens.isChanged(section) {
                                Text("Modified").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("framework-advanced-\(section.rawValue)")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("framework-section-Advanced")
    }

    private func binding(for section: BootstrapEditorSection) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(section) },
            set: { isExpanded in
                if isExpanded { expanded.insert(section) } else { expanded.remove(section) }
            }
        )
    }
}
