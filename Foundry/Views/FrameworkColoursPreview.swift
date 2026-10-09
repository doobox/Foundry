import AppKit
import Observation
import SwiftUI

/// Palette editing state. The project view supplies document persistence through onChange;
/// previews and tests can still use this independently.
@Observable
final class FrameworkColourPreviewModel {
    private(set) var storedPalettes: [ColourPalette] {
        didSet {
            if !synchronizing, oldValue != storedPalettes { onChange?(storedPalettes, pendingSession) }
        }
    }
    @ObservationIgnored var onChange: (([ColourPalette], UUID?) -> Void)?
    private var synchronizing = false
    private var pendingSession: UUID?

    func synchronize(_ values: [ColourPalette]) {
        guard values != storedPalettes else { return }
        synchronizing = true
        storedPalettes = values
        lastEditSession = nil
        synchronizing = false
    }
    var palettes: [PreviewColourPalette] {
        get { storedPalettes.map { PreviewColourPalette(stored: $0) } }
        set { storedPalettes = newValue.map { $0.storedValue } }
    }
    private var lastEditSession: UUID?

    init(storedPalettes: [ColourPalette]? = nil) {
        self.storedPalettes = storedPalettes ?? PreviewColourPalette.samples.map { $0.storedValue }
    }

    func binding(for snapshot: PreviewColourPalette) -> Binding<PreviewColourPalette> {
        let id = snapshot.id
        return Binding(
            get: { self.storedPalettes.first(where: { $0.id == id }).map { PreviewColourPalette(stored: $0) } ?? snapshot },
            set: { value in
                guard let index = self.storedPalettes.firstIndex(where: { $0.id == id }) else { return }
                self.storedPalettes[index] = value.storedValue
            })
    }

    func delete(id: String) {
        storedPalettes.removeAll { $0.id == id && $0.origin == .custom }
    }

    func update(_ palette: PreviewColourPalette, session: UUID, undoManager: UndoManager?) {
        guard let index = storedPalettes.firstIndex(where: { $0.id == palette.id }) else { return }
        let stored = palette.storedValue
        guard storedPalettes[index] != stored else { return }
        if onChange == nil && lastEditSession != session {
            registerRestore(storedPalettes[index], undoManager: undoManager)
            lastEditSession = session
        }
        pendingSession = session
        storedPalettes[index] = stored
        pendingSession = nil
    }

    private func registerRestore(_ value: ColourPalette, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            guard let index = model.storedPalettes.firstIndex(where: { $0.id == value.id }) else { return }
            model.registerRestore(model.storedPalettes[index], undoManager: undoManager)
            model.storedPalettes[index] = value
            model.lastEditSession = nil
        }
        undoManager?.setActionName("Edit Colour")
    }

    func add() {
        let names = Set(storedPalettes.map(\.name))
        var number = 1
        while names.contains("New Colour \(number)") { number += 1 }
        var palette = try! BootstrapColourCatalogue.palette(role: .primary, hue: "orange").duplicated()
        palette.name = "New Colour \(number)"
        storedPalettes.insert(palette, at: 0)
    }

    func duplicate(_ palette: PreviewColourPalette) {
        var copy = try! palette.storedValue.duplicated()
        let names = Set(storedPalettes.map(\.name))
        let base = palette.name + " Copy"
        copy.name = base
        var number = 2
        while names.contains(copy.name) {
            copy.name = "\(base) \(number)"
            number += 1
        }
        storedPalettes.insert(copy, at: 0)
    }
}

struct PreviewColourPalette: Identifiable, Equatable {
    enum Group: String, CaseIterable {
        case custom = "Custom Colours"
        case theme = "Bootstrap Theme Colours"
        case layer = "Bootstrap Layer Colours"
        case standard = "Bootstrap Hue Scales"
    }
    static let steps = ColourShade.bootstrapLabels
    static let bootstrapLayerIDs: Set<String> = ["framework.background", "framework.foreground", "framework.border"]
    var storedValue: ColourPalette
    var id: String { storedValue.id }
    var name: String {
        get { storedValue.name }
        set { storedValue.name = newValue }
    }
    var bootstrapHue: String? { storedValue.bootstrapHue }
    var single: Bool { storedValue.single }
    var lightDefaultShade: Int { storedValue.lightDefaultShade.rawValue - 1 }
    var darkDefaultShade: Int { storedValue.darkDefaultShade.rawValue - 1 }
    var group: Group {
        switch storedValue.origin {
        case .custom: .custom
        case .standard: .standard
        case .framework: Self.bootstrapLayerIDs.contains(id) ? .layer : .theme
        }
    }
    init(stored: ColourPalette) { storedValue = stored }
    func colour(at index: Int) -> Color { Color(hex: storedValue.shades[index]) ?? .gray }
    static var samples: [Self] { ColourPaletteDefaults.make().map { Self(stored: $0) } }
}

struct FrameworkColoursPreview: View {
    @Bindable var model: FrameworkColourPreviewModel
    var canEditFramework = false
    var requestDelete: ((PreviewColourPalette) -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(PreviewColourPalette.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(model.palettes.filter { $0.group == group }) { palette in
                            if group == .theme || group == .layer {
                                BootstrapHuePicker(palette: palette, canEdit: canEditFramework) { hue in
                                    guard let role = FrameworkColorRole(rawValue: palette.id.replacingOccurrences(of: "framework.", with: "")) else { return }
                                    model.update(PreviewColourPalette(stored: BootstrapColourCatalogue.palette(role: role, hue: hue)),
                                        session: UUID(), undoManager: undoManager)
                                }
                            }
                            if group == .custom {
                                BootstrapCustomColourEditor(palette: palette, update: { value, session in
                                    model.update(value, session: session, undoManager: undoManager)
                                }, duplicate: {
                                    model.duplicate(palette)
                                    withAnimation { scrollPosition.scrollTo(edge: .top) }
                                }, delete: {
                                    if let requestDelete { requestDelete(palette) }
                                    else { model.delete(id: palette.id) }
                                })
                            } else {
                                PreviewColourRibbon(palette: palette,
                                    duplicate: {
                                        model.duplicate(palette)
                                        withAnimation { scrollPosition.scrollTo(edge: .top) }
                                    },
                                    delete: {
                                        if let requestDelete { requestDelete(palette) }
                                        else { model.delete(id: palette.id) }
                                    })
                            }
                        }
                        if group == .custom && !model.palettes.contains(where: { $0.group == .custom }) {
                            Text("Add a named colour to try your own palette.").foregroundStyle(.secondary)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(group.rawValue).font(.headline).accessibilityAddTraits(.isHeader)
                                Spacer()
                                if group == .custom {
                                    Button("Add Colour", systemImage: "plus", action: model.add)
                                }
                            }
                        }
                        .padding(.top, group == .custom ? 0 : 18)
                    }
                }
            }
            .padding(28)
        }
        .controlSize(.small)
        .scrollPosition($scrollPosition)
    }
}

struct PreviewColourRibbon: View {
    let palette: PreviewColourPalette
    let duplicate: () -> Void
    let delete: () -> Void
    var editBase: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(palette.name).fontWeight(.medium)
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                        .labelStyle(.iconOnly).help("Duplicate to Custom Colours")
                    if palette.group == .custom {
                        Button("Delete", systemImage: "trash", action: delete).labelStyle(.iconOnly)
                    }
                }.buttonStyle(.borderless)
            }
            .frame(width: 150, alignment: .leading).padding(.leading, 12)
            HStack(spacing: 0) {
                ForEach(palette.single ? [6] : Array(ColourShade.allCases.indices), id: \.self) { index in
                    if index == 6, let editBase {
                        Button(action: editBase) {
                            PreviewColourSwatch(palette: palette, index: index)
                        }
                        .buttonStyle(.plain)
                        .help("Edit the base colour — regenerates the whole strip")
                        .accessibilityLabel("Edit \(palette.name) base colour, 500")
                    } else {
                        PreviewColourSwatch(palette: palette, index: index)
                    }
                }
            }.frame(minWidth: 440)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PreviewColourSwatch: View {
    let palette: PreviewColourPalette
    let index: Int
    var body: some View {
        let colour = palette.colour(at: index)
        let rgb = NSColor(colour).usingColorSpace(.sRGB)
        let light = (rgb.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent } ?? 0) > 0.57
        Text(palette.single ? palette.name : PreviewColourPalette.steps[index])
            .font(.caption2.monospacedDigit())
            .foregroundStyle(light ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(height: 62)
            .background { Rectangle().fill(colour) }
            .help("\(palette.name) · \(PreviewColourPalette.steps[index]) · sRGB preview \(palette.storedValue.shades[index])")
            .accessibilityLabel("\(palette.name), shade \(PreviewColourPalette.steps[index])")
    }
}

#Preview {
    FrameworkColoursPreview(model: FrameworkColourPreviewModel()).frame(width: 760, height: 650)
}
