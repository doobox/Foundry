import AppKit
import Foundation
import SwiftUI

nonisolated enum AppPreferenceKey {
    static let previewApplication = "preview.destination"
    static let appearance = "appearance"
    static let externalPreviewAutoReload = "preview.externalAutoReload"
    static let overridesCanvasBackground = "canvas.background.override"
    static let canvasBackgroundColor = "canvas.background.color"
    static let enablesCanvasWebInspector = "canvas.webInspector.enabled"
    static let showsDeveloperPanel = "developer.panel.visible"
    static let showsHiddenBlocks = "developer.blocks.showHidden"
    static let automaticallyChecksBlockUpdates = "blocks.updates.automatic"
    static let blockLibraryIconSize = "blocks.library.iconSize"
    static let blockLibraryArrangement = "blocks.library.arrangement"
    static let validatesBlocksOnLoad = "blocks.validation.onLoad"
    static let blockValidationMode = "blocks.validation.mode"
}

nonisolated enum BlockValidationMode: String, CaseIterable, Identifiable {
    case off
    case developmentPacks
    case allPacks

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .developmentPacks: "Dev Packs"
        case .allPacks: "All Packs"
        }
    }

    func validates(_ url: URL) -> Bool {
        switch self {
        case .off:
            return false
        case .developmentPacks:
            return url.pathComponents.contains {
                ($0 as NSString).pathExtension.caseInsensitiveCompare("foundrydevpack") == .orderedSame
            }
        case .allPacks:
            return true
        }
    }
}

nonisolated enum BlockValidationPreference {
    static var mode: BlockValidationMode {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: AppPreferenceKey.blockValidationMode),
           let mode = BlockValidationMode(rawValue: rawValue) {
            return mode
        }
        // Preserve the former Boolean preference when upgrading.
        return defaults.bool(forKey: AppPreferenceKey.validatesBlocksOnLoad) ? .allPacks : .off
    }
}

nonisolated enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

nonisolated enum CanvasBackgroundPreference {
    static let defaultColor = "#5C5D60"
}

nonisolated enum PreviewApplicationSelection {
    static let systemDefault = "systemDefault"
}

@MainActor
struct PreviewApplication: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let applicationURL: URL

    var id: String { bundleIdentifier }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

@MainActor
enum PreviewApplicationCatalog {
    static func applications(workspace: NSWorkspace = .shared) -> [PreviewApplication] {
        guard let webURL = URL(string: "https://example.com") else { return [] }
        var applicationsByIdentifier: [String: PreviewApplication] = [:]

        for applicationURL in workspace.urlsForApplications(toOpen: webURL) {
            guard let bundle = Bundle(url: applicationURL),
                  let identifier = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? applicationURL.deletingPathExtension().lastPathComponent
            applicationsByIdentifier[identifier] = PreviewApplication(
                bundleIdentifier: identifier,
                name: name,
                applicationURL: applicationURL
            )
        }

        return applicationsByIdentifier.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func defaultApplication(workspace: NSWorkspace = .shared) -> PreviewApplication? {
        guard let webURL = URL(string: "https://example.com"),
              let applicationURL = workspace.urlForApplication(toOpen: webURL),
              let bundle = Bundle(url: applicationURL),
              let identifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        return PreviewApplication(bundleIdentifier: identifier, name: name, applicationURL: applicationURL)
    }
}
