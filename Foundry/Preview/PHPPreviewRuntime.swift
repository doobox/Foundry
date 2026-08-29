import Foundation

nonisolated struct PHPPreviewCGIRequest: Sendable {
    let method: String
    let scriptName: String
    let query: String
    let body: Data
    let contentType: String?

    init(
        method: String = "GET",
        scriptName: String,
        query: String = "",
        body: Data = Data(),
        contentType: String? = nil
    ) {
        self.method = method
        self.scriptName = scriptName
        self.query = query
        self.body = body
        self.contentType = contentType
    }
}

nonisolated struct PHPPreviewCGIResponse: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let diagnostics: String
}

nonisolated enum PHPPreviewRuntimeError: Error, LocalizedError {
    case unavailable(URL)
    case launchFailed(String)
    case executionFailed(Int32, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let url):
            "Foundry's bundled PHP runtime is unavailable at \(url.path)."
        case .launchFailed(let message):
            "The bundled PHP runtime could not be launched: \(message)"
        case .executionFailed(let status, let diagnostics):
            "PHP exited with status \(status). \(diagnostics)"
        case .invalidResponse:
            "PHP returned an invalid CGI response."
        }
    }
}

nonisolated struct PHPPreviewRuntime: Sendable {
    let executableURL: URL

    static func bundled(bundleURL: URL = Bundle.main.bundleURL) throws -> PHPPreviewRuntime {
        let executableURL = bundleURL.appending(path: "Contents/Helpers/PHP/php-cgi")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw PHPPreviewRuntimeError.unavailable(executableURL)
        }
        return PHPPreviewRuntime(executableURL: executableURL)
    }

    func execute(scriptURL: URL, request: PHPPreviewCGIRequest) async throws -> PHPPreviewCGIResponse {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = executableURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        process.environment = environment(scriptURL: scriptURL, request: request)

        do {
            try process.run()
        } catch {
            throw PHPPreviewRuntimeError.launchFailed(error.localizedDescription)
        }

        let outputTask = Task.detached { try outputPipe.fileHandleForReading.readToEnd() ?? Data() }
        let errorTask = Task.detached { try errorPipe.fileHandleForReading.readToEnd() ?? Data() }
        try inputPipe.fileHandleForWriting.write(contentsOf: request.body)
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        let output = try await outputTask.value
        let errorData = try await errorTask.value
        let diagnostics = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw PHPPreviewRuntimeError.executionFailed(process.terminationStatus, diagnostics)
        }
        return try parse(output, diagnostics: diagnostics)
    }

    private func environment(scriptURL: URL, request: PHPPreviewCGIRequest) -> [String: String] {
        var environment = [
            "GATEWAY_INTERFACE": "CGI/1.1",
            "REDIRECT_STATUS": "200",
            "REQUEST_METHOD": request.method,
            "SCRIPT_FILENAME": scriptURL.path,
            "SCRIPT_NAME": request.scriptName,
            "QUERY_STRING": request.query,
            "SERVER_NAME": "127.0.0.1",
            "SERVER_PORT": "80",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "SERVER_SOFTWARE": "Foundry",
            "DOCUMENT_ROOT": scriptURL.deletingLastPathComponent().path,
            "CONTENT_LENGTH": String(request.body.count)
        ]
        if let contentType = request.contentType { environment["CONTENT_TYPE"] = contentType }
        return environment
    }

    private func parse(_ data: Data, diagnostics: String) throws -> PHPPreviewCGIResponse {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator),
              let headerText = String(data: data[..<separatorRange.lowerBound], encoding: .utf8) else {
            throw PHPPreviewRuntimeError.invalidResponse
        }
        var statusCode = 200
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n") where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw PHPPreviewRuntimeError.invalidResponse }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if name.caseInsensitiveCompare("Status") == .orderedSame {
                statusCode = Int(value.split(separator: " ").first ?? "") ?? 200
            } else {
                headers[name] = value
            }
        }
        return PHPPreviewCGIResponse(
            statusCode: statusCode,
            headers: headers,
            body: Data(data[separatorRange.upperBound...]),
            diagnostics: diagnostics
        )
    }
}
