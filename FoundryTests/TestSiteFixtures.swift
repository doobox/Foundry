@testable import Foundry

enum TestSiteFixtures {
    static func populatedSite() -> Site {
        let container = PartNode(
            type: .container,
            name: "Hero",
            children: [
                PartNode(
                    type: .paragraph,
                    name: "Paragraph",
                    properties: [
                        .init(key: .init(rawValue: "content"), value: .string("Build something remarkable."))
                    ]
                ),
                PartNode(
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
            pages: [Page(title: "Home", slug: "index", parts: [container])]
        )
    }

    @MainActor
    static func populatedDocument() -> FoundryDocument {
        FoundryDocument(site: populatedSite())
    }
}
