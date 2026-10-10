import Foundation
import Testing
@testable import Foundry

/// The `foundry.` identifier prefix belongs to the app's own parts. Anything
/// else claiming it is rejected, so a third-party part can never shadow, or be
/// shadowed by, a built-in.
struct ReservedIdentifierTests {
    private func makePackage(identifier: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "Reserved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Resources"), withIntermediateDirectories: true)
        let manifest = """
        {"minimumAPIVersion":1,"id":"\(identifier)","title":"Reserved","version":"1.0.0",
         "description":"Test","group":"Content","inspector":[],"templates":{"html":"part.html"}}
        """
        try manifest.write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        try #"<p class="{{ part.class }}" {{ part.attributes }}>Hello</p>"#
            .write(to: root.appending(path: "Resources/part.html"), atomically: true, encoding: .utf8)
        return root
    }

    @Test(arguments: ["foundry.reserved.example", "foundry.content.heading", "Foundry.anything.at-all"])
    func partsOutsideTheAppCannotUseTheFoundryPrefix(_ identifier: String) throws {
        let url = try makePackage(identifier: identifier)
        defer { try? FileManager.default.removeItem(at: url) }
        let diagnostics = #expect(throws: PartPackageLoadingError.self) {
            try PartPackageLoader.loadWithDiagnostics(from: url)
        }
        guard case .invalid(let reported)? = diagnostics else {
            Issue.record("expected a validation rejection for \(identifier)")
            return
        }
        #expect(reported.contains { $0.location == "manifest.json:id" && $0.message.contains("reserved") })
    }

    @Test
    func ordinaryPrefixesAndTheAppsOwnPartsAreUnaffected() async throws {
        let url = try makePackage(identifier: "com.example.foundry-fan")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try PartPackageLoader.loadWithDiagnostics(from: url)
        #expect(!LoadedPartPackage.usesReservedIdentifier("com.example.foundry-fan", at: url))
        #expect(LoadedPartPackage.usesReservedIdentifier("foundry.x", at: url))

        // The bundled built-ins keep their names.
        await PartPackageCatalog.shared.waitUntilLoaded()
        #expect(PartType.image.definition.renderKind == .package)
        #expect(!LoadedPartPackage.usesReservedIdentifier(PartType.image.rawValue, at: PartType.image.definition.package!.rootURL))
    }
}
