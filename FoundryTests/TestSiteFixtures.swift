@testable import Foundry

enum TestSiteFixtures {
    static func populatedSite() -> Site {
        let container = BlockNode(
            type: .container,
            name: "Hero",
            children: [
                BlockNode(
                    type: .paragraph,
                    name: "Paragraph",
                    properties: [
                        .init(key: .init(rawValue: "content"), value: .string("Build something remarkable."))
                    ]
                ),
                BlockNode(
                    type: .button,
                    name: "Call to action",
                    properties: [
                        .init(key: .init(rawValue: "label"), value: .string("Get started")),
                        .init(key: .destination, value: .link(.init(destination: .url("#get-started"))))
                    ]
                )
            ]
        )
        return Site(
            name: "Test Site",
            pages: [Page(title: "Home", slug: "index", blocks: [container])]
        )
    }

    @MainActor
    static func populatedDocument() -> FoundryDocument {
        FoundryDocument(site: populatedSite())
    }
}
