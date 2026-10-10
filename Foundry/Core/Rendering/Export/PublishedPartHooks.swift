import Foundation

/// Output hooks belong to authored CSS/behaviour, not to the editor. Plain
/// Bootstrap parts require none. Cross-part scripts and shared styles retain
/// identity across the page because their selectors can reach other parts.
nonisolated struct PublishedPartHooks {
    let retainsPageIdentity: Bool

    init(page: Page, site: Site) {
        let plan = PartArtifactPlan(page: page)
        let customCode = site.customCodeEnabled &&
            [site.headCode, site.bodyStartCode, site.bodyEndCode, site.analyticsCode]
                .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sharedSiteStyles = PartArtifactPlan.sitePackages(in: site).contains { !$0.siteCSS.isEmpty }
        retainsPageIdentity = customCode || sharedSiteStyles || plan.packages.contains { package in
            [package.instanceJavaScript, package.pageJavaScript,
             package.manifest.controlGroups.filter { $0.type != .background }.map(\.javaScript).joined(), package.pageCSS, package.siteCSS,
             package.instancePHP, package.pagePHP]
                .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                || !package.placedHTML.isEmpty
                || package.css.contains(":parent")
                || package.renderDefinition.controlGroupCSS.contains(":parent")
        } || plan.nodes.contains {
            !PartArtifactPlan.htmlArtifact(for: $0, suffix: "JavaScript").isEmpty
                || ($0.customCSS?.contains(":parent") == true)
                || PartArtifactPlan.htmlArtifact(for: $0, suffix: "CSS").contains(":parent")
        }
    }

    func requiresIdentity(for node: PartNode, package: LoadedPartPackage) -> Bool {
        retainsPageIdentity || [package.css, package.renderDefinition.controlGroupCSS,
            node.customCSS ?? "", PartArtifactPlan.htmlArtifact(for: node, suffix: "CSS")]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
