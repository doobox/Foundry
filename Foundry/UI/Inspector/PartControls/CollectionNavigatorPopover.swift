import SwiftUI

struct CollectionNavigatorPopover: View {
    let itemLabel: String
    let recordIDs: [String]
    @Binding var selection: String?
    let move: (IndexSet, Int) -> Void
    let add: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if recordIDs.isEmpty {
                ContentUnavailableView(
                    "No \(itemLabel)s",
                    systemImage: "rectangle.stack",
                    description: Text("Add a \(itemLabel.lowercased()) to begin.")
                )
                .frame(height: 120)
            } else {
                List(selection: $selection) {
                    ForEach(Array(recordIDs.enumerated()), id: \.element) { index, id in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .frame(width: 12)
                                .opacity(selection == id ? 1 : 0)
                                .accessibilityHidden(true)
                            Text(PartCollectionValue.title(itemLabel: itemLabel, position: index))
                            Spacer(minLength: 12)
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .tag(id)
                        .accessibilityLabel(PartCollectionValue.title(itemLabel: itemLabel, position: index))
                        .accessibilityValue(selection == id ? "Selected" : "")
                    }
                    .onMove(perform: move)
                }
                .listStyle(.inset)
                .frame(height: listHeight)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Add \(itemLabel)", systemImage: "plus", action: add)
                    .labelStyle(.iconOnly)
                    .help("Add \(itemLabel)")
                Button("Duplicate \(itemLabel)", systemImage: "plus.square.on.square", action: duplicate)
                    .labelStyle(.iconOnly)
                    .help("Duplicate \(itemLabel)")
                    .disabled(selection == nil)
                Spacer()
                Button("Delete \(itemLabel)", systemImage: "trash", role: .destructive, action: delete)
                    .labelStyle(.iconOnly)
                    .help("Delete \(itemLabel)")
                    .disabled(selection == nil)
            }
            .padding(8)
        }
        .frame(width: 250)
        .controlSize(.small)
    }

    private var listHeight: CGFloat {
        min(300, max(96, CGFloat(recordIDs.count) * 28 + 12))
    }
}
