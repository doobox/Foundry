import SwiftUI

struct ChildPickerPopover: View {
    let label: String
    let options: [PartType]
    let add: (PartType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label.isEmpty ? "Choose a child part" : label)
                .font(.headline)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(options) { type in
                        Button {
                            add(type)
                        } label: {
                            HStack(spacing: 10) {
                                PartSquareIcon(type: type, size: 24)
                                    .accessibilityHidden(true)
                                Text(type.displayName)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add \(type.displayName)")
                    }
                }
            }
            .frame(height: min(CGFloat(options.count) * 44, 264))
        }
        .padding(12)
        .frame(width: 300)
    }
}
