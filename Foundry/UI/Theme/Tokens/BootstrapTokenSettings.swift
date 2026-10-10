import SwiftUI

/// Project-named additions to one Bootstrap scale, each emitted as an extra utility class.
struct BootstrapCustomTokenCard: View {
    let section: BootstrapEditorSection
    let theme: Theme
    let editor: ProjectEditor
    @State private var adding = false
    @State private var name = ""
    @State private var deleting: String?

    var body: some View {
        ThemeEditorCard {
            HStack(spacing: 8) {
                Text("Custom \(section.title)").font(.headline).accessibilityAddTraits(.isHeader)
                ThemeAddButton(title: "Add \(section.title)") { name = ""; adding = true }
            }
            let custom = theme.bootstrapTokens.custom[section.rawValue] ?? []
            if custom.isEmpty { Text("Extend the scale for your project.").font(.callout).foregroundStyle(.secondary) }
            ForEach(custom, id: \.self) { name in
                HStack {
                    Text(name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Delete \(name)", systemImage: "trash") { deleting = name }
                        .labelStyle(.iconOnly)
                }
                ForEach(section.customTokens(named: name)) { token in
                    BootstrapTokenRow(token: token, value: theme.bootstrapTokens.value(token), editor: editor)
                }
                if name != custom.last { Divider() }
            }
        }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add \(section.title)").font(.headline)
                TextField("Name, e.g. hero", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { adding = false }.keyboardShortcut(.cancelAction)
                    Button("Add") { editor.addBootstrapToken(name, section: section); adding = false }
                        .disabled(!editor.canAddBootstrapToken(name, section: section)).keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 360)
        }
        .confirmationDialog("Delete custom value?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Replace with Bootstrap default and delete", role: .destructive) {
                if let deleting { editor.removeBootstrapToken(deleting, section: section) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Part controls using this value will use the default instead. Update any hand-written classes separately. You can undo this change.")
        }
    }
}
