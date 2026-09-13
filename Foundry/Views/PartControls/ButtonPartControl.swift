import SwiftUI

struct ButtonPartControl: View {
    let label: String
    let buttonText: String
    let systemImage: String?
    let activeButtonText: String?
    let activeSystemImage: String?
    let indicator: InspectorRowIndicator?
    @Binding var isActive: Bool

    var body: some View {
        InspectorRow(title: label, alignment: .center, indicator: indicator) {
            Group {
                if isActive {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.bordered)
                }
            }
            .accessibilityValue(isActive ? "On" : "Off")
        }
    }

    private var button: some View {
        Button {
            isActive.toggle()
        } label: {
            if let displayedSystemImage {
                if displayedButtonText.isEmpty {
                    ButtonIconOnlyLabel(systemImage: displayedSystemImage)
                } else {
                    Label(displayedButtonText, systemImage: displayedSystemImage)
                }
            } else {
                Text(displayedButtonText.isEmpty ? "Button" : displayedButtonText)
            }
        }
        .controlSize(.small)
    }

    private var displayedButtonText: String {
        isActive ? (activeButtonText ?? buttonText) : buttonText
    }

    private var displayedSystemImage: String? {
        isActive ? (activeSystemImage ?? systemImage) : systemImage
    }
}

struct ButtonArrayItemPartControl: View {
    let buttonText: String
    let systemImage: String?
    let activeButtonText: String?
    let activeSystemImage: String?
    @Binding var isActive: Bool

    var body: some View {
        Group {
            if isActive {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .accessibilityValue(isActive ? "On" : "Off")
    }

    private var button: some View {
        Button {
            isActive.toggle()
        } label: {
            if let displayedSystemImage {
                if displayedButtonText.isEmpty {
                    ButtonIconOnlyLabel(systemImage: displayedSystemImage)
                } else {
                    Label(displayedButtonText, systemImage: displayedSystemImage)
                }
            } else {
                Text(displayedButtonText.isEmpty ? "Button" : displayedButtonText)
            }
        }
        .buttonSizing(.flexible)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private var displayedButtonText: String {
        isActive ? (activeButtonText ?? buttonText) : buttonText
    }

    private var displayedSystemImage: String? {
        isActive ? (activeSystemImage ?? systemImage) : systemImage
    }
}

struct InspectorSegmentedButtonControl: View {
    let subtitles: [String]
    let buttonTexts: [String]
    let buttonIcons: [String]
    let activeButtonTexts: [String]
    let activeButtonIcons: [String]
    let help: String?
    @Binding var values: [PartProperty.Value]
    @State private var selectedIndex: Int

    init(
        subtitles: [String],
        buttonTexts: [String],
        buttonIcons: [String],
        activeButtonTexts: [String],
        activeButtonIcons: [String],
        help: String?,
        values: Binding<[PartProperty.Value]>
    ) {
        self.subtitles = subtitles
        self.buttonTexts = buttonTexts
        self.buttonIcons = buttonIcons
        self.activeButtonTexts = activeButtonTexts
        self.activeButtonIcons = activeButtonIcons
        self.help = help
        self._values = values
        self._selectedIndex = State(initialValue: Self.selectedIndex(in: values.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 4) {
            Picker("", selection: $selectedIndex) {
                ForEach(values.indices, id: \.self) { index in
                    segmentLabel(at: index)
                        .tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .buttonSizing(.flexible)
            .controlSize(.small)
            HStack(spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    Text(subtitles.indices.contains(index) ? subtitles[index] : "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .help(help ?? "")
        .onChange(of: selectedIndex) { _, newIndex in
            let updatedValues: [PartProperty.Value] = values.indices.map {
                .boolean($0 == newIndex)
            }
            guard updatedValues != values else { return }
            values = updatedValues
        }
        .onChange(of: Self.selectedIndex(in: values)) { _, newIndex in
            guard newIndex != selectedIndex else { return }
            selectedIndex = newIndex
        }
    }

    private func displayedText(at index: Int) -> String {
        guard selectedIndex == index,
              activeButtonTexts.indices.contains(index) else {
            return buttonTexts[index]
        }
        return activeButtonTexts[index]
    }

    private func displayedIcon(at index: Int) -> String? {
        if selectedIndex == index,
           activeButtonIcons.indices.contains(index) {
            return activeButtonIcons[index]
        }
        return buttonIcons.indices.contains(index) ? buttonIcons[index] : nil
    }

    @ViewBuilder
    private func segmentLabel(at index: Int) -> some View {
        let text = displayedText(at: index)
        if let icon = displayedIcon(at: index) {
            if text.isEmpty {
                ButtonIconOnlyLabel(systemImage: icon)
            } else {
                Label(text, systemImage: icon)
            }
        } else {
            Text(text.isEmpty ? "Button" : text)
        }
    }

    private static func selectedIndex(in values: [PartProperty.Value]) -> Int {
        values.firstIndex { $0.booleanValue == true } ?? 0
    }
}

private struct ButtonIconOnlyLabel: View {
    let systemImage: String

    var body: some View {
        ZStack {
            Text(verbatim: "\u{200B}")
                .accessibilityHidden(true)
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    @Previewable @State var isActive = false
    PartControlPreview {
        ButtonPartControl(label: "Action", buttonText: "Run", systemImage: "sparkles", activeButtonText: "Running", activeSystemImage: "checkmark", indicator: .preview, isActive: $isActive)
    }
}

#Preview("Segmented") {
    @Previewable @State var values: [PartProperty.Value] = [
        .boolean(true),
        .boolean(false),
        .boolean(false),
        .boolean(false)
    ]
    PartControlPreview {
        InspectorSegmentedButtonControl(
            subtitles: [],
            buttonTexts: ["One", "Two", "Three", "Four"],
            buttonIcons: ["1.circle", "2.circle", "3.circle", "4.circle"],
            activeButtonTexts: [],
            activeButtonIcons: [],
            help: "Choose one action.",
            values: $values
        )
    }
}
