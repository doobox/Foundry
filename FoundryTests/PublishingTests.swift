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

    @Test
    func sftpRelativePathsResolveFromTheAccountHomeDirectory() {
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "ftp.example.com"
        site.publishingPort = 722
        site.publishingRemotePath = "public_html/test-site"

        let url = PublishingRemoteURLBuilder.url(site: site, relativePath: "index.html", testOnly: false)

        #expect(url == "sftp://ftp.example.com:722/~/public_html/test-site/index.html")
    }

    @Test
    func explicitLeadingSlashProducesAnAbsoluteSFTPPath() {
        var site = Site.starter()
        site.publishingDestination = .sftp
        site.publishingHost = "ftp.example.com"
        site.publishingRemotePath = "/srv/www"

        let url = PublishingRemoteURLBuilder.url(site: site, relativePath: "index.html", testOnly: false)

        #expect(url == "sftp://ftp.example.com:22/srv/www/index.html")
    }
}
