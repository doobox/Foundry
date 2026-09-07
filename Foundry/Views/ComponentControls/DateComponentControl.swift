import SwiftUI

struct DateComponentControl: View {
    let label: String
    let indicator: InspectorRowIndicator?
    @Binding var value: Date

    var body: some View {
        InspectorRow(title: label, alignment: .center, indicator: indicator) {
            DatePicker("", selection: $value, displayedComponents: [.date])
                .labelsHidden()
        }
    }
}

#Preview {
    @Previewable @State var date = Date.now
    ComponentControlPreview {
        DateComponentControl(label: "Date", indicator: .preview, value: $date)
    }
}
