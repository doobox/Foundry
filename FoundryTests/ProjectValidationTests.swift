import Foundation
import Testing
@testable import Foundry

struct ProjectValidationTests {
    @Test
    func rejectsFutureSchemaVersion() throws {
        var site = Site.starter()
        site.schemaVersion = Site.currentSchemaVersion + 1
        let data = try FoundryDocument.encoder.encode(site)

        #expect(throws: ProjectValidationError.self) {
            try FoundryDocument.decodeProject(from: data)
        }
    }

    @Test
    func rejectsProjectWithoutPages() throws {
        let site = Site(name: "Empty", pages: [])
        let data = try FoundryDocument.encoder.encode(site)

        #expect(throws: ProjectValidationError.self) {
            try FoundryDocument.decodeProject(from: data)
        }
    }

    @Test
    func rejectsDuplicateSlugs() throws {
        var site = Site.starter()
        site.pages.append(Page(title: "Other", slug: "index"))
        let data = try FoundryDocument.encoder.encode(site)

        #expect(throws: ProjectValidationError.self) {
            try FoundryDocument.decodeProject(from: data)
        }
    }

    @Test
    func malformedJSONFailsDecoding() {
        let data = Data("{not-json}".utf8)

        #expect(throws: (any Error).self) {
            try FoundryDocument.decodeProject(from: data)
        }
    }
}
