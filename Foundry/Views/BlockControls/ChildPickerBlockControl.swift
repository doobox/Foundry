import SwiftUI

struct ChildPickerBlockControl: View {
    let label: String
    let options: [BlockType]
    let childCount: Int
    let maximum: Int?
    let help: String?
    @Binding var selection: BlockType?
    let add: () -> Void

    private var effectiveSelection: BlockType? {
        selection ?? options.first
    }

    private var pickerSelection: Binding<BlockType?> {
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
                Text("No installed blocks are available for this control.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Block", selection: pickerSelection) {
                        ForEach(options) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .buttonSizing(.flexible)
                    .accessibilityLabel("Block to add to \(label)")

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
    @Previewable @State var selection: BlockType? = .paragraph

    BlockControlPreview {
        ChildPickerBlockControl(
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
