import Foundation
import Testing
@testable import Foundry

struct PHPPreviewRuntimeTests {
    @Test
    func missingBundledRuntimeReportsItsExpectedLocation() {
        let bundleURL = URL(fileURLWithPath: "/tmp/FoundryMissingRuntime.app", isDirectory: true)

        do {
            _ = try PHPPreviewRuntime.bundled(bundleURL: bundleURL)
            Issue.record("Expected the missing runtime to throw.")
        } catch let PHPPreviewRuntimeError.unavailable(url) {
            #expect(url.path.hasSuffix("Contents/Resources/php-cgi"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func executesAndParsesCGIResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundryPHPTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let executableURL = directory.appending(path: "fake-php-cgi")
        let scriptURL = directory.appending(path: "index.php")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = """
        #!/bin/sh
        printf 'Status: 201 Created\r\nContent-Type: text/html; charset=utf-8\r\nX-Query: %s\r\n\r\n' "$QUERY_STRING"
        printf 'Rendered:'
        cat
        """
        try Data(executable.utf8).write(to: executableURL)
        try Data("<?php echo 'unused'; ?>".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let response = try await PHPPreviewRuntime(executableURL: executableURL).execute(
            scriptURL: scriptURL,
            request: .init(
                method: "POST",
                scriptName: "/index.php",
                query: "name=Foundry",
                body: Data("Hello".utf8),
                contentType: "text/plain"
            )
        )

        #expect(response.statusCode == 201)
        #expect(response.headers["Content-Type"] == "text/html; charset=utf-8")
        #expect(response.headers["X-Query"] == "name=Foundry")
        #expect(String(data: response.body, encoding: .utf8) == "Rendered:Hello")
    }
}
