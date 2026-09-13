import SwiftUI

struct BlockTreeRow: View {
    let block: BlockNode
    let depth: Int
    @Binding var selectedBlockID: UUID?
    @Binding var expandedBlockIDs: Set<UUID>
    let moveBlock: (UUID, BlockPlacement) -> Bool
    let insertBlock: (BlockType, BlockPlacement) -> Bool
    let insertReusableBlock: (UUID, BlockPlacement) -> Bool
    let insertGlobalBlock: (UUID, BlockPlacement) -> Bool

    var body: some View { label }

    private var label: some View {
        HStack(spacing: 4) {
            if block.children.isEmpty {
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
            BlockLabel(block: block)
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
            .help("Drag to rearrange \(block.name)")
    }

    private var isSelected: Bool {
        selectedBlockID == block.id
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedBlockIDs.contains(block.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedBlockIDs.insert(block.id)
                } else {
                    expandedBlockIDs.remove(block.id)
                }
            }
        )
    }

}

private struct BlockLabel: View {
    let block: BlockNode

    var body: some View {
        Label(block.name, systemImage: block.type.systemImage)
    }
}
