import SwiftUI

struct ChildPickerPartControl: View {
    let label: String
    let options: [PartType]
    let childCount: Int
    let maximum: Int?
    let help: String?
    @Binding var selection: PartType?
    let add: () -> Void

    private var effectiveSelection: PartType? {
        selection ?? options.first
    }

    private var pickerSelection: Binding<PartType?> {
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
                Text("No installed parts are available for this control.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Part", selection: pickerSelection) {
                        ForEach(options) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .buttonSizing(.flexible)
                    .accessibilityLabel("Part to add to \(label)")

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
    @Previewable @State var selection: PartType? = .paragraph

    PartControlPreview {
        ChildPickerPartControl(
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
