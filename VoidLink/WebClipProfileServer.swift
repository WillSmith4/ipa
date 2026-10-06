import Foundation
import Network

/// Serve one generated profile on loopback only. Safari requires an HTTP(S) URL;
/// this avoids a public upload, a private API, or an unsupported data: URL.
final class WebClipProfileServer {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.voidlink.webclip")
    private let path = "/" + UUID().uuidString + "/VoidLink.mobileconfig"
    private let profile: Data
    private var ready: ((Result<URL, Error>) -> Void)?

    init(profile: Data) { self.profile = profile }

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            self.ready = completion
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port,
                              let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.path)") else {
                            self.finish(.failure(ApplicationShortcutError.profileServer)); return
                        }
                        self.finish(.success(url))
                    case .failed(let error): self.finish(.failure(error)); self.stopOnQueue()
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 300) { [weak self] in self?.stopOnQueue() }
            } catch { self.finish(.failure(error)) }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }

    private func finish(_ result: Result<URL, Error>) {
        let callback = ready
        ready = nil
        DispatchQueue.main.async { callback?(result) }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        if ready != nil { finish(.failure(ApplicationShortcutError.profileServer)) }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        receive(connection, id: id, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in self?.close(id) }
    }

    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }

    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var request = accumulated
            if let data { request.append(data) }
            guard error == nil, request.count <= 8192 else { self.close(id); return }
            if request.range(of: Data("\r\n\r\n".utf8)) == nil {
                if complete { self.close(id) }
                else { self.receive(connection, id: id, accumulated: request) }
                return
            }
            let line = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")[0]
            let parts = line.split(separator: " ")
            let allowed = parts.count == 3 && (parts[0] == "GET" || parts[0] == "HEAD") && parts[1] == self.path
            let body = allowed ? self.profile : Data()
            let header = "HTTP/1.1 \(allowed ? "200 OK" : "404 Not Found")\r\nContent-Type: application/x-apple-aspen-config\r\nContent-Disposition: attachment; filename=\"VoidLink.mobileconfig\"\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            if parts.first != "HEAD" { response.append(body) }
            connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.close(id) })
        }
    }

    deinit { listener?.cancel(); for connection in connections.values { connection.cancel() } }
}
