import SwiftUI

struct GoogleFontFacesEditor: View {
    let configuration: GoogleFontConfiguration
    let onChange: (GoogleFontConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Included styles").font(.headline)
            HStack(alignment: .top, spacing: 24) {
                styleColumn(italic: false)
                if configuration.available.contains(where: \.italic) { styleColumn(italic: true) }
            }
            Text("Keep at least one style. Removing a style does not change existing block selections.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func styleColumn(italic: Bool) -> some View {
        let available = configuration.available.filter { $0.italic == italic }
        let included = configuration.validIncluded.filter { $0.italic == italic }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(italic ? "Italic" : "Normal").fontWeight(.medium)
                Spacer()
                Button("All") { replace(italic: italic, with: available) }
                    .disabled(included == available)
                Button("None") { replace(italic: italic, with: []) }
                    .disabled(included.isEmpty || configuration.validIncluded.allSatisfy { $0.italic == italic })
            }.controlSize(.small)
            ForEach(available) { face in
                let selected = included.first { $0.minimum >= face.minimum && $0.maximum <= face.maximum }
                Toggle(face.isVariable ? "Variable weight" : String(face.minimum), isOn: Binding(
                    get: { selected != nil },
                    set: { enabled in
                        var next = included.filter { $0 != selected }
                        if enabled { next.append(face) }
                        replace(italic: italic, with: next)
                    }))
                    .disabled(selected != nil && configuration.validIncluded.count == 1)
                if face.isVariable, let selected {
                    weightField("Minimum", value: Binding(
                        get: { selected.minimum },
                        set: { minimum in replace(italic: italic, with: [.init(italic: italic, minimum: minimum, maximum: selected.maximum)]) }),
                        range: face.minimum...selected.maximum)
                    weightField("Maximum", value: Binding(
                        get: { selected.maximum },
                        set: { maximum in replace(italic: italic, with: [.init(italic: italic, minimum: selected.minimum, maximum: maximum)]) }),
                        range: selected.minimum...face.maximum)
                }
            }
            if available.isEmpty { Text("Not available").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func weightField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let bounded = Binding<Int>(get: { value.wrappedValue }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
        return HStack {
            Text(title)
            TextField(title, value: bounded, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
            Stepper(title, value: bounded, in: range).labelsHidden()
        }
    }

    private func replace(italic: Bool, with faces: [GoogleFontFace]) {
        var next = configuration
        next.included = configuration.validIncluded.filter { $0.italic != italic } + faces
        guard !next.validIncluded.isEmpty else { return }
        onChange(next)
    }
}
