import SwiftUI

struct ChildPickerPartControl: View {
    let label: String
    var buttonText: String = "Add Child"
    var buttonIcon: String = "plus.app"
    let options: [PartType]
    let action: ChildPickerAction
    let help: String?
    let add: (PartType) -> Void
    @State private var showsChoices = false

    private var disabledReason: String? {
        switch action {
        case .unavailable: "No installed parts are available for this control."
        case .limitReached: "Maximum number of children reached."
        case .add, .choose: nil
        }
    }

    var body: some View {
        InspectorRow(title: label, alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: activate) {
                    Label(buttonText, systemImage: buttonIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!action.isEnabled)
                .help(disabledReason ?? help ?? "")
                .popover(isPresented: $showsChoices) {
                    ChildPickerPopover(label: label, options: options, add: choose)
                }

                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .controlSize(.small)
        .help(help ?? "")
        .onChange(of: action) { _, updated in
            if updated != .choose { showsChoices = false }
        }
    }

    private func activate() {
        switch action {
        case .add(let type): add(type)
        case .choose: showsChoices = true
        case .unavailable, .limitReached: break
        }
    }

    private func choose(_ type: PartType) {
        showsChoices = false
        guard action.isEnabled, options.contains(type) else { return }
        add(type)
    }
}

#Preview {
    PartControlPreview {
        ChildPickerPartControl(
            label: "Cards",
            options: [.paragraph, .heading],
            action: .choose,
            help: "Add another card.",
            add: { _ in }
        )
    }
}
