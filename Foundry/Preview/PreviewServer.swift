import Foundation
import Network

actor PreviewServer {
    static let shared = PreviewServer()

    private let queue = DispatchQueue(label: "uk.co.garysimpson.Foundry.preview-server")
    private var bundle = SiteExportBundle(files: [])
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var startContinuation: CheckedContinuation<URL, any Error>?
    private var revision: UInt64 = 0

    func publish(_ bundle: SiteExportBundle) async throws -> URL {
        self.bundle = bundle
        revision &+= 1
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
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data(), bundle: currentBundle, revision: currentRevision)
    }

    private nonisolated func receiveRequest(
        on connection: NWConnection,
        accumulated: Data,
        bundle: SiteExportBundle,
        revision: UInt64
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var request = accumulated
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete || error != nil || request.count >= 65_536 {
                let response = PreviewHTTPRouter.response(for: request, bundle: bundle, liveReloadRevision: revision)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else {
                self.receiveRequest(on: connection, accumulated: request, bundle: bundle, revision: revision)
            }
        }
    }

    private func serverURL(port: NWEndpoint.Port) -> URL? {
        URL(string: "http://127.0.0.1:\(port.rawValue)/")
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
        if requestTarget.split(separator: "?", maxSplits: 1).first == "/__foundry/revision",
           let liveReloadRevision {
            let revisionData = Data(String(liveReloadRevision).utf8)
            return response(
                status: "200 OK",
                body: method == "HEAD" ? Data() : revisionData,
                contentLength: revisionData.count,
                contentType: "text/plain; charset=utf-8"
            )
        }
        guard let path = safeBundlePath(requestTarget) else {
            return response(status: "403 Forbidden", body: Data(), contentType: "text/plain")
        }
        let resolvedPath: String
        if bundle.file(at: path) != nil {
            resolvedPath = path
        } else if path.hasSuffix("index.html") {
            resolvedPath = String(path.dropLast(4)) + "php"
        } else {
            resolvedPath = path
        }
        guard let file = bundle.file(at: resolvedPath) else {
            return response(status: "404 Not Found", body: Data("Not Found".utf8), contentType: "text/plain")
        }
        let body = liveReloadRevision.map { liveReloadBody(for: file.data, path: resolvedPath, revision: $0) } ?? file.data
        return response(
            status: "200 OK",
            body: method == "HEAD" ? Data() : body,
            contentLength: body.count,
            contentType: mimeType(for: resolvedPath)
        )
    }

    private static func liveReloadBody(for data: Data, path: String, revision: UInt64) -> Data {
        guard path.hasSuffix(".html") || path.hasSuffix(".php"),
              var html = String(data: data, encoding: .utf8) else { return data }
        let script = """
        <script>
        (() => {
          const revision = '\(revision)';
          setInterval(async () => {
            try {
              const next = await fetch('/__foundry/revision', { cache: 'no-store' }).then(r => r.text());
              if (next !== revision) location.reload();
            } catch (_) {}
          }, 500);
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
        contentType: String
    ) -> Data {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(contentLength ?? body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        X-Content-Type-Options: nosniff\r
        \r

        """
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
