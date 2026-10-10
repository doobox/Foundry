import Foundation

/// A value snapshot of the last submitted scene. It is eligible as a baseline
/// only after WebKit acknowledges its revision. No background task mutates it.
nonisolated struct CanvasScene: Sendable {
    let environment: CanvasRenderCache.Environment
    let language: String
    let packages: [String]
    let roots: [String]
    /// Document order, kept as identities. Formatting every instance's UUID
    /// into a string on every render was pure overhead: only the handful of
    /// instructions that reach WebKit need the text form.
    let order: [UUID]
    let inputs: [UUID: CanvasSceneInput]
    let artifacts: [UUID: CanvasSceneArtifact]
    let renderedInstanceCount: Int
    let paths: [UUID: [Int]]
    let breakpoint: ResponsiveBreakpoint
    let examinedInstanceCount: Int

    private static func retainUtilityOverrides(in node: inout PartNode) {
        // Ordinary controls are already resolved for this viewport. Bootstrap
        // utility groups retain base values and need overrides to emit classes.
        let keys = Set(node.type.definition.package?.manifest.resolvedProperties
            .filter { $0.controlGroupSource?.type.generatesBootstrapClasses == true }.map(\.id) ?? [])
        node.responsiveOverrides = node.responsiveOverrides?.filter { keys.contains($0.key.rawValue) }
        if node.responsiveOverrides?.isEmpty == true { node.responsiveOverrides = nil }
    }

    static func render(renderer: HTMLPageRenderer, page: Page, language: String,
                       framework: Framework, assets: ProjectAssetContents,
                       breakpoint: ResponsiveBreakpoint, packageRevision: Int,
                       previous: Self?, consecutiveImpact: ProjectMutationImpact? = nil) throws -> (scene: Self, result: CanvasRenderResult) {
        try Task.checkCancellation()
        let localIDs: [UUID]?
        switch consecutiveImpact {
        case .partProperty(let id, _): localIDs = [id]
        case .partProperties(let ids, _): localIDs = ids
        default: localIDs = nil
        }
        // Breakpoint is a per-instance input, not a reason to discard the scene.
        let environment = CanvasRenderCache.Environment(site: renderer.site, page: page,
            framework: framework, assets: assets, breakpoint: .mobile,
            appearance: renderer.appearance, packageRevision: packageRevision,
            knownRoutes: localIDs == nil ? nil : previous?.environment.routes)
        let candidate = previous.flatMap {
            $0.environment == environment && $0.language == language ? $0 : nil
        }
        let baseline = candidate
        // A consecutive property event cannot alter tree topology or package
        // membership. Use the acknowledged scene's paths instead of walking
        // and resolving every instance. Skipped events/undo/structure/context
        // changes go through the complete input comparison below.
        if let baseline, let localIDs, baseline.breakpoint == breakpoint {
            var targets: [(UUID, PartNode)] = []
            for id in Set(localIDs) {
                guard let path = baseline.paths[id] else { continue }
                var siblings = page.parts
                var target: PartNode?
                for index in path {
                    guard siblings.indices.contains(index) else { target = nil; break }
                    target = siblings[index]
                    siblings = siblings[index].children
                }
                if let target, target.id == id { targets.append((id, target)) }
            }
            if targets.count == Set(localIDs).count {
                // A property event cannot add or drop a package.
                let packages = baseline.packages
                let renderer = renderer.preparedForShells(environment: environment,
                                                          liveIDs: Set(baseline.inputs.keys))
                var inputs = baseline.inputs, artifacts = baseline.artifacts
                var html: [String: String] = [:], styles: [String: String] = [:]
                var count = 0
                for (id, source) in targets {
                    try Task.checkCancellation()
                    guard let oldInput = inputs[id], let old = artifacts[id] else { continue }
                    var own = source.resolved(at: breakpoint, screens: framework.screens)
                    retainUtilityOverrides(in: &own)
                    own.children = oldInput.node.children
                    let input = CanvasSceneInput(node: own, globalID: oldInput.globalID,
                        parentID: oldInput.parentID, slot: oldInput.slot, dropZone: oldInput.dropZone)
                    guard input != oldInput else { continue }
                    let artifact = renderer.renderShell(input, page: page, framework: framework, assets: assets)
                    inputs[id] = input; artifacts[id] = artifact; count += 1
                    if artifact.html != old.html { html[id.uuidString] = artifact.html }
                    if artifact.css != old.css { styles[id.uuidString] = artifact.css }
                }
                try Task.checkCancellation()
                return (Self(environment: environment, language: language, packages: packages,
                    roots: baseline.roots, order: baseline.order, inputs: inputs, artifacts: artifacts,
                    renderedInstanceCount: count, paths: baseline.paths, breakpoint: breakpoint,
                    examinedInstanceCount: targets.count),
                    .scene(.init(html: html, styles: styles, removed: [], roots: nil,
                        styleMoves: styleMoves(
                            from: styleSequence(order: baseline.order, artifacts: baseline.artifacts),
                            to: styleSequence(order: baseline.order, artifacts: artifacts)))))
            }
        }
        // A structural edit moves instances; it never rewrites the values of
        // the ones already on the page. Existing instances can therefore be
        // confirmed in place instead of being resolved and value-compared, so
        // adding one part stops costing a pass over every part.
        let structuralOnly: Bool
        switch consecutiveImpact {
        case .partStructure: structuralOnly = baseline?.breakpoint == breakpoint
        default: structuralOnly = false
        }
        // Carry the acknowledged tables forward and patch them. Rebuilding
        // them entry by entry copies every instance's values on every edit,
        // which is the other half of what made a full page feel heavy.
        var inputs = baseline?.inputs ?? [:]
        var paths = baseline?.paths ?? [:]
        var order: [UUID] = []
        var packages: [String] = []
        var packageIdentifiers: Set<String> = []
        var live: Set<UUID> = []
        var rebuilt: [UUID] = []
        var examinedCount = 0
        order.reserveCapacity(baseline?.order.count ?? 0)
        live.reserveCapacity(baseline?.inputs.count ?? 0)
        func collect(_ nodes: [PartNode], parentID: UUID? = nil, globalID: UUID? = nil,
                     parentPackage: LoadedPartPackage? = nil, parentPath: [Int] = []) throws {
            // Slots and drop zones belong to the parent, so resolve them once
            // for the whole sibling list. Building each drop zone's identifier
            // per child meant allocating strings for every part on the page.
            let slots = parentPackage?.renderDefinition.slots ?? []
            let defaultSlot = parentPackage.flatMap { $0.hasDropZone ? nil : slots.first }
            let dropZoneSlotIDs = parentPackage.map { package in
                package.dropZoneNames.map { package.dropZoneSlotID(for: $0) }
            } ?? []
            for (index, source) in nodes.enumerated() {
                try Task.checkCancellation()
                order.append(source.id)
                live.insert(source.id)
                let path = parentPath + [index]
                if paths[source.id] != path { paths[source.id] = path }
                let ownPackage = source.type.definition.package
                if let identifier = ownPackage?.manifest.identifier,
                   packageIdentifiers.insert(identifier).inserted {
                    packages.append(identifier)
                }
                let inheritedGlobal = source.reusableDefinitionID ?? globalID
                let slot: PartPackageSlot?
                if parentPackage == nil {
                    slot = nil
                } else if let slotID = source.slotID {
                    slot = slots.first { $0.id == slotID }
                } else {
                    slot = defaultSlot
                }
                let dropZone: String?
                if parentPackage == nil || slot != nil {
                    dropZone = nil
                } else {
                    dropZone = dropZoneSlotIDs.enumerated().first { index, slotID in
                        source.slotID == slotID || (index == 0 && source.slotID == nil)
                    }?.element
                }
                let existing = inputs[source.id]
                let isConfirmed = structuralOnly && existing.map { stored in
                    stored.parentID == parentID && stored.globalID == inheritedGlobal
                        && stored.slot == slot && stored.dropZone == dropZone
                        && Self.sameChildIdentities(stored.node.children, source.children)
                } == true
                if !isConfirmed {
                    examinedCount += 1
                    var own = source.resolved(at: breakpoint, screens: framework.screens)
                    retainUtilityOverrides(in: &own)
                    own.children = source.children.map { child in
                        var identity = PartNode(id: child.id, type: child.type)
                        identity.slotID = child.slotID
                        return identity
                    }
                    let input = CanvasSceneInput(node: own, globalID: inheritedGlobal,
                        parentID: parentID, slot: slot, dropZone: dropZone)
                    if existing != input {
                        inputs[source.id] = input
                        rebuilt.append(source.id)
                    }
                }
                try collect(source.children, parentID: source.id, globalID: inheritedGlobal,
                            parentPackage: ownPackage, parentPath: path)
            }
        }
        try collect(page.parts)
        var artifacts = baseline?.artifacts ?? [:]
        let departed = inputs.keys.filter { !live.contains($0) }
        for id in departed {
            inputs.removeValue(forKey: id)
            artifacts.removeValue(forKey: id)
            paths.removeValue(forKey: id)
        }
        var html: [String: String] = [:]
        var styles: [String: String] = [:]
        var childMoves: [String: [[String]]] = [:]
        // Only the instances whose inputs actually changed need a new shell;
        // the rest are already carried forward with the tables.
        let shellRenderer = renderer.preparedForShells(environment: environment, liveIDs: live)
        for id in rebuilt {
            try Task.checkCancellation()
            guard let input = inputs[id] else { continue }
            let old = artifacts[id]
            let artifact = shellRenderer.renderShell(input, page: page, framework: framework, assets: assets)
            artifacts[id] = artifact
            if old?.html != artifact.html {
                // A parent whose own markup is intact keeps its element, and
                // with it every descendant already sitting under it.
                if let old, let moves = Self.childMoves(from: old.html, to: artifact.html) {
                    childMoves[id.uuidString] = moves
                } else {
                    html[id.uuidString] = artifact.html
                }
            }
            if old?.css != artifact.css { styles[id.uuidString] = artifact.css }
        }
        let roots = page.parts.map { $0.id.uuidString }
        let scene = Self(environment: environment, language: language, packages: packages,
            roots: roots, order: order, inputs: inputs, artifacts: artifacts, renderedInstanceCount: rebuilt.count,
            paths: paths, breakpoint: breakpoint, examinedInstanceCount: examinedCount)
        try Task.checkCancellation()
        guard let baseline, baseline.packages == packages,
              !roots.isEmpty, !baseline.roots.isEmpty else {
            return (scene, .page(renderer.renderSceneDocument(artifacts: artifacts, page: page,
                language: language, framework: framework, assets: assets, breakpoint: breakpoint)))
        }
        let removed = departed.map(\.uuidString)
        return (scene, .scene(.init(html: html, styles: styles, removed: removed,
            roots: roots == baseline.roots ? nil : roots,
            styleMoves: styleMoves(
                from: styleSequence(order: baseline.order, artifacts: baseline.artifacts),
                to: styleSequence(order: order, artifacts: artifacts)),
            childMoves: childMoves)))
    }

    /// Whether a stored input's child stubs still describe the live children.
    /// Compared field by field so confirming an untouched instance allocates
    /// nothing.
    private static func sameChildIdentities(_ stubs: [PartNode], _ sources: [PartNode]) -> Bool {
        guard stubs.count == sources.count else { return false }
        for index in stubs.indices {
            if stubs[index].id != sources[index].id
                || stubs[index].type != sources[index].type
                || stubs[index].slotID != sources[index].slotID { return false }
        }
        return true
    }

    /// A shell's own markup with its children lifted out. Children are only
    /// separable when they form one contiguous run; a shell that interleaves
    /// them with markup of its own has to be republished whole.
    private struct ShellChildren {
        let prefix: String
        let suffix: String
        let children: [String]
    }

    private static func shellChildren(in html: String) -> ShellChildren? {
        let opening = "<!--foundry-child:"
        guard let first = html.range(of: opening) else { return nil }
        var children: [String] = []
        var cursor = first.lowerBound
        while html[cursor...].hasPrefix(opening) {
            let identifier = html.index(cursor, offsetBy: opening.count)
            guard let close = html.range(of: "-->", range: identifier..<html.endIndex) else { return nil }
            children.append(String(html[identifier..<close.lowerBound]))
            cursor = close.upperBound
        }
        guard html.range(of: opening, range: cursor..<html.endIndex) == nil else { return nil }
        return ShellChildren(prefix: String(html[..<first.lowerBound]),
                             suffix: String(html[cursor...]), children: children)
    }

    /// Instructions that re-seat a parent's children where they already are,
    /// as `[childID, "before"|"after", siblingID]` triples. Republishing a
    /// parent's markup is what makes pasting cost more as a page fills up:
    /// the new parent element arrives empty, so every child it already had
    /// has to be moved back into it. Nil when the two shells differ by more
    /// than which children they host, or when there is no surviving sibling
    /// to anchor against — both cases republish the markup instead.
    static func childMoves(from old: String, to new: String) -> [[String]]? {
        guard let before = shellChildren(in: old), let after = shellChildren(in: new),
              before.prefix == after.prefix, before.suffix == after.suffix else { return nil }
        var targetIndices: [String: Int] = [:]
        targetIndices.reserveCapacity(after.children.count)
        for (index, id) in after.children.enumerated() { targetIndices[id] = index }
        let survivors = before.children.compactMap { targetIndices[$0] }
        let settled = Set(longestIncreasingSubsequence(survivors))
        guard let lastSettled = settled.max() else { return nil }
        var moves: [[String]] = []
        // Children past the last settled sibling follow their predecessor,
        // which is settled or was placed on the previous pass of this loop.
        for index in (lastSettled + 1)..<after.children.count {
            moves.append([after.children[index], "after", after.children[index - 1]])
        }
        // Children ahead of it precede their successor, on the same argument.
        for index in stride(from: lastSettled - 1, through: 0, by: -1) where !settled.contains(index) {
            moves.append([after.children[index], "before", after.children[index + 1]])
        }
        return moves
    }

    /// The instance stylesheets a fresh render emits, in document order. An
    /// instance with no CSS has no `<style>` element at all.
    private static func styleSequence(order: [UUID], artifacts: [UUID: CanvasSceneArtifact]) -> [UUID] {
        order.filter { artifacts[$0]?.css.isEmpty == false }
    }

    /// Instructions that turn `current` into `target` by moving as few
    /// stylesheets as possible. CSS source order is observable, so the canvas
    /// must match a fresh render exactly — but re-seating every sheet on every
    /// edit costs more than the edit itself once a page holds hundreds of
    /// instances. Everything already in a mutually consistent order stays put.
    ///
    /// Emitted back to front so each instruction's anchor is already sitting in
    /// its final position when the anchor is used.
    static func styleMoves(from current: [UUID], to target: [UUID]) -> [[String]] {
        var targetIndices: [UUID: Int] = [:]
        targetIndices.reserveCapacity(target.count)
        for (index, id) in target.enumerated() { targetIndices[id] = index }
        let survivors = current.compactMap { targetIndices[$0] }
        let settled = Set(longestIncreasingSubsequence(survivors))
        var moves: [[String]] = []
        for index in target.indices.reversed() where !settled.contains(index) {
            moves.append([target[index].uuidString,
                          index + 1 < target.count ? target[index + 1].uuidString : ""])
        }
        return moves
    }

    /// One longest strictly increasing subsequence of `values`, as its members.
    private static func longestIncreasingSubsequence(_ values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var tails: [Int] = []
        var predecessors = [Int](repeating: -1, count: values.count)
        for index in values.indices {
            var low = 0, high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if values[tails[middle]] < values[index] { low = middle + 1 } else { high = middle }
            }
            predecessors[index] = low > 0 ? tails[low - 1] : -1
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result: [Int] = []
        var cursor = tails[tails.count - 1]
        while cursor != -1 {
            result.append(values[cursor])
            cursor = predecessors[cursor]
        }
        return result
    }
}
