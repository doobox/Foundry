import SwiftUI

struct IconPartControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var selection: String

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            FoundryIconPicker(selection: $selection, accessibilityLabel: label)
        }
    }
}

#Preview {
    @Previewable @State var selection = "star"
    PartControlPreview {
        IconPartControl(label: "Icon", indicator: .preview, selection: $selection)
    }
}

import SwiftUI

struct FoundryIconPicker: View {
    @Binding var selection: String
    let accessibilityLabel: String

    @State private var isPresented = false
    @State private var isFontReady = false

    private var selectedIcon: FoundryWebIcon? {
        FoundryWebLibraryRegistry.icon(named: selection)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                FoundryIconGlyph(icon: selectedIcon, fontReady: isFontReady, size: 17)
                    .frame(width: 22, height: 22)
                Text(selectedIcon?.displayName ?? "Choose Icon")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedIcon?.displayName ?? "No icon selected")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            FoundryIconPickerPopover(
                selection: $selection,
                isPresented: $isPresented,
                fontReady: isFontReady
            )
        }
        .onAppear {
            isFontReady = FoundryWebLibraryRegistry.prepareNativeIconFont()
        }
    }
}

private struct FoundryIconPickerPopover: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    let fontReady: Bool

    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 8)
    ]

    private var filteredIcons: [FoundryWebIcon] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return FoundryWebLibraryRegistry.icons }
        return FoundryWebLibraryRegistry.icons.filter {
            $0.name.localizedStandardContains(query)
                || $0.displayName.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search icons", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            if filteredIcons.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(filteredIcons) { icon in
                            Button {
                                selection = icon.name
                                isPresented = false
                            } label: {
                                VStack(spacing: 7) {
                                    FoundryIconGlyph(icon: icon, fontReady: fontReady, size: 23)
                                        .frame(width: 28, height: 28)
                                    Text(icon.name)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .top)
                                .background(
                                    selection == icon.name
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(
                                            selection == icon.name
                                                ? Color.accentColor.opacity(0.8)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .help(icon.displayName)
                            .accessibilityLabel(icon.displayName)
                            .accessibilityAddTraits(selection == icon.name ? .isSelected : [])
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 440, height: 500)
    }
}

private struct FoundryIconGlyph: View {
    let icon: FoundryWebIcon?
    let fontReady: Bool
    let size: CGFloat

    var body: some View {
        if let icon, fontReady {
            Text(icon.glyph)
                .font(.custom(FoundryWebLibraryRegistry.nativeIconFontName, size: size))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "square.dashed")
                .font(.system(size: size * 0.78))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
