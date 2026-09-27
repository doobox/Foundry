import Foundation

/// A value snapshot of the last submitted scene. It is eligible as a baseline
/// only after WebKit acknowledges its revision. No background task mutates it.
nonisolated struct CanvasScene: Sendable {
    let environment: CanvasRenderCache.Environment
    let language: String
    let packages: [String]
    let roots: [String]
    let order: [String]
    let inputs: [UUID: CanvasSceneInput]
    let artifacts: [UUID: CanvasSceneArtifact]
    let renderedInstanceCount: Int
    let paths: [UUID: [Int]]
    let breakpoint: ResponsiveBreakpoint
    let examinedInstanceCount: Int

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
        let packages = (localIDs == nil ? nil : candidate?.packages)
            ?? PartArtifactPlan(page: page).packages.map { $0.manifest.identifier }
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
                var inputs = baseline.inputs, artifacts = baseline.artifacts
                var html: [String: String] = [:], styles: [String: String] = [:]
                var count = 0
                var addsStylesheet = false
                for (id, source) in targets {
                    try Task.checkCancellation()
                    guard let oldInput = inputs[id], let old = artifacts[id] else { continue }
                    var own = source.resolved(at: breakpoint, screens: framework.screens)
                    own.responsiveOverrides = nil
                    own.responsiveDefaults = nil
                    own.children = oldInput.node.children
                    let input = CanvasSceneInput(node: own, globalID: oldInput.globalID,
                        parentID: oldInput.parentID, slot: oldInput.slot, dropZone: oldInput.dropZone)
                    guard input != oldInput else { continue }
                    let artifact = renderer.renderShell(input, page: page, framework: framework, assets: assets)
                    inputs[id] = input; artifacts[id] = artifact; count += 1
                    if artifact.html != old.html { html[id.uuidString] = artifact.html }
                    if artifact.css != old.css { styles[id.uuidString] = artifact.css }
                    addsStylesheet = addsStylesheet || (old.css.isEmpty && !artifact.css.isEmpty)
                }
                try Task.checkCancellation()
                return (Self(environment: environment, language: language, packages: packages,
                    roots: baseline.roots, order: baseline.order, inputs: inputs, artifacts: artifacts,
                    renderedInstanceCount: count, paths: baseline.paths, breakpoint: breakpoint,
                    examinedInstanceCount: targets.count),
                    .scene(.init(html: html, styles: styles, removed: [], roots: nil,
                        styleOrder: addsStylesheet ? baseline.order : [])))
            }
        }
        var inputs: [UUID: CanvasSceneInput] = [:]
        var order: [String] = []
        var paths: [UUID: [Int]] = [:]
        func collect(_ nodes: [PartNode], parentID: UUID? = nil, globalID: UUID? = nil,
                     parentPackage: LoadedPartPackage? = nil, parentPath: [Int] = []) throws {
            for (index, source) in nodes.enumerated() {
                try Task.checkCancellation()
                order.append(source.id.uuidString)
                let path = parentPath + [index]
                paths[source.id] = path
                let inheritedGlobal = source.reusableDefinitionID ?? globalID
                let slot = parentPackage.flatMap { package in
                    if let id = source.slotID { return package.renderDefinition.slots.first { $0.id == id } }
                    return package.hasDropZone ? nil : package.renderDefinition.slots.first
                }
                let dropZone = parentPackage.flatMap { package -> String? in
                    guard slot == nil else { return nil }
                    return package.dropZoneNames.enumerated().first { index, name in
                        source.slotID == package.dropZoneSlotID(for: name) || (index == 0 && source.slotID == nil)
                    }.map { package.dropZoneSlotID(for: $0.element) }
                }
                var own = source.resolved(at: breakpoint, screens: framework.screens)
                own.responsiveOverrides = nil
                own.responsiveDefaults = nil
                own.children = source.children.map { child in
                    var identity = PartNode(id: child.id, type: child.type)
                    identity.slotID = child.slotID
                    return identity
                }
                inputs[source.id] = .init(node: own, globalID: inheritedGlobal,
                    parentID: parentID, slot: slot, dropZone: dropZone)
                try collect(source.children, parentID: source.id, globalID: inheritedGlobal,
                            parentPackage: source.type.definition.package, parentPath: path)
            }
        }
        try collect(page.parts)
        var artifacts: [UUID: CanvasSceneArtifact] = [:]
        var html: [String: String] = [:]
        var styles: [String: String] = [:]
        var renderedCount = 0
        for (id, input) in inputs {
            try Task.checkCancellation()
            let old = baseline?.artifacts[id]
            let artifact: CanvasSceneArtifact
            if baseline?.inputs[id] == input, let old {
                artifact = old
            } else {
                artifact = renderer.renderShell(input, page: page, framework: framework, assets: assets)
                renderedCount += 1
            }
            artifacts[id] = artifact
            if old?.html != artifact.html { html[id.uuidString] = artifact.html }
            if old?.css != artifact.css { styles[id.uuidString] = artifact.css }
        }
        let roots = page.parts.map { $0.id.uuidString }
        let scene = Self(environment: environment, language: language, packages: packages,
            roots: roots, order: order, inputs: inputs, artifacts: artifacts, renderedInstanceCount: renderedCount,
            paths: paths, breakpoint: breakpoint, examinedInstanceCount: inputs.count)
        try Task.checkCancellation()
        guard let baseline, baseline.packages == packages,
              !roots.isEmpty, !baseline.roots.isEmpty else {
            return (scene, .page(renderer.renderSceneDocument(artifacts: artifacts, page: page,
                language: language, framework: framework, assets: assets, breakpoint: breakpoint)))
        }
        let removed = baseline.inputs.keys.filter { inputs[$0] == nil }.map(\.uuidString)
        let addsStylesheet = styles.contains { id, css in
            guard !css.isEmpty, let uuid = UUID(uuidString: id) else { return false }
            return baseline.artifacts[uuid]?.css.isEmpty != false
        }
        return (scene, .scene(.init(html: html, styles: styles, removed: removed,
            roots: roots == baseline.roots ? nil : roots,
            styleOrder: order != baseline.order || addsStylesheet ? order : [])))
    }
}
