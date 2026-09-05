import Foundation
import Observation

@MainActor
@Observable
final class ComponentUpdateManager {
    static let shared = ComponentUpdateManager()

    enum ItemState: Equatable {
        case available
        case updating(Double)
        case installed
        case failed(String)
    }

    struct Item: Identifiable {
        let update: FoundryPackUpdater.AvailableUpdate
        var state: ItemState = .available
        var id: String { update.id }
    }

    private(set) var items: [Item] = []
    private(set) var isChecking = false
    private(set) var completedMessage: String?
    private(set) var checkMessage: String?
    private var hasAutomaticallyChecked = false
    private var automaticCheckGeneration: UInt64 = 0

    private init() {}

    var isUpdating: Bool {
        items.contains { if case .updating = $0.state { true } else { false } }
    }

    var hasActionableUpdates: Bool {
        items.contains { item in
            if case .installed = item.state { return false }
            return true
        }
    }

    func checkAll() async {
        guard !isChecking, !isUpdating else { return }
        isChecking = true
        defer { isChecking = false }
        completedMessage = nil
        checkMessage = nil
        let urls = updateablePackURLs()
        var found: [FoundryPackUpdater.AvailableUpdate] = []
        var failures: [String] = []
        let urlsByPackID = Dictionary(grouping: urls) { url in
            (try? FoundryPackLoader.load(from: url).identifier) ?? url.standardizedFileURL.path
        }
        let duplicatePackIDs = Set(urlsByPackID.compactMap { key, values in values.count > 1 ? key : nil })
        for packID in duplicatePackIDs.sorted() {
            failures.append("Multiple installed component packs use the id \(packID); none of them were checked.")
        }
        let unambiguousURLs = urls.filter { url in
            guard let packID = try? FoundryPackLoader.load(from: url).identifier else { return true }
            return !duplicatePackIDs.contains(packID)
        }
        await withTaskGroup(of: CheckResult.self) { group in
            for url in unambiguousURLs {
                group.addTask {
                    do { return .update(try await FoundryPackUpdater.check(for: url)) }
                    catch FoundryPackUpdateError.noCompatibleRelease { return .upToDate }
                    catch is CancellationError { return .cancelled }
                    catch { return .failed(url.deletingPathExtension().lastPathComponent, error.localizedDescription) }
                }
            }
            for await result in group {
                switch result {
                case .update(let update): found.append(update)
                case .failed(let pack, let message): failures.append("\(pack): \(message)")
                case .upToDate: break
                case .cancelled: failures.append("The update check was cancelled.")
                }
            }
        }
        guard !Task.isCancelled else {
            checkMessage = "The update check was cancelled."
            return
        }
        items = found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { Item(update: $0) }
        if failures.isEmpty {
            checkMessage = items.isEmpty ? "All components are up to date." : nil
        } else {
            checkMessage = "Could not check \(failures.count) component pack\(failures.count == 1 ? "" : "s"). \(failures.joined(separator: " "))"
        }
    }

    func checkAllManually() async {
        hasAutomaticallyChecked = true
        automaticCheckGeneration &+= 1
        await checkAll()
    }

    func automaticCheckIfNeeded() async -> Bool {
        guard !hasAutomaticallyChecked else { return false }
        hasAutomaticallyChecked = true
        let generation = automaticCheckGeneration
        let delaySeconds = Int.random(in: 30...120)
        do {
            try await Task.sleep(for: .seconds(delaySeconds))
        } catch {
            hasAutomaticallyChecked = false
            return false
        }
        guard generation == automaticCheckGeneration else { return false }
        await checkAll()
        return !items.isEmpty
    }

    func install(id: String) async {
        guard !isChecking,
              let item = items.first(where: { $0.id == id }) else { return }
        switch item.state {
        case .available, .failed:
            break
        case .updating, .installed:
            return
        }
        let update = item.update
        setState(.updating(0.1), for: id)
        do {
            _ = try await FoundryPackUpdater.checkAndInstallUpdate(for: update.sourceURL) { value in
                self.setState(.updating(value), for: id)
            }
            try Task.checkCancellation()
            setState(.installed, for: id)
            ComponentPackageCatalog.shared.reloadAllPacks()
        } catch is CancellationError {
            setState(.available, for: id)
            checkMessage = "The component update was cancelled."
        } catch {
            setState(.failed(error.localizedDescription), for: id)
        }
        updateCompletionMessage()
    }

    func installAll() async {
        let ids = items.compactMap { item -> String? in
            if case .available = item.state { return item.id }
            if case .failed = item.state { return item.id }
            return nil
        }
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { await self.install(id: id) } }
        }
    }

    private func updateCompletionMessage() {
        guard !items.isEmpty, items.allSatisfy({
            if case .installed = $0.state { return true }
            if case .failed = $0.state { return true }
            return false
        }) else { return }
        let installedCount = items.filter { if case .installed = $0.state { true } else { false } }.count
        completedMessage = installedCount == items.count
            ? "All component updates were installed successfully."
            : "Installed \(installedCount) of \(items.count) component updates."
    }

    private func setState(_ state: ItemState, for id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }

    private enum CheckResult: Sendable {
        case update(FoundryPackUpdater.AvailableUpdate)
        case upToDate
        case failed(String, String)
        case cancelled
    }

    private func updateablePackURLs() -> [URL] {
        guard let root = try? FoundryPackLoader.installedPacksURL() else { return [] }
        return FoundryPackLoader.packURLs(in: root)
            .filter { (try? FoundryPackLoader.load(from: $0).metadata.updates) != nil }
    }
}
