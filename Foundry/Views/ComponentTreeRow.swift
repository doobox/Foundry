import SwiftUI

struct ComponentTreeRow: View {
    let component: ComponentNode
    let depth: Int
    @Binding var selectedComponentID: UUID?
    @Binding var expandedComponentIDs: Set<UUID>
    let moveComponent: (UUID, ComponentPlacement) -> Bool
    let insertComponent: (ComponentType, ComponentPlacement) -> Bool
    let insertReusableComponent: (UUID, ComponentPlacement) -> Bool
    let insertGlobalComponent: (UUID, ComponentPlacement) -> Bool

    var body: some View { label }

    private var label: some View {
        HStack(spacing: 4) {
            if component.children.isEmpty {
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
            ComponentLabel(component: component)
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
            .help("Drag to rearrange \(component.name)")
    }

    private var isSelected: Bool {
        selectedComponentID == component.id
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedComponentIDs.contains(component.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedComponentIDs.insert(component.id)
                } else {
                    expandedComponentIDs.remove(component.id)
                }
            }
        )
    }

}

private struct ComponentLabel: View {
    let component: ComponentNode

    var body: some View {
        Label(component.name, systemImage: component.type.systemImage)
    }
}
