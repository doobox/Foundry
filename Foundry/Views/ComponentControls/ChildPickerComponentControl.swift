import SwiftUI

struct ChildPickerComponentControl: View {
    let label: String
    let options: [ComponentType]
    let childCount: Int
    let maximum: Int?
    let help: String?
    @Binding var selection: ComponentType?
    let add: () -> Void

    private var effectiveSelection: ComponentType? {
        selection ?? options.first
    }

    private var pickerSelection: Binding<ComponentType?> {
        Binding(
            get: { effectiveSelection },
            set: { selection = $0 }
        )
    }

    private var canAdd: Bool {
        selection != nil && (maximum.map { childCount < $0 } ?? true)
    }

    var body: some View {
        InspectorRow(title: label, alignment: .top) {
            if options.isEmpty {
                Text("No installed components are available for this control.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Component", selection: pickerSelection) {
                        ForEach(options) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .buttonSizing(.flexible)
                    .accessibilityLabel("Component to add to \(label)")

                    Button(action: add) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(!canAdd)

                    Text(maximum.map { "\(childCount) of \($0)" } ?? "\(childCount) added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .controlSize(.small)
        .help(help ?? "")
    }
}

#Preview {
    @Previewable @State var selection: ComponentType? = .paragraph

    ComponentControlPreview {
        ChildPickerComponentControl(
            label: "Cards",
            options: [.paragraph, .heading],
            childCount: 3,
            maximum: 12,
            help: "Add another card.",
            selection: $selection,
            add: {}
        )
    }
}
