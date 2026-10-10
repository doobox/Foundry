import SwiftUI

struct BootstrapColourSourcePicker: View {
    let section: BootstrapEditorSection
    let theme: Theme
    let select: (String) -> Void
    @State private var selection = "custom"

    private var current: String { BootstrapColourSource.selected(in: theme, section: section) }

    var body: some View {
        Picker("Colour source", selection: $selection) {
            if current == "custom" { Text("Custom colour").tag("custom") }
            ForEach(BootstrapColourSource.choices(for: section)) { source in
                Text(source.title).tag(source.id)
            }
        }
        .labelsHidden()
        .onAppear { selection = current }
        .onChange(of: current) { _, value in selection = value }
        .onChange(of: selection) { _, value in
            guard value != current,
                  let source = BootstrapColourSource.choices(for: section).first(where: { $0.id == value }) else { return }
            select(source.expression)
        }
    }
}
