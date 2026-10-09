import SwiftUI

struct BootstrapTokenSettings: View {
    let section: BootstrapEditorSection
    let framework: Framework
    let editor: ProjectEditor
    @State private var adding = false
    @State private var name = ""
    @State private var deleting: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if section.allowsCustom {
                    FrameworkEditorCard {
                        HStack(spacing: 8) {
                            Text("Custom \(section.title)").font(.headline).accessibilityAddTraits(.isHeader)
                            Button("Add \(section.title)", systemImage: "plus") { name = ""; adding = true }
                                .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 24, height: 24)
                        }
                        let custom = framework.bootstrapTokens.custom[section.rawValue] ?? []
                        if custom.isEmpty { Text("Extend the scale for your project.").font(.callout).foregroundStyle(.secondary) }
                        ForEach(custom, id: \.self) { name in
                            HStack {
                                Text(name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Delete \(name)", systemImage: "trash") { deleting = name }
                                    .labelStyle(.iconOnly)
                            }
                            ForEach(section.customTokens(named: name)) { token in
                                BootstrapTokenRow(token: token, value: framework.bootstrapTokens.value(token), editor: editor)
                            }
                            if name != custom.last { Divider() }
                        }
                    }
                }
                FrameworkEditorCard {
                    HStack {
                        Text("Bootstrap \(section.title)").font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if framework.bootstrapTokens.isChanged(section) {
                            Button("Reset", systemImage: "arrow.counterclockwise") { editor.resetBootstrapTokens(section) }
                                .help("Restore Bootstrap defaults. Custom values are kept. You can undo this change.")
                        }
                    }
                    if section == .zIndex {
                        Text("Keep component levels in order so menus and overlays stack correctly.").font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(section.tokens) { token in
                            BootstrapTokenRow(token: token, value: framework.bootstrapTokens.value(token), editor: editor)
                            if token.id != section.tokens.last?.id { Divider() }
                        }
                    }
                }
            }.padding(20)
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
