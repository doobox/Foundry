import Testing
@testable import Foundry

@Suite("Publishing")
struct PublishingTests {
    @Test
    func embeddedTransportIncludesSecurePublishingBackends() {
        let version = SitePublisher.transportVersion

        #expect(version.contains("libcurl/8.16.0"))
        #expect(version.contains("libssh2/1.11.1"))
        #expect(version.contains("mbedTLS/3.6.4"))
    }
}
