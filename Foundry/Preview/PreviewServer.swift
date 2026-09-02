import Foundation
import Network

nonisolated let foundryPreviewSessionQueryName = "__foundry_session"

actor PreviewServer {
    static let shared = PreviewServer()

    private let queue = DispatchQueue(label: "uk.co.garysimpson.Foundry.preview-server")
    private var bundle = SiteExportBundle(files: [])
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startContinuation: CheckedContinuation<URL, any Error>?
    private var revision: UInt64 = 0
    private var documentRoot: URL?
    private struct EventStream {
        let connection: NWConnection
        let sessionID: UUID?
    }

    private var eventStreams: [UUID: EventStream] = [:]
    private var navigationAcknowledgements: Set<UUID> = []

    func publish(_ bundle: SiteExportBundle, notifyingClients: Bool = true) async throws -> URL {
        let nextRoot = FileManager.default.temporaryDirectory
            .appending(path: "FoundryPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
        try SiteExportWriter().write(bundle, to: nextRoot)
        let previousRoot = documentRoot
        documentRoot = nextRoot
        self.bundle = bundle
        revision &+= 1
        if notifyingClients {
            publishReloadEvent()
        }
        if let previousRoot {
            Task {
                try? await Task.sleep(for: .seconds(10))
                try? FileManager.default.removeItem(at: previousRoot)
            }
        }
        if let port, let url = serverURL(port: port) { return url }
        if startContinuation != nil {
            throw PreviewServerError.alreadyStarting
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.serve(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state) }
        }
        listener.start(queue: queue)

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let listenerPort = listener?.port else {
                failStart(PreviewServerError.missingPort)
                return
            }
            port = listenerPort
            guard let url = serverURL(port: listenerPort) else {
                failStart(PreviewServerError.invalidURL)
                return
            }
            startContinuation?.resume(returning: url)
            startContinuation = nil
        case .failed(let error):
            failStart(error)
        case .cancelled:
            failStart(PreviewServerError.cancelled)
        default:
            break
        }
    }

    private func failStart(_ error: any Error) {
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func serve(_ connection: NWConnection) {
        let currentBundle = bundle
        let currentRevision = revision
        let currentDocumentRoot = documentRoot
        connection.start(queue: queue)
        receiveRequest(
            on: connection,
            accumulated: Data(),
            bundle: currentBundle,
            documentRoot: currentDocumentRoot,
            revision: currentRevision
        )
    }

    private nonisolated func receiveRequest(
        on connection: NWConnection,
        accumulated: Data,
        bundle: SiteExportBundle,
        documentRoot: URL?,
        revision: UInt64
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var request = accumulated
            if let data { request.append(data) }
            if PreviewHTTPRequest.isComplete(request) || isComplete || error != nil || request.count >= 65_536 {
                Task {
                    if let parsedRequest = PreviewHTTPRequest(data: request),
                       parsedRequest.target == "/__foundry/events" {
                        await self.openEventStream(connection, request: parsedRequest)
                        return
                    }
                    if let parsedRequest = PreviewHTTPRequest(data: request),
                       parsedRequest.target == "/__foundry/navigation-ack" {
                        await self.acknowledgeNavigation(connection, request: parsedRequest)
                        return
                    }
                    let response = await self.phpResponse(
                        for: request,
                        bundle: bundle,
                        documentRoot: documentRoot,
                        revision: revision
                    ) ?? PreviewHTTPRouter.response(for: request, bundle: bundle, liveReloadRevision: revision)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            } else {
                self.receiveRequest(
                    on: connection,
                    accumulated: request,
                    bundle: bundle,
                    documentRoot: documentRoot,
                    revision: revision
                )
            }
        }
    }

    private func openEventStream(_ connection: NWConnection, request: PreviewHTTPRequest) {
        guard request.method == "GET" else {
            let response = Data("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        let streamID = UUID()
        let sessionID = request.queryValue(named: foundryPreviewSessionQueryName).flatMap(UUID.init(uuidString:))
        eventStreams[streamID] = EventStream(connection: connection, sessionID: sessionID)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                break
            default:
                return
            }
            Task { await self?.removeEventStream(streamID) }
        }
        let headers = Data("""
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        X-Content-Type-Options: nosniff\r
        \r
        retry: 1000\n
        \n
        """.utf8)
        connection.send(content: headers, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { await self?.removeEventStream(streamID) }
        })

        let clientRevision = request.queryValue(named: "revision").flatMap(UInt64.init)
        if clientRevision != revision {
            sendReloadEvent(to: connection)
        }
    }

    private func publishReloadEvent() {
        for stream in eventStreams.values {
            sendReloadEvent(to: stream.connection)
        }
    }

    func navigatePreview(sessionID: UUID, to target: String) async -> Bool {
        let matchingStreams = eventStreams.filter { $0.value.sessionID == sessionID }
        let navigationID = UUID()
        let navigation = PreviewNavigation(id: navigationID, target: target)
        guard !matchingStreams.isEmpty,
              let encodedTarget = try? JSONEncoder().encode(navigation),
              let payload = String(data: encodedTarget, encoding: .utf8) else { return false }
        let event = Data("event: navigate\ndata: \(payload)\n\n".utf8)
        var delivered = false
        for (streamID, stream) in matchingStreams {
            if await send(event, to: stream.connection) {
                delivered = true
            } else {
                stream.connection.cancel()
                removeEventStream(streamID)
            }
        }
        guard delivered else { return false }

        for _ in 0..<25 {
            if navigationAcknowledgements.remove(navigationID) != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        for (streamID, stream) in matchingStreams {
            stream.connection.cancel()
            removeEventStream(streamID)
        }
        navigationAcknowledgements.remove(navigationID)
        return false
    }

    private func send(_ content: Data, to connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: content, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func acknowledgeNavigation(_ connection: NWConnection, request: PreviewHTTPRequest) {
        guard request.method == "GET",
              let navigationID = request.queryValue(named: "id").flatMap(UUID.init(uuidString:)) else {
            let response = Data(
                "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
            )
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        navigationAcknowledgements.insert(navigationID)
        let response = Data(
            "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8
        )
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendReloadEvent(to connection: NWConnection) {
        let event = Data("event: reload\ndata: \(revision)\n\n".utf8)
        connection.send(content: event, completion: .contentProcessed { _ in })
    }

    private func removeEventStream(_ id: UUID) {
        eventStreams.removeValue(forKey: id)
    }

    private nonisolated func phpResponse(
        for requestData: Data,
        bundle: SiteExportBundle,
        documentRoot: URL?,
        revision: UInt64
    ) async -> Data? {
        guard let request = PreviewHTTPRequest(data: requestData),
              let path = PreviewHTTPRouter.resolvedBundlePath(request.target, bundle: bundle),
              path.hasSuffix(".php"),
              let documentRoot else { return nil }
        do {
            let runtime = try PHPPreviewRuntime.bundled()
            let result = try await runtime.execute(
                scriptURL: documentRoot.appending(path: path),
                request: .init(
                    method: request.method,
                    scriptName: "/" + path,
                    query: request.query,
                    body: request.body,
                    contentType: request.headers["content-type"]
                )
            )
            return PreviewHTTPRouter.response(
                for: result,
                method: request.method,
                revision: revision,
                sessionID: request.previewSessionID
            )
        } catch {
            return PreviewHTTPRouter.phpErrorResponse(error)
        }
    }

    private func serverURL(port: NWEndpoint.Port) -> URL? {
        URL(string: "http://127.0.0.1:\(port.rawValue)/")
    }
}

private nonisolated struct PreviewNavigation: Encodable {
    let id: UUID
    let target: String
}

nonisolated struct PreviewHTTPRequest: Sendable {
    let method: String
    let target: String
    let query: String
    let headers: [String: String]
    let body: Data

    var previewSessionID: UUID? {
        queryValue(named: foundryPreviewSessionQueryName).flatMap(UUID.init(uuidString:))
    }

    func queryValue(named name: String) -> String? {
        var components = URLComponents()
        components.percentEncodedQuery = query
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    init?(data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator),
              let header = String(data: data[..<separatorRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        let rawTarget = String(parts[1])
        let targetParts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        target = String(targetParts[0])
        query = targetParts.count == 2 ? String(targetParts[1]) : ""
        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            parsedHeaders[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        headers = parsedHeaders
        body = Data(data[separatorRange.upperBound...])
    }

    static func isComplete(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator),
              let header = String(data: data[..<separatorRange.lowerBound], encoding: .utf8) else { return false }
        let contentLength = header.components(separatedBy: "\r\n").dropFirst().compactMap { line -> Int? in
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Content-Length") == .orderedSame else { return nil }
            return Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        return data.count >= separatorRange.upperBound + contentLength
    }
}

nonisolated enum PreviewHTTPRouter {
    static func response(
        for request: Data,
        bundle: SiteExportBundle,
        liveReloadRevision: UInt64? = nil
    ) -> Data {
        guard let header = String(data: request, encoding: .utf8),
              let requestLine = header.components(separatedBy: "\r\n").first else {
            return response(status: "400 Bad Request", body: Data(), contentType: "text/plain")
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return response(status: "400 Bad Request", body: Data(), contentType: "text/plain")
        }
        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            return response(status: "405 Method Not Allowed", body: Data(), contentType: "text/plain")
        }
        let requestTarget = String(parts[1])
        guard safeBundlePath(requestTarget) != nil else {
            return response(status: "403 Forbidden", body: Data(), contentType: "text/plain")
        }
        guard let resolvedPath = resolvedBundlePath(requestTarget, bundle: bundle) else {
            return response(status: "404 Not Found", body: Data("Not Found".utf8), contentType: "text/plain")
        }
        guard let file = bundle.file(at: resolvedPath) else {
            return response(status: "404 Not Found", body: Data("Not Found".utf8), contentType: "text/plain")
        }
        let sessionID = PreviewHTTPRequest(data: request)?.previewSessionID
        let body = liveReloadRevision.map {
            liveReloadBody(for: file.data, path: resolvedPath, revision: $0, sessionID: sessionID)
        } ?? file.data
        return response(
            status: "200 OK",
            body: method == "HEAD" ? Data() : body,
            contentLength: body.count,
            contentType: mimeType(for: resolvedPath)
        )
    }

    static func resolvedBundlePath(_ requestTarget: String, bundle: SiteExportBundle) -> String? {
        guard let path = safeBundlePath(requestTarget) else { return nil }
        if bundle.file(at: path) != nil {
            return path
        } else if path.hasSuffix("index.html") {
            let phpPath = String(path.dropLast(4)) + "php"
            return bundle.file(at: phpPath) == nil ? nil : phpPath
        }
        return nil
    }

    static func response(
        for cgi: PHPPreviewCGIResponse,
        method: String,
        revision: UInt64,
        sessionID: UUID? = nil
    ) -> Data {
        let body = liveReloadBody(
            for: cgi.body,
            path: "index.php",
            revision: revision,
            sessionID: sessionID
        )
        let contentType = cgi.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
            ?? "text/html; charset=utf-8"
        let forwardedHeaders = cgi.headers.filter {
            !["content-type", "content-length", "connection", "transfer-encoding"]
                .contains($0.key.lowercased())
        }
        return response(
            status: "\(cgi.statusCode) \(statusReason(cgi.statusCode))",
            body: method == "HEAD" ? Data() : body,
            contentLength: body.count,
            contentType: contentType,
            additionalHeaders: forwardedHeaders
        )
    }

    static func phpErrorResponse(_ error: any Error) -> Data {
        let message = "PHP preview failed: \(error.localizedDescription)"
        return response(
            status: "500 Internal Server Error",
            body: Data(message.utf8),
            contentType: "text/plain; charset=utf-8"
        )
    }

    private static func statusReason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "PHP Response"
        }
    }

    private static func liveReloadBody(
        for data: Data,
        path: String,
        revision: UInt64,
        sessionID: UUID?
    ) -> Data {
        guard path.hasSuffix(".html") || path.hasSuffix(".php"),
              var html = String(data: data, encoding: .utf8) else { return data }
        let script = """
        <script>
        (() => {
          const revision = '\(revision)';
          const requestedSession = '\(sessionID?.uuidString ?? "")';
          if (requestedSession) sessionStorage.setItem('\(foundryPreviewSessionQueryName)', requestedSession);
          const session = requestedSession || sessionStorage.getItem('\(foundryPreviewSessionQueryName)') || '';
          const events = new EventSource('/__foundry/events?revision=' + encodeURIComponent(revision) + (session ? '&\(foundryPreviewSessionQueryName)=' + encodeURIComponent(session) : ''));
          events.addEventListener('reload', () => location.reload());
          events.addEventListener('navigate', async event => {
            const navigation = JSON.parse(event.data);
            try {
              await fetch('/__foundry/navigation-ack?id=' + encodeURIComponent(navigation.id), {
                cache: 'no-store'
              });
            } finally {
              const current = location.pathname + location.search;
              if (current === navigation.target) {
                location.reload();
              } else {
                location.assign(navigation.target);
              }
            }
          });
        })();
        </script>
        """
        if let bodyRange = html.range(of: "</body>", options: .caseInsensitive) {
            html.insert(contentsOf: script, at: bodyRange.lowerBound)
        } else {
            html.append(script)
        }
        return Data(html.utf8)
    }

    static func safeBundlePath(_ requestTarget: String) -> String? {
        let target = requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestTarget
        guard let decoded = target.removingPercentEncoding,
              !decoded.contains("\\"),
              !decoded.contains("\0") else { return nil }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else { return nil }
        var path = components.joined(separator: "/")
        if path.isEmpty || decoded.hasSuffix("/") { path += path.isEmpty ? "index.html" : "/index.html" }
        return path
    }

    private static func response(
        status: String,
        body: Data,
        contentLength: Int? = nil,
        contentType: String,
        additionalHeaders: [String: String] = [:]
    ) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(contentLength ?? body.count)\r\n"
        for (name, value) in additionalHeaders.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            header += "\(name): \(value)\r\n"
        }
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n"
        header += "X-Content-Type-Options: nosniff\r\n"
        header += "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "html", "php": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "gif": "image/gif"
        default: "application/octet-stream"
        }
    }
}

nonisolated enum PreviewServerError: LocalizedError {
    case alreadyStarting
    case missingPort
    case cancelled
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .alreadyStarting: "The preview server is already starting."
        case .missingPort: "The preview server started without an available port."
        case .cancelled: "The preview server was cancelled before it became ready."
        case .invalidURL: "The preview server could not create its local URL."
        }
    }
}
