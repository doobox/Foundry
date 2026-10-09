import SwiftUI

struct FrameworkCustomSpacingRow: View {
    let token: CustomSpacingToken
    let editor: ProjectEditor
    let remove: () -> Void
    @State private var name = ""
    @State private var value = 0.0
    @State private var error: String?
    @FocusState private var editingName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 120)
                    .focused($editingName).onSubmit(commitName)
                    .accessibilityLabel("Spacing size name")
                Slider(value: sliderValue, in: 0...12, step: 0.125)
                    .accessibilityLabel("\(token.name) value")
                FrameworkNumberField(title: "\(token.name) value", value: $value, unit: "rem", step: 0.125, precision: 3)
                Button("Delete \(token.name)", systemImage: "trash", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 24, height: 24)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 8)
        .onAppear { name = token.name; value = token.value }
        .onChange(of: token.name) { _, newValue in name = newValue; error = nil }
        .onChange(of: token.value) { _, newValue in value = newValue }
        .onChange(of: editingName) { _, focused in if !focused { commitName() } }
        .onChange(of: value) { _, newValue in
            if newValue.isFinite && newValue >= 0 { editor.setCustomSpacing(token.id, value: newValue) }
            else { value = token.value }
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { min(max(value, 0), 12) }, set: { value = $0 })
    }

    private func commitName() {
        guard editor.renameCustomSpacing(token.id, name: name) else {
            error = "Use a unique name with letters, numbers, hyphens or underscores. Bootstrap names are reserved."
            return
        }
        error = nil
    }
}
