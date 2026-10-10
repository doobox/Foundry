import SwiftUI

struct PartTreeRow: View {
    let part: PartNode
    let depth: Int
    @Binding var selectedPartID: UUID?
    @Binding var expandedPartIDs: Set<UUID>
    let movePart: (UUID, PartPlacement) -> Bool
    let insertPart: (PartType, PartPlacement) -> Bool
    let insertReusablePart: (UUID, PartPlacement) -> Bool
    let insertGlobalPart: (UUID, PartPlacement) -> Bool

    var body: some View { label }

    private var label: some View {
        HStack(spacing: 4) {
            if part.children.isEmpty {
                Color.clear.frame(width: 16, height: 16)
            } else {
                Button {
                    expansionBinding.wrappedValue.toggle()
                } label: {
                    Image(systemName: expansionBinding.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            PartLabel(part: part)
        }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .padding(.leading, CGFloat(depth) * 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .help("Drag to rearrange \(part.name)")
    }

    private var isSelected: Bool {
        selectedPartID == part.id
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedPartIDs.contains(part.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedPartIDs.insert(part.id)
                } else {
                    expandedPartIDs.remove(part.id)
                }
            }
        )
    }

}

private struct PartLabel: View {
    let part: PartNode

    var body: some View {
        Label(part.name, systemImage: part.type.systemImage)
    }
}
