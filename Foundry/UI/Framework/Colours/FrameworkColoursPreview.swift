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

    private func resetting(_ group: PreviewColourPalette.Group) -> [ColourPalette] {
        return storedPalettes.map { palette in
            guard palette.origin == .framework, PreviewColourPalette(stored: palette).group == group,
                  let role = FrameworkColorRole(rawValue: BootstrapPaletteTheme.definitionRole(palette)) else { return palette }
            return BootstrapColourCatalogue.palette(role: role)
        }
    }

    func canReset(_ group: PreviewColourPalette.Group) -> Bool {
        resetting(group) != storedPalettes
    }

    func reset(_ group: PreviewColourPalette.Group, undoManager: UndoManager?) {
        restorePalettes(resetting(group), undoManager: undoManager)
    }

    private func restorePalettes(_ values: [ColourPalette], undoManager: UndoManager?) {
        guard values != storedPalettes else { return }
        if onChange == nil {
            let previous = storedPalettes
            undoManager?.registerUndo(withTarget: self) { model in
                model.restorePalettes(previous, undoManager: undoManager)
            }
            undoManager?.setActionName("Reset Theme Colours")
        }
        pendingSession = UUID()
        storedPalettes = values
        pendingSession = nil
        lastEditSession = nil
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

    func canAddTheme(named name: String, excluding id: String? = nil) -> Bool {
        BootstrapPaletteTheme.validCustomRole(name)
            && !storedPalettes.contains { $0.origin == .custom && $0.id != id && $0.name == name }
    }

    func renameTheme(id: String, name: String, undoManager: UndoManager?) {
        guard canAddTheme(named: name, excluding: id),
              var palette = storedPalettes.first(where: { $0.id == id && $0.origin == .custom }) else { return }
        let oldRole = palette.name
        palette.name = name
        palette.bootstrapTokens = Dictionary(uniqueKeysWithValues: palette.bootstrapTokens.map { token, value in
            (palette.colourKind == .theme && token.hasPrefix(oldRole + "-") ? name + token.dropFirst(oldRole.count) : token, value)
        })
        update(PreviewColourPalette(stored: palette), session: UUID(), undoManager: undoManager)
    }

    func addTheme(named name: String, kind: BootstrapColourKind = .theme) {
        guard canAddTheme(named: name) else { return }
        let role = FrameworkColorRole(rawValue: kind.sourceRole) ?? .primary
        let source = storedPalettes.resolvedPalette(id: "framework." + role.rawValue)
            ?? BootstrapColourCatalogue.palette(role: role)
        let preferredID = "custom." + name
        let id = storedPalettes.contains { $0.id == preferredID } ? "custom." + UUID().uuidString.lowercased() : preferredID
        var palette = try! ColourPalette(id: id, name: name, origin: .custom,
            shades: source.shades, lightDefaultShade: .seven, darkDefaultShade: .seven)
        palette.customKind = kind
        storedPalettes.append(BootstrapPaletteTheme.applying(source, to: palette))
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
        case theme = "Bootstrap Theme Colours"
        case surface = "Bootstrap Surfaces"
        case foreground = "Bootstrap Foregrounds"
        case border = "Bootstrap Borders"
        case link = "Bootstrap Link Colours"
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
        if storedValue.origin == .standard { return .standard }
        switch storedValue.colourKind {
        case .theme: return .theme
        case .surface: return .surface
        case .foreground: return .foreground
        case .border: return .border
        case .link: return .link
        }
    }
    init(stored: ColourPalette) { storedValue = stored }
    func colour(at index: Int) -> Color { Color(hex: storedValue.shades[index]) ?? .gray }
    static var samples: [Self] { ColourPaletteDefaults.make().map { Self(stored: $0) } }
}

struct FrameworkColoursPreview: View {
    @Bindable var model: FrameworkColourPreviewModel
    @Environment(\.undoManager) private var undoManager
    var canEditFramework = true
    var requestDelete: ((PreviewColourPalette) -> Void)? = nil
    var tokenEditor: ProjectEditor? = nil
    var framework: Framework = .standard
    @State private var mode: SiteAppearance = .light
    @State private var previews: [String: String] = [:]
    @State private var error: String?
    @State private var addingColour = false
    @State private var newColourName = ""
    @State private var addingKind: BootstrapColourKind = .theme

    private var css: String {
        var framework = self.framework
        framework.colourPalettes = model.storedPalettes
        return BootstrapColourCatalogue.sourceCSS + BootstrapColorCSS.export(framework: framework, mode: .both) + BootstrapThemeCSS.render(framework: framework)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach([BootstrapColourKind.theme, .surface, .foreground, .border], id: \.self) { kind in
                    let group = PreviewColourPalette(stored: BootstrapColourCatalogue.palette(role: FrameworkColorRole(rawValue: kind.sourceRole)!)).group
                    FrameworkEditorCard {
                        HStack(spacing: 8) {
                            Text(group.rawValue).font(.headline).accessibilityAddTraits(.isHeader)
                                Button("Add custom colour", systemImage: "plus") {
                                    newColourName = ""
                                    addingKind = kind
                                    addingColour = true
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .frame(width: 24, height: 24)
                                .help("Add colour")
                            Spacer()
                            if model.canReset(group) {
                                Button("Reset", systemImage: "arrow.counterclockwise") {
                                    model.reset(group, undoManager: undoManager)
                                }
                                .disabled(!canEditFramework)
                                .help("Restore this section's Bootstrap defaults in both modes. Custom colours are kept.")
                            }
                        }
                        let palettes = model.palettes.filter { $0.group == group }
                        ForEach(palettes) { palette in
                            BootstrapThemeTokenEditor(model: model, palette: palette, mode: mode,
                                                      previews: previews, canEdit: palette.storedValue.origin == .custom || canEditFramework,
                                                      delete: palette.storedValue.origin == .custom ? { requestDelete?(palette) } : nil)
                            if palette.id != palettes.last?.id { Divider() }
                        }
                    }
                }
                if let tokenEditor {
                    BootstrapTokenColoursCard(section: .linkColours, framework: framework, editor: tokenEditor, mode: mode,
                        model: model, customPreviews: previews, requestDelete: requestDelete, addCustom: {
                            addingKind = .link
                            newColourName = ""
                            addingColour = true
                        })
                }
            }.padding(20)
        }
        .controlSize(.small)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    mode = .light
                } label: {
                    Label {
                        Text("Light")
                    } icon: {
                        Image(systemName: mode == .light ? "sun.max.fill" : "sun.max")
                            .renderingMode(.original)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color(nsColor: mode == .light ? .labelColor : .secondaryLabelColor))
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityAddTraits(mode == .light ? .isSelected : [])
                .help("Preview and edit light theme colours")
                Button {
                    mode = .dark
                } label: {
                    Label {
                        Text("Dark")
                    } icon: {
                        Image(systemName: mode == .dark ? "moon.fill" : "moon")
                            .renderingMode(.original)
                            .foregroundStyle(Color(nsColor: mode == .dark ? .labelColor : .secondaryLabelColor))
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityAddTraits(mode == .dark ? .isSelected : [])
                .help("Preview and edit dark theme colours")
            }
        }
        .onChange(of: mode) { previews = [:] }
        .task(id: css + mode.rawValue) { await resolvePreviews() }
        .sheet(isPresented: $addingColour) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add custom colour").font(.headline)
                TextField("Name, e.g. brand", text: $newColourName)
                Text("Use a unique lowercase name with letters, numbers and hyphens, starting with a letter. Edit existing Bootstrap themes directly instead of reusing their names.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { addingColour = false }.keyboardShortcut(.cancelAction)
                    Button("Add colour") {
                        model.addTheme(named: newColourName, kind: addingKind)
                        addingColour = false
                    }.disabled(!model.canAddTheme(named: newColourName))
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 400)
        }
    }

    private func resolvePreviews() async {
        let snapshot = css
        let appearance = mode
        let allTokens = FrameworkColorRole.allCases.flatMap { BootstrapColourCatalogue.tokens(for: $0.rawValue) }
            + model.storedPalettes.filter { $0.origin == .custom }.flatMap(\.colourTokens)
        let tokens = Array(Set(allTokens)).sorted()
        do {
            let values = try await BootstrapScalePreviewResolver().resolve(
                expressions: tokens.map { "var(--bs-\($0))" }, css: snapshot, mode: appearance.rawValue)
            try Task.checkCancellation()
            guard snapshot == css, appearance == mode else { return }
            previews = Dictionary(uniqueKeysWithValues: zip(tokens, values))
            error = nil
        } catch is CancellationError {
            // A new edit or mode superseded the preview.
        } catch {
            guard !Task.isCancelled else { return }
            previews = [:]
            self.error = "Could not resolve Bootstrap colour previews. Reopen the editor to retry."
        }
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
                    if palette.storedValue.origin == .custom {
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
