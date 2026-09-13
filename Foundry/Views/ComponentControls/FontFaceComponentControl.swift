import SwiftUI

struct FontFaceComponentControl: View {
    let label: String
    let options: FontFaceOptions
    let indicator: InspectorRowIndicator?
    @Binding var weight: Double
    @Binding var style: String
    let editsWeight: Bool

    private var unavailable: Bool {
        options.missing || (options.verified && (editsWeight ? !options.weights.contains(Int(weight)) : !options.styles.contains(style)))
    }

    var body: some View {
        InspectorRow(title: label, indicator: indicator) {
            VStack(alignment: .leading, spacing: 4) {
                if editsWeight {
                    if options.variableWeight, let minimum = options.weights.first, let maximum = options.weights.last {
                        HStack(spacing: 4) {
                            TextField(label, value: variableWeightBinding, format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                            InspectorStepper(value: variableWeightBinding, range: Double(minimum)...Double(maximum), increment: 1, accessibilityLabel: label)
                        }
                    } else {
                        Picker(label, selection: $weight) {
                            if !options.weights.contains(Int(weight)) {
                                Text("\(Int(weight))\(unavailable ? " — Unavailable" : "")").tag(weight)
                            }
                            ForEach(options.weights, id: \.self) { value in
                                Text(String(value)).tag(Double(value))
                            }
                        }
                        .pickerStyle(.menu)
                        .buttonSizing(.flexible)
                        .labelsHidden()
                    }
                } else {
                    Picker(label, selection: $style) {
                        if !options.styles.contains(style) {
                            Text("\(style.capitalized) — Unavailable").tag(style)
                        }
                        ForEach(options.styles, id: \.self) { value in
                            Text(value.capitalized).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .buttonSizing(.flexible)
                    .labelsHidden()
                }
                if unavailable {
                    Label("Unavailable in this font. The browser may substitute a face.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .help(options.verified ? label : "Standard CSS choices. Face availability is not verified for this font; the browser may substitute or synthesize a face.")
    }

    private var variableWeightBinding: Binding<Double> {
        Binding(get: { weight }, set: { value in
            guard value.isFinite, let closest = options.weights.min(by: { abs(Double($0) - value) < abs(Double($1) - value) }) else { return }
            weight = Double(closest)
        })
    }
}
