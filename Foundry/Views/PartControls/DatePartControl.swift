import SwiftUI

struct DatePartControl: View {
    let label: String
    let subtitle: String?
    let minimum: Date?
    let maximum: Date?
    let indicator: InspectorRowIndicator?
    @Binding var value: Date

    var body: some View {
        InspectorRow(title: label, alignment: .top, indicator: indicator) {
            DatePartField(subtitle: subtitle, minimum: minimum, maximum: maximum, value: $value)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DateArrayPartControl: View {
    let label: String
    let subtitles: [String]
    let help: String?
    let minimum: Date?
    let maximum: Date?
    let indicator: InspectorRowIndicator?
    let values: [Binding<Date>]

    var body: some View {
        InspectorRow(title: label, alignment: .top, indicator: indicator) {
            if values.count > 2 {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            field(at: row * 2)
                            if row * 2 + 1 < values.count {
                                field(at: row * 2 + 1)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(values.indices, id: \.self) { index in
                        field(at: index)
                    }
                }
            }
        }
        .help(help ?? "")
    }

    private func field(at index: Int) -> some View {
        DatePartField(
            subtitle: subtitles.indices.contains(index) ? subtitles[index] : nil,
            minimum: minimum,
            maximum: maximum,
            value: values[index]
        )
        .frame(maxWidth: .infinity)
    }
}

private struct DatePartField: View {
    let subtitle: String?
    let minimum: Date?
    let maximum: Date?
    @Binding var value: Date

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            if minimum != nil || maximum != nil {
                picker(in: (minimum ?? .distantPast)...(maximum ?? .distantFuture))
            } else {
                picker
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(subtitle)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var picker: some View {
        DatePicker("", selection: $value, displayedComponents: [.date])
            .labelsHidden()
            .controlSize(.regular)
            .fixedSize()
    }

    private func picker(in range: ClosedRange<Date>) -> some View {
        DatePicker("", selection: $value, in: range, displayedComponents: [.date])
            .labelsHidden()
            .controlSize(.regular)
            .fixedSize()
    }
}

#Preview {
    @Previewable @State var dates = Array(repeating: Date.now, count: 4)
    PartControlPreview {
        VStack(spacing: 12) {
            DatePartControl(label: "Published", subtitle: "Single date", minimum: nil, maximum: nil, indicator: .preview, value: $dates[0])
            DateArrayPartControl(
                label: "Event dates",
                subtitles: ["Starts", "Ends"],
                help: nil,
                minimum: nil,
                maximum: nil,
                indicator: .preview,
                values: [$dates[0], $dates[1]]
            )
            DateArrayPartControl(
                label: "Milestones",
                subtitles: ["Plan", "Build", "Review", "Launch"],
                help: nil,
                minimum: nil,
                maximum: nil,
                indicator: .preview,
                values: [$dates[0], $dates[1], $dates[2], $dates[3]]
            )
        }
    }
}
