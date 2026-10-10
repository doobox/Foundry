import SwiftUI
import UniformTypeIdentifiers

struct CollectionPartControl: View {
    let label: String
    let collectionKey: PartProperty.Key
    let itemLabel: String
    let fields: [PartPropertyDefinition]
    @Binding var values: [PartProperty.Value]
    let part: PartNode
    let selectedParts: [PartNode]
    let currentPage: Page?
    let framework: Framework
    let assets: [ProjectAsset]
    let assetContents: ProjectAssetContents
    let pages: [Page]
    let folders: [PageFolder]
    let publicURL: String
    let editor: ProjectEditor
    let editsSharedDefinition: Bool
    let breakpoint: ResponsiveBreakpoint
    let importMedia: (URL, UTType) -> ProjectAsset?
    let selectedPrimitive: CanvasPrimitiveSelection?
    let selectPrimitive: (CanvasPrimitiveSelection?) -> Void

    @State private var selection: String?
    @State private var showsNavigator = false

    var body: some View {
        Group {
            navigator
            if let selectedIndex {
                ForEach(visibleFields(in: values[selectedIndex])) { field in
                    PartPropertyEditor(
                        definition: field,
                        part: part,
                        selectedParts: selectedParts,
                        currentPage: currentPage,
                        framework: framework,
                        assets: assets,
                        assetContents: assetContents,
                        pages: pages,
                        folders: folders,
                        publicURL: publicURL,
                        editor: editor,
                        editsSharedDefinition: editsSharedDefinition,
                        breakpoint: breakpoint,
                        importMedia: importMedia,
                        collectionRecord: recordBinding(at: selectedIndex),
                        collectionDefinitions: fields
                    )
                }
            }
        }
        .onAppear(perform: prepareSelection)
        .onChange(of: recordIDs) { _, _ in repairSelection() }
        .onChange(of: selectedPrimitive, initial: true) { _, selected in
            selectCanvasItem(selected)
        }
    }

    private var navigator: some View {
        InspectorRow(title: label, alignment: .center) {
            HStack(spacing: 5) {
                Button("Previous \(itemLabel)", systemImage: "chevron.left", action: selectPrevious)
                    .labelStyle(.iconOnly)
                    .disabled(values.count < 2)

                Button(action: showNavigator) {
                    HStack(spacing: 6) {
                        Text(selectedIndex.map(title(at:)) ?? "No \(itemLabel)s")
                            .foregroundStyle(selectedIndex == nil ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(itemLabel)
                .accessibilityValue(selectedIndex.map(title(at:)) ?? "No items")
                .popover(isPresented: $showsNavigator, arrowEdge: .trailing) {
                    CollectionNavigatorPopover(
                        itemLabel: itemLabel,
                        recordIDs: recordIDs,
                        selection: selectionBinding,
                        move: moveItems,
                        add: addItem,
                        duplicate: duplicateSelectedItem,
                        delete: removeSelectedItem
                    )
                }

                Button("Next \(itemLabel)", systemImage: "chevron.right", action: selectNext)
                    .labelStyle(.iconOnly)
                    .disabled(values.count < 2)
            }
        }
    }

    private var visibleDefinitions: [PartPropertyDefinition] {
        fields.filter(\.isInspectorVisible)
    }

    private func visibleFields(in record: PartProperty.Value) -> [PartPropertyDefinition] {
        let resolved = Dictionary(uniqueKeysWithValues: fields.map { field in
            (
                field.key.rawValue,
                PartCollectionValue.value(
                    fieldID: field.key.rawValue,
                    in: record,
                    at: field.isResponsive ? breakpoint : .mobile,
                    screens: framework.screens
                )
            )
        })
        return visibleDefinitions.filter {
            PartPackageVisibilityEvaluator.isVisible($0.visibleWhen, values: resolved)
        }
    }

    private var recordIDs: [String] {
        values.enumerated().map { recordID(at: $0.offset) }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { selection },
            set: { selectItem(id: $0) }
        )
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return values.firstIndex { PartCollectionValue.id(of: $0) == selection }
    }

    private func recordID(at index: Int) -> String {
        PartCollectionValue.id(of: values[index]) ?? "missing-\(index)"
    }

    private func title(at index: Int) -> String {
        PartCollectionValue.title(itemLabel: itemLabel, position: index)
    }

    private func recordBinding(at index: Int) -> Binding<PartProperty.Value> {
        Binding(
            get: { values.indices.contains(index) ? values[index] : PartCollectionValue.record(fields: fields) },
            set: { if values.indices.contains(index) { values[index] = $0 } }
        )
    }

    private func prepareSelection() {
        values = values.map { record in
            guard PartCollectionValue.id(of: record) == nil else { return record }
            return PartCollectionValue.record(fields: fields, overriding: record.objectValue ?? [:])
        }
        repairSelection()
    }

    private func repairSelection() {
        guard !recordIDs.isEmpty else {
            selection = nil
            return
        }
        if selection.map(recordIDs.contains) != true { selection = recordIDs[0] }
    }

    private func selectCanvasItem(_ selected: CanvasPrimitiveSelection?) {
        guard selected?.partID == part.id,
              selected?.propertyKey == collectionKey,
              let index = selected?.propertyPath.first,
              values.indices.contains(index) else { return }
        selection = recordID(at: index)
    }

    private func selectPrevious() {
        guard let selectedIndex, !values.isEmpty else { return }
        selectItem(id: recordID(at: selectedIndex == 0 ? values.count - 1 : selectedIndex - 1))
    }

    private func selectNext() {
        guard let selectedIndex, !values.isEmpty else { return }
        selectItem(id: recordID(at: selectedIndex == values.count - 1 ? 0 : selectedIndex + 1))
    }

    private func addItem() {
        let record = PartCollectionValue.record(fields: fields)
        values.append(record)
        selectItem(id: PartCollectionValue.id(of: record))
    }

    private func removeSelectedItem() {
        guard let selectedIndex else { return }
        values.remove(at: selectedIndex)
        let nextSelection = values.indices.contains(selectedIndex)
            ? PartCollectionValue.id(of: values[selectedIndex])
            : values.last.flatMap(PartCollectionValue.id)
        selectItem(id: nextSelection)
    }

    private func duplicateSelectedItem() {
        guard let selectedIndex else { return }
        var valuesByField = values[selectedIndex].objectValue ?? [:]
        valuesByField.removeValue(forKey: PartCollectionValue.identityKey)
        let duplicate = PartCollectionValue.record(fields: fields, overriding: valuesByField)
        values.insert(duplicate, at: selectedIndex + 1)
        selectItem(id: PartCollectionValue.id(of: duplicate))
    }

    private func showNavigator() {
        showsNavigator = true
    }

    private func selectItem(id: String?) {
        selection = id
        guard let id,
              let index = recordIDs.firstIndex(of: id) else {
            selectPrimitive(nil)
            return
        }
        selectPrimitive(.init(partID: part.id, propertyKey: collectionKey, propertyPath: [index]))
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        values.move(fromOffsets: source, toOffset: destination)
        selectItem(id: selection)
    }

}
